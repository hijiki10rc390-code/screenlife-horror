"""ステージの素材パック（背景・人影・3段階の表情・重ね画像）を作る。外見を変えたいときは設定の文章を直して再実行する。

実行には CUDA 版の専用環境を使う。GPU のメモリが足りなくなるので、同時に2本走らせないこと。
  C:\\sd\\venv-cuda\\Scripts\\python.exe build_stage.py <設定.json> <工程> [番号]

工程:
  base     … 背景の候補を作る（base_seeds の分だけ）。見て選び、設定の base_image に書く
  ghost    … 人影の候補を作る（ghost_seeds の分だけ）。見て選ぶ
  react    … 表情3種（不安・怯え・恐怖）を作る
  figure   … 人影を黒背景で別に作る（figure_seeds）。暗くて狭い場所は描き足しが失敗するので、この合成方式を使う
  lure     … 誘惑の仕草（設定の lures）の差分を作る
  faces    … 表情のバリエーション（設定の faces: 名前・プロンプト・強さ・seeds）を作る。ゲームオーバー・ハッピーエンド用など
  outfit   … 衣装違いをインペイントで生成（設定の outfits: 名前・プロンプト・seeds）。表情は base のまま、衣装だけ描き換える
  pack     … 重ね画像を assets/stages/<id>/ に書き出す。番号 = 採用する人影の seed（figure_place があれば figure の seed）

設定の例は stages_src/stage2.src.json。
"""
import gc
import json
import os
import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionXLInpaintPipeline, StableDiffusionXLPipeline
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).parent
MODEL = os.environ.get("SD_MODEL", r"C:\sd\models-extra\RealVisXL_V5.0_fp16.safetensors")
# 年齢は明確に成人。若く見せる語は使わない（設定側の文章でも同じ）
ALWAYS_NEG = "nude, naked, topless, child, underage, teenager, schoolgirl, minor"


def load(kind):
    cls = StableDiffusionXLPipeline if kind == "txt2img" else StableDiffusionXLInpaintPipeline
    pipe = cls.from_single_file(MODEL, torch_dtype=torch.float16, use_safetensors=True)
    pipe.enable_model_cpu_offload()      # 8GB の VRAM に収める
    pipe.vae.enable_tiling()
    return pipe


def free(pipe):
    del pipe
    gc.collect()
    torch.cuda.empty_cache()


def inpaint(pipe, base, box, prompt, neg, strength, seed):
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rectangle(box, fill=255)
    g = torch.Generator("cuda").manual_seed(seed)
    return pipe(prompt=prompt, negative_prompt=neg + ", " + ALWAYS_NEG, image=base, mask_image=mask,
                strength=strength, num_inference_steps=30, guidance_scale=6.5,
                width=base.size[0], height=base.size[1], generator=g).images[0]


def sheet(paths, out, cell=(480, 270)):
    ims = [Image.open(p).resize(cell) for p in paths]
    s = Image.new("RGB", (cell[0] * 2, cell[1] * ((len(ims) + 1) // 2)))
    for i, im in enumerate(ims):
        s.paste(im, ((i % 2) * cell[0], (i // 2) * cell[1]))
    s.save(out)
    print("一覧:", out, flush=True)


def overlay(src, box, feather, out):
    """box の外側を透明にした重ね画像。範囲の外は元の背景がそのまま見える"""
    img = Image.open(src).convert("RGB")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rectangle(box, fill=255)
    rgba = img.convert("RGBA")
    rgba.putalpha(mask.filter(ImageFilter.GaussianBlur(feather)))
    rgba.save(out)
    print("保存:", out, flush=True)


_SESSION = None


def person_mask(img):
    """人物の輪郭（白=人物）を自動で切り出す。初回はモデルをダウンロードする"""
    global _SESSION
    from rembg import new_session, remove
    if _SESSION is None:
        _SESSION = new_session("u2net_human_seg")
    return remove(img, session=_SESSION, only_mask=True).convert("L")


def person_overlay(gen_path, base_path, box, feather, out):
    """表情・仕草の差分を、人物の輪郭の中だけ重ねる。四角で重ねると、描き直された背景まで変わって見える。
    新しい姿勢の輪郭と元の輪郭の和集合を使うので、腕などが動いても元の姿が残らない"""
    gen = Image.open(gen_path).convert("RGB")
    base = Image.open(base_path).convert("RGB")
    m = ImageChops.lighter(person_mask(gen), person_mask(base))
    m = m.filter(ImageFilter.MaxFilter(9))
    clip = Image.new("L", gen.size, 0)
    ImageDraw.Draw(clip).rectangle(box, fill=255)
    m = ImageChops.multiply(m, clip).filter(ImageFilter.GaussianBlur(max(2, feather // 3)))
    rgba = gen.convert("RGBA")
    rgba.putalpha(m)
    rgba.save(out)
    print("保存:", out, flush=True)


def figure_overlay_mask(src, place, feather, out, size=(1024, 576), clip_y=None, alpha_scale=1.0, tone=None):
    """明るい背景で撮った人物（暗い服でもよい）を、輪郭で切り出して place の中に重ねる。
    figure_overlay は「明るい部分=人物」と見なすので、暗い服の人物には使えない。こちらは輪郭の自動切り出しを使う"""
    x1, y1, x2, y2 = place
    fig = Image.open(src).convert("RGB")
    h = y2 - y1
    fig = fig.resize((int(fig.width * h / fig.height), h))
    m = person_mask(fig).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
    if tone:   # 部屋の光に馴染ませる: 暗くして環境光の色を混ぜ、少しぼかす
        dark = tone.get("dark", 0.5)
        tint = tuple(tone.get("tint", (70, 55, 90)))
        mix = tone.get("mix", 0.3)
        fig = fig.point(lambda v: int(v * dark))
        fig = Image.blend(fig, Image.new("RGB", fig.size, tint), mix).filter(ImageFilter.GaussianBlur(tone.get("blur", 1.2)))
    if alpha_scale < 1.0:
        m = m.point(lambda v: int(v * alpha_scale))
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    alpha = Image.new("L", size, 0)
    left = (x1 + x2) // 2 - fig.width // 2
    canvas.paste(fig.convert("RGBA"), (left, y1))
    alpha.paste(m, (left, y1))
    band = Image.new("L", size, 0)
    ImageDraw.Draw(band).rectangle((x1, y1, x2, y2), fill=255)
    a = ImageChops.multiply(alpha, band.filter(ImageFilter.GaussianBlur(feather)))
    if clip_y is not None:
        keep = Image.new("L", size, 0)
        ImageDraw.Draw(keep).rectangle((0, 0, size[0], clip_y), fill=255)
        a = ImageChops.multiply(a, keep.filter(ImageFilter.GaussianBlur(6)))
    canvas.putalpha(a)
    canvas.save(out)
    print("保存:", out, flush=True)


def figure_overlay(src, place, feather, out, size=(1024, 576), clip_y=None):
    """黒背景の人物画像を、暗い場所 place=[x1,y1,x2,y2] の中に重ねる。明るさをそのまま透明度にするので、
    暗い場所では人物だけが浮かぶ。place の幅で切り取るので、ドアの縁から覗くように見える"""
    x1, y1, x2, y2 = place
    fig = Image.open(src).convert("RGB")
    h = y2 - y1
    fig = fig.resize((int(fig.width * h / fig.height), h))
    # 背景の暗い灰色（明るさ50前後）は透明にし、人物の白い部分だけを残す
    lum = fig.convert("L").point(lambda v: max(0, min(255, int((v - 50) * 2.0))))
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    alpha = Image.new("L", size, 0)
    cx = (x1 + x2) // 2
    left = cx - fig.width // 2
    canvas.paste(fig.convert("RGBA"), (left, y1))
    alpha.paste(lum, (left, y1))
    band = Image.new("L", size, 0)
    ImageDraw.Draw(band).rectangle((x1, y1, x2, y2), fill=255)
    band = band.filter(ImageFilter.GaussianBlur(feather))
    a = ImageChops.multiply(alpha, band)
    if clip_y is not None:   # 手前の物（ノートPCなど）の後ろに立っているように、これより下を隠す
        keep = Image.new("L", size, 0)
        ImageDraw.Draw(keep).rectangle((0, 0, size[0], clip_y), fill=255)
        a = ImageChops.multiply(a, keep.filter(ImageFilter.GaussianBlur(6)))
    canvas.putalpha(a)
    canvas.save(out)
    print("保存:", out, flush=True)


def main():
    spec = json.load(open(sys.argv[1], encoding="utf-8"))
    step = sys.argv[2]
    sid = spec["id"]
    work = ROOT / "outputs" / "stages_build" / sid
    work.mkdir(parents=True, exist_ok=True)

    if step == "base":
        pipe = load("txt2img")
        paths = []
        for seed in spec["base_seeds"]:
            g = torch.Generator("cuda").manual_seed(seed)
            img = pipe(spec["base_prompt"], negative_prompt=spec["base_neg"] + ", " + ALWAYS_NEG, width=1024, height=576,
                       num_inference_steps=28, guidance_scale=6.5, generator=g).images[0]
            p = work / f"base_{seed}.png"
            img.save(p)
            paths.append(p)
            print("保存:", p, flush=True)
        sheet(paths, work / "sheet_base.png")

    elif step == "ghost":
        base = Image.open(ROOT / spec["base_image"]).convert("RGB")
        pipe = load("inpaint")
        paths = [ROOT / spec["base_image"]]
        for seed in spec["ghost_seeds"]:
            img = inpaint(pipe, base, spec["ghost_box"], spec["ghost_prompt"] + ", " + spec["style"],
                          spec["ghost_neg"], spec.get("ghost_strength", 0.92), seed)
            p = work / f"ghost_{seed}.png"
            img.save(p)
            paths.append(p)
            print("保存:", p, flush=True)
        sheet(paths, work / "sheet_ghost.png")

    elif step == "react":
        base = Image.open(ROOT / spec["base_image"]).convert("RGB")
        pipe = load("inpaint")
        subj, pron = spec["subject"], spec["pronoun"]
        reacts = {
            "uneasy": (f"{subj}, eyes glancing nervously to the side toward the dark, uneasy tense expression", 0.5),
            "scared": (f"{subj}, head turned looking over {pron} shoulder, wide frightened eyes, mouth slightly open", 0.6),
            "terror": (f"{subj}, both hands pressed over {pron} mouth, wide terrified eyes staring, panic", 0.7),
        }
        paths = [ROOT / spec["base_image"]]
        for name, (prompt, strength) in reacts.items():
            img = inpaint(pipe, base, spec["body_box"], prompt + ", " + spec["style"], spec["react_neg"],
                          strength, spec.get("react_seed", 40))
            p = work / f"react_{name}.png"
            img.save(p)
            paths.append(p)
            print("保存:", p, flush=True)
        sheet(paths, work / "sheet_react.png")

    elif step == "lure":
        base = Image.open(ROOT / spec["base_image"]).convert("RGB")
        pipe = load("inpaint")
        paths = [ROOT / spec["base_image"]]
        for lure in spec["lures"]:
            prompt = f"{spec['subject']}, {lure['prompt']}, {spec['style']}"
            img = inpaint(pipe, base, spec.get("lure_box", spec["body_box"]), prompt, spec["react_neg"],
                          lure.get("strength", 0.7), spec.get("react_seed", 40))
            p = work / f"lure_{lure['name']}.png"
            img.save(p)
            paths.append(p)
            print("保存:", p, flush=True)
        sheet(paths, work / "sheet_lure.png")

    elif step == "faces":
        base = Image.open(ROOT / spec["base_image"]).convert("RGB")
        pipe = load("inpaint")
        paths = [ROOT / spec["base_image"]]
        for face in spec["faces"]:
            prompt = f"{spec['subject']}, {face['prompt']}, {spec['style']}"
            for seed in face.get("seeds", [spec.get("react_seed", 40)]):
                img = inpaint(pipe, base, spec.get("lure_box", spec["body_box"]), prompt, spec["react_neg"],
                              face.get("strength", 0.7), seed)
                p = work / f"face_{face['name']}_{seed}.png"
                img.save(p)
                paths.append(p)
                print("保存:", p, flush=True)
        sheet(paths, work / "sheet_faces.png", cell=(400, 225))

    elif step == "figure":
        pipe = load("txt2img")
        paths = []
        for seed in spec["figure_seeds"]:
            g = torch.Generator("cuda").manual_seed(seed)
            img = pipe(spec["figure_prompt"], negative_prompt=spec["figure_neg"], width=832, height=1216,
                       num_inference_steps=28, guidance_scale=6.5, generator=g).images[0]
            p = work / f"figure_{seed}.png"
            img.save(p)
            paths.append(p)
            print("保存:", p, flush=True)
        sheet(paths, work / "sheet_figure.png", cell=(300, 438))

    elif step == "outfit":
        # 衣装違い生成: 既存の base_image をベースに、複数衣装をインペイントで生成
        # 設定形式:
        #   "base_image": 既存の base 画像へのパス
        #   "outfits": [{"name": "pajamas", "prompt": "...", "seeds": [...], "strength": 0.7}, ...]
        #   "body_box": 衣装を描き換える範囲 [x1, y1, x2, y2]
        base = Image.open(ROOT / spec["base_image"]).convert("RGB")
        pipe = load("inpaint")
        paths = [ROOT / spec["base_image"]]
        for outfit in spec["outfits"]:
            prompt = f"{spec['subject']}, {outfit['prompt']}, {spec['style']}"
            for seed in outfit.get("seeds", [spec.get("react_seed", 40)]):
                img = inpaint(pipe, base, spec["body_box"], prompt, spec.get("react_neg", ""),
                              outfit.get("strength", 0.6), seed)
                p = work / f"outfit_{outfit['name']}_{seed}.png"
                img.save(p)
                paths.append(p)
                print("保存:", p, flush=True)
        sheet(paths, work / "sheet_outfit.png")

    elif step == "pack":
        seed = int(sys.argv[3])
        out = ROOT / "assets" / "stages" / sid
        out.mkdir(parents=True, exist_ok=True)
        Image.open(ROOT / spec["base_image"]).convert("RGB").save(out / "base.png")
        ov = spec["overlay"]
        if "figure_place" in spec and spec.get("figure_mode") == "mask":
            figure_overlay_mask(work / f"figure_{seed}.png", spec["figure_place"], ov["feather"], out / "ghost_overlay.png",
                                clip_y=spec.get("figure_clip_y"), alpha_scale=spec.get("figure_alpha", 1.0),
                                tone=spec.get("figure_tone"))
        elif "figure_place" in spec:
            figure_overlay(work / f"figure_{seed}.png", spec["figure_place"], ov["feather"], out / "ghost_overlay.png", clip_y=spec.get("figure_clip_y"))
        else:
            overlay(work / f"ghost_{seed}.png", ov["ghost_box"], ov["feather"], out / "ghost_overlay.png")
        for name in ("uneasy", "scared", "terror"):
            if spec.get("person_mask", True):
                person_overlay(work / f"react_{name}.png", ROOT / spec["base_image"], ov["body_box"], ov["feather"], out / f"react_{name}.png")
            else:
                overlay(work / f"react_{name}.png", ov["body_box"], ov["feather"] + 4, out / f"react_{name}.png")
        lb = ov.get("lure_box", ov["body_box"])
        for lure in spec.get("lures", []):
            if spec.get("person_mask", True):
                person_overlay(work / f"lure_{lure['name']}.png", ROOT / spec["base_image"], lb, ov["feather"], out / f"lure_{lure['name']}.png")
            else:
                overlay(work / f"lure_{lure['name']}.png", lb, ov["feather"] + 4, out / f"lure_{lure['name']}.png")
        print("素材パック:", out)

    else:
        print(__doc__)


if __name__ == "__main__":
    main()

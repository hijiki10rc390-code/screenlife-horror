"""SDXL（diffusers・GPU）で、通話の背景画像と「異変の映り込み」を試す検証スクリプト。

実行には CUDA 版 PyTorch を入れた専用環境を使う（A1111 の venv は CPU 版で使えない）:
  C:\\sd\\venv-cuda\\Scripts\\python.exe sd_test.py rooms [枚数]
  C:\\sd\\venv-cuda\\Scripts\\python.exe sd_test.py ghost <画像> <x1,y1,x2,y2> [プロンプト]

モデルは A1111 と共用: C:\\sd\\stable-diffusion-webui\\models\\Stable-diffusion\\sd_xl_base_1.0.safetensors
"""
import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionXLImg2ImgPipeline, StableDiffusionXLInpaintPipeline, StableDiffusionXLPipeline
from PIL import Image, ImageDraw

import os

# 既定は実写特化の RealVisXL。標準 SDXL を使うときは SD_MODEL に別パスを指定する
MODEL = os.environ.get("SD_MODEL", r"C:\sd\models-extra\RealVisXL_V5.0_fp16.safetensors")
OUT = Path(__file__).parent / "outputs" / "sd"
OUT.mkdir(parents=True, exist_ok=True)

STYLE = ("candid photograph taken with a cheap laptop webcam at night, dim ordinary apartment bedroom, "
         "single warm lamp, dark corners, grainy, realistic, amateur photo")
NEG = ("people, person, face, text, watermark, cartoon, anime, illustration, drawing, ink, comic, monochrome, "
       "black and white, painting, cgi, 3d render, bright, screenshot, user interface, window frame, border")
PERSON = ("a young japanese woman in a hoodie sitting in front of the camera looking at the screen, "
          "candid photograph taken with a cheap laptop webcam at night, dim apartment bedroom behind her, "
          "single warm lamp, grainy, realistic, amateur photo")
PERSON_NEG = ("text, watermark, cartoon, anime, illustration, drawing, painting, cgi, 3d render, bright, "
              "screenshot, user interface, window frame, border, deformed face, extra fingers")


def load_pipe() -> StableDiffusionXLPipeline:
    pipe = StableDiffusionXLPipeline.from_single_file(MODEL, torch_dtype=torch.float16, use_safetensors=True)
    pipe.enable_model_cpu_offload()   # 8GB の VRAM に収めるため
    pipe.vae.enable_tiling()
    return pipe


def rooms(n: int) -> None:
    pipe = load_pipe()
    for i in range(n):
        g = torch.Generator("cuda").manual_seed(1000 + i)
        img = pipe(STYLE, negative_prompt=NEG, width=1024, height=576, num_inference_steps=28,
                   guidance_scale=6.5, generator=g).images[0]
        p = OUT / f"room_{i}.png"
        img.save(p)
        print("保存:", p, flush=True)


SCENE = ("a young japanese woman in a hoodie sitting at a desk, facing the camera, "
         "behind her on the left is an open dark doorway leading to a black hallway, "
         "candid photograph taken with a cheap laptop webcam at night, dim apartment bedroom, "
         "single warm lamp, grainy, realistic, amateur photo")


SCENE2 = ("a young japanese man in a plain t-shirt sitting at a desk, facing the camera, "
          "behind him a large window showing the dark night outside, curtains half open, "
          "candid photograph taken with a cheap laptop webcam at night, dim apartment room, "
          "single desk lamp, grainy, realistic, amateur photo")


SCENE3 = ("a cute young japanese woman in her early twenties, adult, long dark hair, wearing loose casual loungewear "
          "(an off-shoulder camisole top and short shorts), sitting at a desk facing the camera, "
          "behind her on the left is an open doorway leading to a dark hallway with a faint light far away, "
          "candid photograph taken with a cheap laptop webcam at night, dim apartment bedroom, warm lamp, "
          "grainy, realistic, amateur photo")
SCENE3_NEG = ("text, watermark, cartoon, anime, illustration, drawing, painting, cgi, 3d render, bright, "
              "screenshot, user interface, window frame, border, deformed face, extra fingers, "
              "nude, naked, topless, child, underage, teenager, school uniform")


SCENE4 = ("a cute girl-next-door japanese woman streamer in her early twenties, adult, natural makeup, "
          "hair in a loose messy ponytail, wearing a gaming headset with a microphone, "
          "an oversized pastel t-shirt and casual shorts, sitting in a gaming chair at a desk, facing the camera, "
          "streaming room with a purple and blue LED strip glow and a monitor, "
          "behind her on the right is an open doorway leading to a dark hallway with a faint light far away, "
          "candid photograph taken with a cheap webcam at night, grainy, realistic, amateur photo")
SCENE4_NEG = ("text, watermark, cartoon, anime, illustration, drawing, painting, cgi, 3d render, bright, "
              "screenshot, user interface, window frame, border, deformed face, extra fingers, "
              "glamorous, nightclub, hostess, evening dress, heavy makeup, glossy lips, cleavage, high heels, "
              "nude, naked, topless, child, underage, teenager, school uniform")


SCENE5 = ("a cute girl-next-door japanese woman streamer in her early twenties, adult, natural makeup, "
          "hair in a loose messy ponytail, wearing a gaming headset with a microphone, "
          "an oversized pastel t-shirt, sitting in a gaming chair facing the camera, centered, medium shot, "
          "the room lights are off, only a dim purple LED strip and the monitor glow, deep shadows, dark room, "
          "behind her an open doorway into a pitch black hallway, "
          "candid photograph taken with a cheap webcam at night, underexposed, grainy, realistic, amateur photo")


SCENE6 = ("a cute girl-next-door japanese woman streamer in her early twenties, adult, natural makeup, "
          "hair in a loose messy ponytail, wearing a gaming headset with a microphone, "
          "a plain camisole bra top and dolphin shorts (short loose athletic shorts with curved side hems) as loungewear, "
          "sitting in a gaming chair facing the camera, centered, medium shot, "
          "the room lights are off, only a dim purple LED strip and the monitor glow, deep shadows, dark room, "
          "behind her an open doorway into a pitch black hallway, "
          "candid photograph taken with a cheap webcam at night, underexposed, grainy, realistic, amateur photo")


# SDXL は約77トークンを超えると後ろが切り捨てられる。暗さと構図は先頭に置き、短く書く
SCENE7 = ("dark night photo from a cheap webcam, grainy, underexposed: a cute japanese woman streamer in her 20s, "
          "gaming headset, camisole top, dolphin shorts, sitting in a gaming chair facing the camera, "
          "black room, dim purple LED glow, open dark doorway behind her")
SCENE7_NEG = ("bright, daylight, sofa, white wall, living room, cartoon, anime, text, watermark, nude, child, "
              "heavy makeup, side view, deformed face")


SCENE8 = ("dark night photo from a cheap webcam, grainy, underexposed: a cute soft japanese woman streamer in her 20s, "
          "twin tails with ribbons, cat-ear gaming headset, camisole top, dolphin shorts, "
          "sitting in a gaming chair facing the camera, black room, dim pink LED glow, open dark doorway behind her")


SCENE9 = ("dark night photo from a cheap webcam, grainy, underexposed: a cute soft japanese woman streamer in her 20s, "
          "twin tails with ribbons, black cat-ear gaming headset, camisole top, dolphin shorts, "
          "sitting in a gaming chair facing the camera, ordinary dark bedroom, faint monitor glow, "
          "open dark doorway behind her")


# 顔の印象を若く柔らかく（成人の範囲で）。77トークンを超えないよう短く書く
SCENE10 = ("dark night webcam photo, grainy: fresh-faced cute japanese woman in her early 20s, big eyes, soft cheeks, "
           "gentle smile, twin tails with ribbons, black cat-ear headset, camisole top, dolphin shorts, "
           "gaming chair, dark bedroom, faint monitor glow, open dark doorway behind her")
SCENE10_NEG = (SCENE7_NEG + ", neon, pink glow, colorful lights, wrinkles, tired eyes, dark circles, aged, "
               "middle-aged, thick eyebrows, nasolabial folds, harsh shadows on face, child, teenager")


# 成人と明確にわかる見た目にする（若く見せる語は使わない）。配信の定番: バストアップ・顔に前から柔らかい光
SCENE11 = ("dark night webcam photo, grainy, bust-up shot, soft light on her face: beautiful adult japanese woman, "
           "25 years old, long straight black hair, gentle smile, black cat-ear headset, camisole top, dolphin shorts, "
           "gaming chair, dark bedroom, faint monitor glow, open dark doorway behind her")
SCENE11_NEG = (SCENE7_NEG + ", neon, pink glow, colorful lights, wrinkles, tired eyes, dark circles, aged, "
               "childlike, young-looking, schoolgirl, minor, teenager, child, twin tails, ribbon, flash photography, "
               "wide angle distortion")


def persons(n: int, prompt: str = PERSON, prefix: str = "person", seed0: int = 2000) -> None:
    pipe = load_pipe()
    for i in range(n):
        g = torch.Generator("cuda").manual_seed(seed0 + i)
        img = pipe(prompt, negative_prompt=PERSON_NEG, width=1024, height=576, num_inference_steps=28,
                   guidance_scale=6.5, generator=g).images[0]
        p = OUT / f"{prefix}_{i}.png"
        img.save(p)
        print("保存:", p, flush=True)


# 人物の指定は環境変数で切り替える（既定は 1 つ目の通話の女性）
SUBJECT = os.environ.get("REACT_SUBJECT", "a young japanese woman with east asian features, black hair, grey hoodie with the hood up")
PRON = os.environ.get("REACT_PRON", "her")
REACTS = {
    "uneasy": (f"{SUBJECT}, eyes glancing nervously to the right toward the dark, uneasy tense expression", 0.5),
    "scared": (f"{SUBJECT}, head turned to the right looking over {PRON} shoulder, wide frightened eyes, mouth slightly open", 0.6),
    "terror": (f"{SUBJECT}, both hands pressed over {PRON} mouth, wide terrified eyes staring to the right, panic", 0.7),
}
REACT_PREFIX = os.environ.get("REACT_PREFIX", "react")


def react(src: str, box: str, seeds: int) -> None:
    """同じ人物の表情・向きだけを変えた画像を作る（上半身を範囲指定して描き直す）"""
    base = Image.open(src).convert("RGB")
    x1, y1, x2, y2 = (int(v) for v in box.split(","))
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rectangle((x1, y1, x2, y2), fill=255)
    pipe = StableDiffusionXLInpaintPipeline.from_single_file(MODEL, torch_dtype=torch.float16, use_safetensors=True)
    pipe.enable_model_cpu_offload()
    for name, (prompt, strength) in REACTS.items():
        for s in range(seeds):
            g = torch.Generator("cuda").manual_seed(40 + s)
            img = pipe(prompt=prompt + ", " + STYLE, negative_prompt="text, watermark, cartoon, anime, bright, colorful",
                       image=base, mask_image=mask, strength=strength, num_inference_steps=30, guidance_scale=6.5,
                       width=base.size[0], height=base.size[1], generator=g).images[0]
            p = OUT / f"{REACT_PREFIX}_{name}_{s}.png"
            img.save(p)
            print("保存:", p, flush=True)


def ghost(src: str, box: str, prompt: str) -> None:
    base = Image.open(src).convert("RGB")
    x1, y1, x2, y2 = (int(v) for v in box.split(","))
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rectangle((x1, y1, x2, y2), fill=255)
    pipe = StableDiffusionXLInpaintPipeline.from_single_file(MODEL, torch_dtype=torch.float16, use_safetensors=True)
    pipe.enable_model_cpu_offload()
    g = torch.Generator("cuda").manual_seed(int(os.environ.get("GHOST_SEED", "7")))
    img = pipe(prompt=prompt + ", " + STYLE, negative_prompt="text, watermark, cartoon, anime, bright, colorful",
               image=base, mask_image=mask, strength=float(os.environ.get("GHOST_STRENGTH", "0.9")),
               num_inference_steps=30, guidance_scale=6.5,
               width=base.size[0], height=base.size[1], generator=g).images[0]
    p = OUT / (Path(src).stem + "_ghost" + os.environ.get("GHOST_SUFFIX", "") + ".png")
    img.save(p)
    print("保存:", p, flush=True)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "rooms":
        rooms(int(sys.argv[2]) if len(sys.argv) > 2 else 4)
    elif len(sys.argv) >= 3 and sys.argv[1] == "react":
        react(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "330,170,600,480", 2)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes":
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 6, SCENE, "scene", 3000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes11":
        PERSON_NEG = SCENE11_NEG
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE11, "scene11", 13000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes10":
        PERSON_NEG = SCENE10_NEG
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE10, "scene10", 12000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes9":
        PERSON_NEG = SCENE7_NEG + ", neon, pink glow, colorful lights, glowing, purple light"
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE9, "scene9", 11000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes8":
        PERSON_NEG = SCENE7_NEG
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE8, "scene8", 10000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes7":
        PERSON_NEG = SCENE7_NEG
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE7, "scene7", 9000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes6":
        PERSON_NEG = SCENE4_NEG.replace("cleavage, ", "") + ", cleavage, lingerie, underwear, bright room, overexposed, side view, profile"
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE6, "scene6", 8000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes5":
        PERSON_NEG = SCENE4_NEG + ", bright room, overexposed, side view, profile"
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE5, "scene5", 7000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes4":
        PERSON_NEG = SCENE4_NEG
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE4, "scene4", 6000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes3":
        PERSON_NEG = SCENE3_NEG
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 8, SCENE3, "scene3", 5000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scenes2":
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 6, SCENE2, "scene2", 4000)
    elif len(sys.argv) >= 2 and sys.argv[1] == "persons":
        persons(int(sys.argv[2]) if len(sys.argv) > 2 else 4)
    elif len(sys.argv) >= 4 and sys.argv[1] == "ghost":
        ghost(sys.argv[2], sys.argv[3],
              sys.argv[4] if len(sys.argv) > 4 else "a tall pale figure standing motionless in the dark, thin silhouette, faint face")
    else:
        print(__doc__)

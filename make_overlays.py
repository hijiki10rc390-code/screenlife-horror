"""生成画像から、Godot で重ねる透過 PNG（assets/scene/）を作る。
  - ghost_overlay.png   … 背後の人影（base_ghost.png の人影の範囲だけ）
  - react_*.png          … 相手の表情の差分（上半身の範囲だけ）
範囲の外はアルファ 0 なので、元の背景と継ぎ目なく重なる。実行: python make_overlays.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).parent
SD = ROOT / "outputs" / "sd"
OUT = ROOT / "assets" / "scene"
OUT.mkdir(parents=True, exist_ok=True)

# 元画像（人影なし・表情の差分なし）。
base = Image.open(SD / "base.png").convert("RGB")
base.save(OUT / "base.png")


def overlay(src: str, box: tuple, feather: int, name: str) -> None:
    img = Image.open(SD / src).convert("RGB")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rectangle(box, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather))
    out = img.convert("RGBA")
    out.putalpha(mask)
    out.save(OUT / name)
    print("保存:", OUT / name)


overlay("base_ghost.png", (590, 20, 810, 450), 14, "ghost_overlay.png")
# 相手の上半身。ノートPCの上端（y≒366）より下は含めない
BODY = (335, 170, 610, 372)
overlay("react_uneasy_0.png", BODY, 18, "react_uneasy.png")
overlay("react_scared_0.png", BODY, 18, "react_scared.png")
overlay("react_terror_0.png", BODY, 18, "react_terror.png")

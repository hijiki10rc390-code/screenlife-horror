"""lunge 姿の ghost 画像を、ghost_face の位置に正しく合わせて ghost_overlay.png を作る。

背景は透明。lunge 中は face_fx の face 座標（ghost_face）に合わせて位置が決まるので、
ここで作る画像で顔の x/y を一致させておくと、襲いかかり時の顔のブレがなくなる。

使い方:
    python tools/align_lunge_overlay.py <figure.png> <output.png> <ghost_face_x> <ghost_face_y>

引数:
    figure.png   : 入力の lunge figure（SDXL 生成直後の 832x1216 など）
    output.png   : 出力ファイル（1024x576、透明 PNG）
    ghost_face_x : stage JSON の ghost_face[0]（映像 1024x576 座標系）
    ghost_face_y : stage JSON の ghost_face[1]
"""
import sys
from pathlib import Path
from PIL import Image


CANVAS_W = 1024
CANVAS_H = 576


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)

    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    fx = float(sys.argv[3])
    fy = float(sys.argv[4])

    # figure を顔中心 (fx, fy) に配置する。大きさは ghost_box 程度（縦 560 に収まる）
    fig = Image.open(src).convert("RGBA")
    target_h = 560
    scale = target_h / fig.height
    fig_resized = fig.resize((int(fig.width * scale), target_h), Image.LANCZOS)

    # 配置: 顔が (fx, fy) に来るように
    # 顔の y は画像の上から 25%（頭部）
    head_y = int(fig_resized.height * 0.18)
    head_x = int(fig_resized.width * 0.5)
    left = int(fx - head_x)
    top = int(fy - head_y)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.paste(fig_resized, (left, top), fig_resized)
    canvas.save(out)
    print(f"保存: {out}  face=({fx},{fy})  size={fig_resized.size}  pos=({left},{top})")


if __name__ == "__main__":
    main()
"""恐怖顔の生成画像を person_overlay で切り抜いて、既存の react_scared.png に適用する。

使い方:
    python tools/apply_strong_fear.py <face.png> <output.png> <base.png> <body_box>

引数:
    face.png   : faces 工程で生成した恐怖顔（kawaii base + 恐怖表情）
    output.png : 出力ファイル（react_scared.png など。既存ファイルを上書き）
    base.png   : 切り抜き用マスクの基準（元の base と同じ人物）
    body_box   : 人物の範囲 [x1, y1, x2, y2]
"""
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

# build_stage.py の person_mask を再実装
try:
    from build_stage import person_mask
except ImportError:
    # build_stage.py から関数を import できない時のフォールバック
    def person_mask(img):
        global _SESSION
        from rembg import new_session, remove
        if '_SESSION' not in globals() or _SESSION is None:
            _SESSION = new_session("u2net_human_seg")
        return remove(img, session=_SESSION, only_mask=True).convert("L")


def person_overlay(gen_path, base_path, box, feather, out):
    """build_stage.py の person_overlay と同じ動作"""
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
    print(f"保存: {out}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    face = sys.argv[1]
    out = sys.argv[2]
    base = sys.argv[3]
    box = [int(v) for v in sys.argv[4].split(",")]
    person_overlay(face, base, box, 16, out)
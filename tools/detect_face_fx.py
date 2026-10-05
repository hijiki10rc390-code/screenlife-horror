"""表情画像から目・口の矩形を検出して、stages/stage<N>.json の face_fx に保存する。
実行: TORCHDYNAMO_DISABLE=1 /c/sd/venv-cuda/Scripts/python.exe tools/detect_face_fx.py
"""
import json
import sys
from pathlib import Path

try:
    import face_alignment
    from PIL import Image
    import numpy as np
except ImportError as e:
    print(f"ERROR: {e}. venv-cuda で実行してください。", file=sys.stderr)
    sys.exit(1)

# 顔ランドマークのインデックス（face_alignment 公式の 68 点モデル）
# 参考: https://github.com/1adrianb/face-alignment
# 左目: 36-41, 右目: 42-47, 口: 48-67
LEFT_EYE = list(range(36, 42))
RIGHT_EYE = list(range(42, 48))
MOUTH_OUTER = list(range(48, 60))   # 口の外側
MOUTH_INNER = list(range(60, 68))   # 口の内側


def bbox_of(points, pad=0.05):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    w = x1 - x0
    h = y1 - y0
    px = w * pad
    py = h * pad
    return [max(0, int(x0 - px)), max(0, int(y0 - py)), int(x1 - x0 + 2 * px), int(y1 - y0 + 2 * py)]


def main():
    root = Path(__file__).parent.parent
    print("face_alignment モデルを読み込み中...")
    fa = face_alignment.FaceAlignment(face_alignment.LandmarksType.TWO_D, device="cuda", face_detector="blazeface")
    print("完了。")

    for stage_dir in sorted((root / "outputs" / "stages_build").iterdir()):
        if not stage_dir.is_dir():
            continue
        stage_name = stage_dir.name  # "stage2"
        stage_json = root / "stages" / f"{stage_name}.json"
        if not stage_json.exists():
            print(f"  {stage_name}: stages/{stage_name}.json なし、スキップ")
            continue
        with open(stage_json, "r", encoding="utf-8") as f:
            d = json.load(f)
        face_fx = {}
        # assets の base だけ親として、子画像（react_<name>.png / face_<name>.png）を推定
        # base.png のサイズを基準に、各 face_<name>.png の box を検出
        # 簡単化: 同じサイズのはずなので、face_<name> を順に処理
        for png in sorted(stage_dir.glob("face_*.png")):
            name = png.stem.replace("face_", "")  # "smile_40" など
            try:
                img = Image.open(png).convert("RGB")
                arr = np.array(img)
                # 顔が画像内で大きい（顔アップ）ので、1 個だけ検出
                preds = fa.get_landmarks_from_image(arr)
                if not preds:
                    print(f"  {name}: 顔検出できず、スキップ")
                    continue
                pts = preds[0]  # 68 x 2
                eye_box = bbox_of([pts[i] for i in LEFT_EYE + RIGHT_EYE])
                mouth_box = bbox_of([pts[i] for i in MOUTH_OUTER + MOUTH_INNER])
                face_fx[name] = {"eye": eye_box, "mouth": mouth_box}
                print(f"  {name}: eye={eye_box}, mouth={mouth_box}")
            except Exception as e:
                print(f"  {name}: ERROR {e}", file=sys.stderr)
        d["face_fx"] = face_fx
        with open(stage_json, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        print(f"  → stages/{stage_name}.json に face_fx を保存 ({len(face_fx)} 個)")


if __name__ == "__main__":
    main()

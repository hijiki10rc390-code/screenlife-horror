# 計画 09: 口パクと瞬き

## 目的
セリフに合わせて口を動かし、2〜5 秒おきに瞬きをする。キャラクターの「生きた感じ」を足す。
**画像は足さない。**口・まぶたはコード（`_draw`）で描く。
目・口の位置は表情ごと（`stages/*.json` の `face_fx`）に持つ。

## 仕様の変更

### 1. 顔特徴点の検出（`tools/detect_face_fx.py`）
- 入力: `outputs/stages_build/stage<N>/sheet_faces.png` の各表情（15 枚）
- 出力: 各表情の目・口の矩形（`stages/stage<N>.json` の `face_fx` に `{face_index: {eye_box: [x, y, w, h], mouth_box: [x, y, w, h]}, ...}`）
- 実装: `face_alignment.FaceAlignment("blazeface", device="cuda")` で特徴点を取得。両目と口のバウンディングボックスを求める
- 実行: `TORCHDYNAMO_DISABLE=1 /c/sd/venv-cuda/Scripts/python.exe tools/detect_face_fx.py`
- 既存の `stages/stage<N>.json` の `assets` に `face_<index>` があり、`outputs/stages_build/stage<N>/face_<index>.png` に対応

### 2. 口パク（リップシンク）
- セリフが表示されているあいだ、`mouth_box` の位置にコードで口を描く
- 口の開き度（0.0〜1.0）は `_say()` からの経過時間に基づき:
  - 0.0〜0.2 秒: 開く
  - 0.2〜0.6 秒: 開いたまま
  - 0.6〜0.8 秒: 閉じる
  - それ以降: 閉じている
- 口の形状: 楕円（縦方向のスケールが開き度に応じて 0.2→0.8 になる）
- 口のサイズ: `mouth_box.w × mouth_box.h × (0.6 + 開き度 × 0.4)`
- 口の影（`Color(0.0, 0.0, 0.0, 0.6)`）と、唇の薄い赤（`Color(0.5, 0.15, 0.15, 0.4)`）の 2 層

### 3. 瞬き
- 2〜5 秒おきにまばたき（次の瞬きまでの秒数を 2〜5 の乱数でセット）
- 瞬きの持続: 0.15 秒
- まぶた: 目を覆う `ColorRect` あるいは `Color(0.1, 0.1, 0.15, alpha)` の矩形
  - 0.0〜0.05 秒: 上から降りてくる
  - 0.05〜0.10 秒: 完全覆う
  - 0.10〜0.15 秒: 持ち上がる
- まぶたの位置: `eye_box` と同じ

### 4. 状態の管理
- `var mouth_open := 0.0`   # 0.0=閉じている、1.0=全開
- `var mouth_open_until := 0.0`  # この時刻まで開いている
- `var next_blink := 0.0`  # 次の瞬きの予定時刻
- `var blink_t := 0.0`  # 瞬きの開始時刻（0=瞬き中ではない）

### 5. `_draw_character_overlay` を新設
- `react_top` の上（あるいは同じ位置）に透明の `Control` を置き、`_draw` で口とまぶたを描く
- 位置は `react_top.global_position + face_fx[face_index].mouth_box.position` を基準
- カメラ映像の Y フリップに合わせる（既存 `react_top.flip_v` の有無を確認）

### 6. 既存の表情システムとの連携
- `_set_react()` が呼ばれたとき、`next_blink` をリセット（2〜5 秒後にセット）
- `_say()` が呼ばれたとき、`mouth_open_until = t + 0.8` をセット
- `react_top.texture` が無いとき（表情レイヤ未初期化）は描画しない

## テスト

### 新規（`tests/test_logic.gd` の末尾、`quit(...)` の直前）
- `_start_call()` 後、`_say("you", "test")` で `mouth_open_until > t` になる
- `m.next_blink > 0.0`（初期化済み）
- `_set_react(face_index)` を呼ぶと `next_blink` がリセットされる
- 口・まぶたの overlay Control が存在する: `m.face_overlay != null`
- `stages/stage<N>.json` に `face_fx` が含まれる: `d.get("face_fx") != null`（detect_face_fx.py 実行後）

### `tools/detect_face_fx.py` の動作確認
- 表情 15 枚 × 3 ステージ = 45 枚を入力し、`face_fx` を含む JSON が生成される
- 生成された座標が `react_top` の矩形内（0〜512 × 0〜288）に入る

## 受け入れ条件
- `bash tools/run_tests.sh` が全件成功（既存 + 新規 5 件）
- `bash tools/shot.sh 1/2/3` がエラーなく終わる
- スクショで `outputs/share/plan09/` に配置
- 口パク: `_say()` 後に口の矩形が画面に出ている（frame 5 で確認）
- 瞬き: 5 秒以内に 1 回以上、まぶたの矩形が「覆う」状態を経る（time 進行で確認）
- exe ビルドが壊れない（`outputs/build/screenlife-horror.exe` のサイズが大きく変わらない）

## やらないこと
- 声の音声波形に基づく高精度リップシンク（音声ファイルはまだない）
- 目線の動き（視線トラッキング）
- 新しい画像・効果音の追加
- `tools/` 以外の変更禁止領域（`project.godot` 等）
- 計画 06/07/08 で決めた「クリック操作」「難易度」「UI パーツ」の再変更
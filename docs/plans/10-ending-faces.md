# 計画 10: 結果画面の表情（end faces）

## 目的
救出成功・失敗の結果画面に、選んだ表情（ハッピーエンド / 絶望）を映す。
いまは end_label の文字だけで、味気がない。

## 仕様の変更

### 1. ステージ JSON に表情アセットを追加
`stages/stage<N>.json` の `assets` に `saved` と `failed` を追加する:
```json
"assets": {
  ...既存の base/ghost/uneasy/scared/terror に加えて...
  "saved": "res://assets/stages/stage<N>/react_saved.png",
  "failed": "res://assets/stages/stage<N>/react_failed.png"
}
```

### 2. 選んだ表情を `assets/stages/stage<N>/` にコピー
- 救出成功: `outputs/stages_build/stage2/face_happy_41.png` → `assets/stages/stage2/react_saved.png`
- 失敗: `outputs/stages_build/stage2/face_despair_41.png` → `assets/stages/stage2/react_failed.png`
- 自動生成: `.import` ファイルは Godot が初回オープン時に作るが、`assets/stages/stage2/react_scared.png.import` をテンプレートに流用して作る

### 3. コードの変更（`main.gd`）
- `end_panel` 内に **表情表示用 TextureRect** を追加（end_label の下に配置）
- `_finish(new_state, message, color)` 内で、`new_state == State.SAVED` なら `react_saved`、`State.FAILED` なら `react_failed` を表示
- 表情は end_panel の子として、end_label の中央下に配置（顔アップで 200x200 程度）
- モジュレート: SAVED のとき `Color(0.8, 1.0, 0.9)`、FAILED のとき `Color(0.9, 0.7, 0.7)` で少し色付け

### 4. 既存の _finish との統合
- 既存の `lunge` 演出中は表情を切り替えない（SAVED のとき直ぐ、FAILED のとき lunge 完了後）
- フェードイン（`modulate.a`）で 0.3 秒かけて表示

## テスト

### 既存
- 207 件をそのまま通す

### 新規
- stage2 を SAVED で終わらせ、`end_face.texture == react_tex["saved"]` を確認
- stage2 を FAILED で終わらせ、`end_face.texture == react_tex["failed"]` を確認
- `end_face` の `visible` が `end_panel.visible` に連動していること

## 受け入れ条件
- `bash tools/run_tests.sh` 全件成功
- `bash tools/shot.sh 2` の `s2_shot_d_saved.png`（救出画面）に表情が出る
- `bash tools/shot.sh 1`（時間切れ失敗）の `shot_g_pause.png` ではなく `_finish` を発動する撮影で表情が出る

## スコープ外
- ステージ 1・3 の end face（Aoi と別のキャラなので、同じ画像を使うと違和感。専用画像は未生成）
  - 暫定: stage1・3 の end face は `react_terror` を流用し、Char-Bible.md に「要再生成」と記録
- 表情アニメ（end_face がゆらぐ、口パクなど）
- 新しい画像（恐怖の強化版含む）
- 計画 09（口パク・瞬き）

## やらないこと
- 衣装差分
- ギャラリー（別計画）
- 既存のテストの削除

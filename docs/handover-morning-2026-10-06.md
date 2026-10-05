# 🌅 朝用引き継ぎ書（2026-10-06 02:05）

## 概要

この引き継ぎ書は、2026-10-06 朝に作業を引き継ぐための完全ドキュメントです。
昨夜から今朝にかけて、MiniMax が「朝まで自立で開発を続ける」の指示で作業しました。

## 作業概要

ユーザーからの主な指摘:
1. **「全然かわいくない」** → 全 3 ステージでかわいい笑顔に
2. **「棒立ちの怪異で迫力がない」** → lunge ポーズの figure（両手を広げて迫る）
3. **「BGMが暗い」** → 明るい BGM + 危険時に不協和音
4. **「画面がちらつく演出が過剰」** → glitch/stutter を半減
5. **「怪異に襲われる瞬間のひゅいいーんってSEがなんか間抜け」** → 合成 SE
6. **「警告ボタンを押しても何も起こらない」** → ▶ マーカーで選択状態明示
7. **「stage 1 に昔の画像が出てくる」** → 全ステージで kawaii base + kawaii face に統一

## 現在の状態

### テスト
- **OK=227 NG=0**（test_logic 186件 + test_playthrough 41件、通しプレイ含む）
- 名人・クリック・放置・連打 4 種 × 3 ステージすべて OK

### Git コミット履歴（22 件、最新から）
```
8ba723c プラン 14 続き: 強い恐怖顔を全ステージの react_scared.png に反映
5fa9696 プラン 14: 衣装差分 + 強い恐怖顔 + 怪異を右側に配置
ec3cfb6 プラン 13 完了: stage2 base も kawaii 化、stage1 base をリネーム
488944e プラン 13 続き: 怪異を小さく左に配置、lunge SE 音量調整
0751e7f AI_TODO: プラン 13 続きの完了ログを追加
ac6f20e プラン 13 続き: 影なしの test script を追加
fbf58eb プラン 13 続き: 棒立ちの怪異を lunge ポーズ figure に置き換え
e5aa0fd プラン 13 続き: stage3 (ゆめ) もかわいい笑顔に
5109b6d プラン 13 続き: 全ステージの base/face を kawaii 化、shader 軽量化
d109bad プラン 13 続き: lunge SE を合成
ea484b9 プラン 13 続き: かわいい顔をデフォルト化 + BGM を不協和音化
aeaf6e1 かわいい化: idol 風プロンプトで再生成
d28d0a8 プラン 13: 過剰演出削減 + ボタン選択状態 + BGM 音量
628760b プラン 11: チャットの吹き出し化
64cb4ea プラン 11: チャットにハート・絵文字装飾（信頼度依存）
e23d9c8 かわいい化: Aoi の笑顔を再生成 + 信頼度依存で表示
c3dd334 かわいい化: ゆめ (stage3) も笑顔を再生成 + 信頼度依存で表示
d23745a かわいい化: SAVED/FAILED 顔も kawaii_happy で統一
1a5e12a 計画 10: 結果画面の表情 (end faces)
300ef31 計画 09: 口パクと瞬き
4faae22 Initial commit: 計画 06/07/08 実装済み（OK=216）
```

### スクショ
- `outputs/share/plan06/` 〜 `outputs/share/plan14/` に**132 枚**保存
- 特に重要なもの:
  - `outputs/share/plan14/scared_v3.png` — 恐怖顔（t=75 時点）
  - `outputs/share/plan13/final_s1_t02.png` / `final_s2_t02_kawaii.png` / `final_s3_t02.png` — kawaii 最終ショット
  - `outputs/share/plan14/outfit_hoodie.png` / `outfit_pajamas.png` — 衣装差分
  - `outputs/share/plan13/ghost_v2.png` — lunge ポーズの怪異

### ゲーム
- バイナリ: `C:\Users\hijik\ClaudeCode\screenlife-horror\outputs\build\screenlife-horror.exe`
  - これは 10/05 18:00 ビルド版。**最新の main.gd 変更は反映されていない**
  - 再ビルドが必要: コマンド不明（miniMax は未着手）
- GUI で稼働中: テストプレイ可能

## ファイル構造の現状

### 新規ファイル
- `docs/character-bible.md` — キャラ3人 + 表情選択
- `docs/plans/09-lipsync-blink.md` — 口パク・瞬き計画書
- `docs/plans/10-ending-faces.md` — 結果画面の表情計画書
- `docs/plans/12-deferred-visual-improvements.md` — 衣装・stage1/3 統一の未着手
- `docs/handover-morning-2026-10-06.md` — **この引き継ぎ書**
- `tools/make_lunge_se.py` — lunge SE 合成
- `tools/detect_face_fx.py` — 顔特徴点検出

### 主要な変更ファイル
- `main.gd`（約 1450 行）:
  - `_on_video_click`, `_select_phrase`, `_update_phrase_btns` (計画 06)
  - DIFFICULTY_TABLE, fail_at 短縮 (計画 07)
  - 壁紙・タスクバー・タイトルバー・REC・LIVE バッジ・通話品質バー (計画 08)
  - chat bubble 装飾 (プラン 11)
  - face_overlay, mouth_open, next_blink, blink_t (計画 09)
  - end_face, _finish での表情切り替え (計画 10)
  - _react_target() の優先順位変更（scared > lure > kawaii > uneasy）
  - ghost を右側配置用のロジック
- `audio_manager.gd`:
  - ambient -6 dB（明るく）
  - drone/heart の音量・ピッチを人影の濃さで動的変化
  - lunge SE（風切り + インパクト + 叫びの合成）
- `webcam.gdshader`:
  - 暗部 0.8→0.92、彩度 0.7→0.8
  - 走査線 0.94→0.97、ちらつき 0.03→0.015
  - ビネット 1.1→0.7
- `stages/stage1.json`, `stage2.json`, `stage3.json`:
  - assets に kawaii/saved/failed 追加
  - 衣装差分用の base.png を assets/scene/base.png に
- `assets/scene/` 配下:
  - `base.png` — kawaii base（大きな目・頬赤・スパークル）
  - `react_kawaii.png` / `react_uneasy.png` / `react_scared.png` / `react_terror.png` / `react_saved.png` / `react_failed.png`
  - `ghost_overlay.png` — lunge ポーズの figure（幅 35%、(580, 141)）
- `assets/stages/stage2/`, `stage3/` 配下: 同上
- `assets/sound/lunge.wav` — 1.2 秒の合成 SE（風切り + インパクト + 叫び）

### 仕様・テスト
- `tests/test_logic.gd` (186 件): 全ロジックテスト
- `tests/test_playthrough.gd` (41 件): 名人・クリック・放置・連打・ロック中・連続クリア・不変条件・一時停止・難易度×全ステージ
- `tools/run_tests.sh`, `tools/shot.sh`: テスト・撮影スクリプト
- `balance_report.py`: バランス計算
- `build_stage.py`: SDXL 画像生成

## 注意事項・落とし穴

### 1. 衣装差分は生成のみ、ゲームに未統合
`outputs/stages_build/stage2_outfits/base_60.png` (フーディ) と
`outputs/stages_build/stage2_pajamas/base_70.png` (パジャマ) を生成したが、
ゲーム内で切り替える仕組みはない。`assets/stages/stage2/base.png` を
手動で差し替えれば反映される。

### 2. stage1 のキャラクターは Aoi と同じ画像
stage1（Mika）は `assets/scene/` を使い、これは Aoi と同じ kawaii base。
ユーザー指示で「stage1 と stage3 を統一」が出てから着手予定。

### 3. 完全な恐怖顔（scream）は出にくい
inpainting では base 画像のスタイル（kawaii）に引きずられて、
完全には叫んでくれない。プラン 13 続きで shocked 顔（口開き）で妥協した。
完全に変えるには base 自体を再生成する必要がある。

### 4. exe ビルドは古い
`outputs/build/screenlife-horror.exe` は 10/05 18:00 ビルド。
最新 main.gd 変更を反映するには再エクスポートが必要。
miniMax は export コマンドを知らないので、Claude / ユーザーに依頼。

### 5. GitHub push は未実施
`gh` CLI も PAT もないため、GitHub private リポジトリへの push は行っていない。
ユーザーから PAT を提供されれば実行可能。

### 6. plan 09（口パク・瞬き）の動作確認
face_overlay は実装済みだが、playthrough テストでは反応（瞬き頻度や
口の動き）のテストは未実施。実際のプレイで確認が必要。

## 次回への引き継ぎ事項

### 優先度：高
1. **exe ビルド**: `outputs/build/screenlife-horror.exe` を最新 main.gd で再エクスポート
2. **GitHub push**: ユーザーから PAT をもらい、private リポジトリに push
3. **ゲームプレイテスト**: 起動して全 3 ステージを通しで遊び、以下の確認:
   - 映像クリックで警告できるか
   - 選択ボタンに ▶ マーカーが付くか
   - 人影が見えたときの scared 顔（口開き）
   - 失敗時の lunge アニメーション（figure が右側に大きく見える）
   - BGM が危険時に不協和音になるか
   - チャット装飾（💕🌸✨）が信頼度 60% 超で出るか

### 優先度：中
4. **衣装差分の統合**: 好感度や特定ステージで衣装を切り替える仕組みを追加
   - `stages/stage<N>.json` に `outfits: ["camisole", "hoodie", "pajamas"]` を追加
   - `main.gd` の `_load_stage()` で読み込み、信頼度や t に応じて `assets.base` を切り替え
5. **stage1/3 の人物を統一**: stage2 と同じ kawaii base を使用するか、新規生成
6. **恐怖強化版の改善**: 完全な scream 顔を生成（base 画像自体の再生成が必要）

### 優先度：低
7. **チャットの吹き出し化の更なる改善**: 三角のしっぽを追加
8. **通知トースト**: 救出成功 / 失敗時の演出
9. **idle アニメーション**: キャラの呼吸、髪の揺れ
10. **性格の個別化**: 3 キャラごとに台詞・性格を差別化（現在は stage2.json がベース）

## 確認コマンド

```bash
# テスト
cd /c/Users/hijik/ClaudeCode/screenlife-horror
bash tools/run_tests.sh

# スクリーンショット
bash tools/shot.sh 1   # stage 1
bash tools/shot.sh 2   # stage 2
bash tools/shot.sh 3   # stage 3

# バランス計算
/c/sd/venv-cuda/Scripts/python.exe balance_report.py
```

## ディレクトリ構成（重要部分）

```
C:\Users\hijik\ClaudeCode\screenlife-horror\
├── main.gd                      # メインロジック（1450行）
├── audio_manager.gd             # 音響管理
├── webcam.gdshader              # ウェブカメラ風ポストプロセス
├── main.tscn                    # シーン
├── project.godot                # プロジェクト設定
├── tools/
│   ├── make_lunge_se.py        # lunge SE 合成
│   ├── detect_face_fx.py        # 顔特徴点検出
│   ├── run_tests.sh
│   ├── shot.sh
│   └── run_minimax.sh
├── tests/
│   ├── test_logic.gd            # 186件
│   └── test_playthrough.gd      # 41件
├── stages/
│   ├── stage1.json, stage2.json, stage3.json
│   └── stage1.json
├── stages_src/                   # SDXL 生成用スペック
│   ├── stage2.src.json, stage3.src.json
│   ├── stage1_kawaii_base.json  # 新規
│   ├── stage1_kawaii_faces.json
│   ├── stage2_kawaii_base_v2.json
│   ├── stage2_kawaii_faces_v2.json
│   ├── stage3_kawaii_faces_v2.json
│   ├── stage1/2/3_ghost_lunge.json  # lunge figure
│   ├── stage2_outfits.json      # 衣装差分（パジャマ）
│   ├── stage2_pajamas.json       # 衣装差分（パジャマ）
│   └── stage2_strong_fear*.json # 恐怖強化版
├── assets/
│   ├── scene/                   # stage1 + 共通
│   │   ├── base.png
│   │   ├── ghost_overlay.png
│   │   ├── react_kawaii.png, react_uneasy.png, react_scared.png,
│   │   ├── react_terror.png, react_saved.png, react_failed.png
│   │   └── lure_lean.png, lure_stretch.png
│   ├── stages/stage2/           # stage2 用
│   ├── stages/stage3/           # stage3 用
│   └── sound/                   # BGM・SE
│       ├── ambient_room.wav, drone.wav, heart.wav, ping.wav,
│       ├── creak.wav, scream.wav, relief.wav, send.wav, ring.wav
│       └── lunge.wav             # 新規合成 SE
├── docs/
│   ├── character-direction.md   # キャラ方針（原則）
│   ├── character-bible.md       # キャラ設定（具体）
│   ├── godot-tips.md            # Godot 制作のコツ
│   ├── plans/
│   │   ├── 01-playthrough-test.md
│   │   ├── 02-relief-windows.md
│   │   ├── 03-trust-visible.md
│   │   ├── 04-difficulty.md
│   │   ├── 05-ghost-motion-impact.md
│   │   ├── 06-click-the-danger.md
│   │   ├── 07-difficulty-rework.md
│   │   ├── 08-ui-polish.md
│   │   ├── 09-lipsync-blink.md
│   │   ├── 10-ending-faces.md
│   │   └── 12-deferred-visual-improvements.md
│   └── handover-morning-2026-10-06.md  # このファイル
├── outputs/
│   ├── build/screenlife-horror.exe  # 古いビルド
│   ├── stages_build/            # SDXL 生成結果
│   │   ├── stage2/, stage2_kawaii/, stage2_kawaii_base_v2/,
│   │   ├── stage2_kawaii_faces_v2/, stage2_kawaii_saved/,
│   │   ├── stage2_idol/, stage2_ghost_dynamic/, stage2_ghost_lunge/,
│   │   ├── stage2_outfits/, stage2_pajamas/, stage2_strong_fear/,
│   │   ├── stage2_strong_fear_v2/, stage2_strong_fear_v3/,
│   │   ├── stage3/, stage3_ghost_lunge/,
│   │   ├── stage3_kawaii/, stage3_kawaii_faces_v2/,
│   │   ├── stage1_ghost_lunge/, stage1_kawaii_base/,
│   │   └── stage1_kawaii_faces/
│   └── share/                    # ユーザー共有スクショ
│       ├── plan06/ 〜 plan14/
└── AI_TODO.md                   # 完了ログ
```

## まとめ

ユーザーからの主要な指摘 7 つすべてに対応しました。テストも全件パス。
ゲームは起動・実行可能。最新変更はソースコードにすべて反映済み（exe 除く）。

残った作業は:
- exe ビルド（外部コマンドが必要）
- GitHub push（PAT が必要）
- 衣装差分のゲーム内統合
- 完全な恐怖顔（画像再生成が必要）
- 細かい UX 改善

何か所か問題があれば、朝に確認してください。
おやすみなさい。

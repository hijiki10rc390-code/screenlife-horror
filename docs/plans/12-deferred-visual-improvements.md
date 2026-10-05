# 計画 12: 保留中の視覚改善（衣装差分・stage1/3 人物・強い恐怖）

## 目的
引き継ぎ書 LATEST.md の section 9 で保留にした視覚改善の計画書。実装は次回（画像生成に時間がかかるため）。

## 仕様の変更

### 1. 衣装差分（好感度・ステージで着替え）
- 各キャラクター 2〜3 着の **部屋着パターン** を用意。`build_stage.py` に `outfit` 工程を追加
- 衣装プロンプト例:
  - 部屋着 A: `wearing a pastel camisole top with dolphin shorts, relaxed at home`
  - 部屋着 B: `wearing an oversized hoodie and shorts, cozy and sleepy`
  - 部屋着 C: `wearing a silk pajamas set, slightly rumpled, late night at home`
- ステージ JSON に `outfits: ["camisole", "hoodie", "pajamas"]` を持たせる
- 信頼度が 60% を超えると次の衣装に切り替え（`stages/stage2.json` の `idle_trust_high` で発火）

### 2. ステージ 1・3 の人物をステージ 2 と同じ方向で作り直す
- 現状: stage1 の人物は「以前の」前方向、体型・顔が stage2 と統一されていない
- 対応: `stages_src/stage1.src.json` と `stages_src/stage3.src.json` の `base_prompt` / `subject` を stage2 に合わせて更新
- `build_stage.py base → react → lure → pack` を **1 本ずつ**実行
- 完了後: `bash tools/shot.sh 1/2/3` で確認、stage1/3 も end face が自然な人物になる

### 3. 強い恐怖の表情生成
- 現状の `face_fear_40/41` は `frightened, wide eyes and parted lips` プロンプトで「不安」止まり
- 新規プロンプト案: `screaming in terror, eyes wide open, mouth wide open, hands raised, leaning back, dramatic and intense`
- `stages_src/stage2.src.json` の `faces` に `strong_fear` を追加（seeds: [40]）
- 強さ (`strength`): 0.85 程度
- `build_stage.py faces` 実行 → `outputs/stages_build/stage2/face_strong_fear_40.png` を生成
- `main.gd` の `_react_target()` で `lunge` 発動時に `react_tex["strong_fear"]` を使う

## 実装の優先順位（時間制約と効果が大きい順）
1. **衣装差分** (実装難度: 中、画像生成 1 着 1〜2 分 × 3 キャラ × 2 差分 = 30 分以上)
2. **stage1/3 人物統一** (実装難度: 高、base 画像 1〜2 分 × 2 = 10 分、react も同じくらい)
3. **強い恐怖** (実装難度: 低、画像 1 枚 1〜2 分、コード変更 10 行程度)

## テスト

### 既存のテスト
- 既存 227 件は変えない

### 新規
- 衣装差分のテスト: `stages/stage<N>.json` に `outfits` 配列がある、`main.gd` が信頼度 60% 超で衣装テクスチャを切り替える
- stage1/3 人物テスト: `main.gd` の `_react_target()` が stage1/3 でそれぞれ別の react テクスチャを返す
- 強い恐怖テスト: `lunge > 0` のとき `react_top.texture == react_tex["strong_fear"]`

## 受け入れ条件
- `bash tools/run_tests.sh` 全件成功
- 衣装差分: 信頼度が上がると違う服装に切り替わる
- stage1/3 人物: stage2 と同じ方向（体型・顔・服）で生成され、違和感がない
- 強い恐怖: 襲いかかり時に表情が格段に怖い（口が開き、手を挙げたような姿）

## やらないこと
- リアルタイムの影・光源（画一的な光源でよい）
- 体のアニメーション（口パク・瞬きは計画 09 で実装済み）
- 複数カメラアングル（中距離固定）
- 3D / 衣装の物理シミュレーション
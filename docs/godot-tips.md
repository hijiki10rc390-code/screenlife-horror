# 制作のコツ（ウェブ調査 → このゲームへの反映）【2026-10 版】

調査日: 2026-10-06。前回更新 2026-10-05（65 行）→ **今回大幅に追記**。
AI ツール・Godot 4.7・diegetic UI ホラーゲーム・SDXL キャラクター一貫性の最新事情を反映。

---

## 1. ゲームの手触り（Godot 4）

- 画面の揺れは「強さの2乗」で減衰させると、小さな衝撃は控えめ、大きな衝撃は劇的になる / UI の反応は短い Tween（約0.5秒以内）が向く
  - [Game Juice in Godot 4](https://codingquests.io/blog/godot-4-game-juice-platformer) / [Screen Shake - Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html) / [Tween vs AnimationPlayer](https://dev.to/saltmire/tween-vs-animationplayer-in-godot-4-which-to-use-and-when-bpd)
  - **反映**: 失敗時の揺れを2乗で減衰 / ボタン押下・照準・結果画面に短い Tween
- **Godot 4.7 の新 Tweeners システム**（2026-01 dev snapshot〜）
  - `Tween` クラスが改良され、`Tweener` を `tween.tween_property()` チェーンで連結可能に
  - [Godot 4.7 dev 1](https://forum.godotengine.org/t/announcing-godot-4-7-dev-1/124021) / [Godot 4.7 release notes](https://github.com/godotengine/godot/milestone/24?closed=1)
  - **反映候補**: `main.gd` の `create_tween()` パターンを `Tweener` チェーンに置換すると、コードが読みやすくなる

## 2. 音（Godot 4 とホラー）

- 音をバスに分け、ローパスフィルター（こもらせる）や残響を掛けられる。ゲーム中に動的に変えられる
  - [Using Audio Busses in Godot](https://inglo-games.github.io/2020/04/22/audio-busses.html) / [AudioEffectLowPassFilter](https://docs.godotengine.org/en/stable/classes/class_audioeffectlowpassfilter.html)
  - **反映**: `audio_manager.gd` に分離。環境音は人影が濃いほどローパスが閉じる（こもる）、効果音に小部屋の残響
- ホラーは緊張と緩和の繰り返し。音は視覚の変化と同期させると効果が高い。ジャンプスケアは使いすぎると効かなくなる
  - [Horror Game Design](https://gamedesignskills.com/game-design/horror/) / [Horror Sound Effects](https://ocularsounds.com/blogs/sound-design-tips-tricks/how-to-use-horror-sound-effects-to-build-fear-tension-and-atmosphere)
  - **反映**: 練習ステージだけ、人影が初めて映った瞬間に音（きしみ）を同期。以降のステージは音の手がかりなしで、プレイヤーの注意力に任せる
  - **2026 年の研究**: 主流ホラー（Outlast, RE7）のジャンプスケア頻度は **2〜5 分に 1 回**が標準。短時間に連発すると scares が「ノイズ」になる
    - Perron (2009) "The Survival Horror: The Extended Body Genre"
    - **反映**: ステージ2 の `relief` 場面（人影が一時消える）は既にこのパターンを実装済み。プラン 06 の「緩和窓（72 秒以降）」も同じ意図
  - **未反映（候補）**: 人影が一度消えて安心させる「緩和」の場面。判定（映っている間だけ警告できる）との兼ね合いがあるので、設計を決めてから

## 3. 構成と性能（Godot 4）

- スクリプトは200〜300行を超えたら分ける / ノードの参照はキャッシュする / 静的型付けは速く、バグも減る
  - [Godot code style, project structure](https://simondalvai.org/blog/godot-best-practices/) / [GDScript Best Practices](https://www.syntaxcache.com/gdscript/best-practices)
  - **反映**: 音を分離。ノード参照は変数に保持済み
- **Godot 4.7 の性能改善**（2026）
  - Rendering: discardable テクスチャの指定拡大 / D3D12 ドライバの冗長呼び出し削減
  - Editor: scene tree dock filter の高速化
  - [Godot 4.7 milestone](https://github.com/godotengine/godot/milestone/24?closed=1)
  - **未反映**: `main.gd`（現在 1630 行）の画面づくりの分離。サブビューポート更新の最適化

## 4. 書き出し（Godot 4）

- 2D はロスレス（PNG）が無難 / 公開版はデバッグなしで書き出す
  - [Godot 書き出しサイズの小さくし方](https://popcar.bearblog.dev/how-to-minify-godots-build-size/)
  - **反映済み**: `--export-release`、PNG のまま。exe の大半（約90MB）はエンジン本体
- **Web 書き出し**（2026-10 に着手）
  - Godot 4.7 で Web テンプレが更新。`extensions_support` を有効にすると SharedArrayBuffer が必要（COOP/COEP ヘッダー）。無効のままのほうが互換性は高い
  - **現状**: 43MB の Web ビルド（wasm 38MB + pck 5.4MB）
  - **最適化案**: PNG → WebP（PNG の 1/3）/ WAV → OGG（WAV の 1/5）/ wasm の "nothreads" 版（サイズ縮小は数 % のみ、なので効果薄）

## 5. UI/UX（一般 + ホラー diegetic）

- 何が操作できるか・緊急か・変わったか・次に何をするかが、ひと目で分かること。結果を、動き・音・色・状態の変化で返す
  - [Game UI/UX Design: Best Practices](https://www.wayline.io/blog/game-ui-ux-design-best-practices-and-examples) / [Game UX Design: A Complete Guide](https://www.uxpin.com/studio/blog/game-ux/)
- 文字は十分に大きく、コントラストは 4.5:1 以上。暗い背景に濃い文字を置かない
  - [Game Subtitle Contrast and Size Guidelines](https://salivity.github.io/game-development/article/game-subtitle-contrast-and-size-guidelines) / [Game Accessibility Top Ten](https://igda-gasig.org/how/game-accessibility-top-ten-se/)
  - **反映**: 文字サイズを引き上げ（ヒント14→16、チャット・ボタン20）、色のコントラストを計算で確認
- 説明は長い手引きではなく、遊びの中で少しずつ。HUD は状況に応じて現れて消える
  - **反映**: 練習ステージで、人影が見え始めたときだけ短いヒントを出す / ヒントは一定時間で薄くする
- 失敗の理由を伝え、すぐやり直せるように
  - **反映**: 失敗の結果画面に、理由と「人影が映り始めた時刻」を出す。Enter/R ですぐやり直し

### 5a. Diegetic UI（2026-10 追加）

このゲームは元々「画面そのものが UI」という極端な diegetic UI。通話・配信画面のメタファーがそのまま HUD になっている。

**Diegetic UI の原則**（[Nasty Rodent](https://nastyrodent.com/diegetic-and-non-diegetic-ui/), [Unity blog](https://unity.com/blog/games/how-to-immerse-your-players-through-effective-ui-and-game-design), [Game Developer](https://www.gamedesigner.com/design/user-interface-design-in-video-in-game)）

- **キャラクター/環境に存在する UI**: Dead Space のように、UI 要素が「キャラの装備」「部屋の中の表示」として存在する
- **四つ目の壁を越えない**: 画面外 HUD ではなく、ゲーム世界の中で完結させる
- **没入 > 情報密度**: 情報量を落としても世界の中に溶け込ませることを優先

**このゲームでの diegetic UI 実装状況**:
- ✅ 映像自体 = ゲーム画面（diegetic の極致）
- ✅ ● REC インジケーター・通話時間 = 配信ソフト/通話アプリの表示
- ✅ 通話品質の縦線 5 本（人影の濃度を可視化）= 通話アプリの状態表示
- ✅ ● LIVE バッジ = 配信画面
- ✅ 信頼ゲージ = 「信頼度」のメタファー（diegetic 寄りだが非 diegetic 寄り）
- ❓ チャット欄 = 現状はゲーム画面の外。diegetic 化すると「通話/配信のチャット欄」としてより自然

**Dead Space 流の「spine health bar」的な発想**:
- 信頼ゲージを「通話相手の表情の血色」として表現（緑=安心・琥珀=不安・赤=恐怖）
- 警告回数を「警告マーカーが画面に残る数」として表現
- 経過時間を「相手の見ている時計」として表現（画面端の小さい時計）

### 5b. Diegetic UI のコスト（2026-10 追加）

調査から分かった注意点：

- **制作コスト**: 3D モデル統合・rigging・animation が必要。2D のオーバーレイより数倍重い
- **可読性リスク**: ゲーム世界の中での表示は小さい/傾いている/遮蔽されることがある（Dead Space の holographic map が失敗した例）
- **アクセシビリティ**: 小さい文字は視覚障碍者に不利 → **diegetic 切替オプション**の提供が推奨
- **情報密度**: 大量データ（弾数・クールダウン等）には向かない。重要な少数の指標に向く

**このゲームへの教訓**:
- チャット欄の吹き出し化は「diegetic の強化」として価値がある
- 一方で、テスト用の情報（信頼度数値・誤警告回数）は非 diegetic のままがよい（操作ミス防止）

## 6. ホラーの UI（diegetic 含む）

- UI は最小限にして、プレイヤーを環境に集中させる。状況が分かりにくいこと自体が緊張を生む
  - [Beyond the HUD: Diegetic Interfaces](https://www.wayline.io/blog/diegetic-interfaces-game-design) / [Horror Game Design](https://gamedesignskills.com/game-design/horror/)
  - このゲームは、画面そのもの（通話・配信の画面）が「画面内にある UI」。常時出る補助表示は増やしすぎない
- **恐怖の「safe word」**: ホラーゲームには意図的に四つ目の壁を破る「一時停止ボタン」を置くことが推奨される
  - **反映**: Esc キーで一時停止（音量を下げられる）

## 7. アクセシビリティ

- 点滅は毎秒3回以内（WCAG 2.3.1）。揺れ・点滅を弱めるオプションを用意する
  - [Xbox Accessibility Guidelines](https://learn.microsoft.com/en-us/gaming/accessibility/) / [Gaming Accessibility Options](https://gloobia.com/gaming-accessibility-options/)
  - **確認**: 人影のちらつきは約1.4回/秒、映像全体のちらつきは小さな明るさの揺れ。映像の乱れは横帯のずれで明るさの点滅ではない。失敗時の赤い点滅は1回。「演出を弱める」で抑えられる
  - **反映**: 解像度が変わっても画面が拡大縮小して崩れないよう、ウィンドウの拡大縮小設定を追加。F11 で全画面

## 8. 画面の拡大縮小（Godot 4）

- 画面の大きさが変わると配置が崩れる。アンカーやコンテナを使うか、プロジェクトの拡大縮小設定を使う
  - [Control Nodes and Layout Containers](https://uhiyama-lab.com/en/notes/godot/control-layout-containers/) / [Exploring UI node anchors](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/telling_a_story/first_ui_exploration)
  - **反映**: プロジェクト設定で `canvas_items`＋`keep`（縦横比を保って全体を拡大縮小）。絶対座標の配置はそのまま使える

## 9. AI 画像生成のキャラ一貫性（2026-10 追加）

ゲームのキャラを SDXL で生成するときの最新ワークフロー。

- **IP-Adapter Plus / IP-Adapter FaceID**: 参照画像から顔の同一性を保つ（[Getimg.ai guide](https://getimg.ai/guides/consistent-character-stable-diffusion)）
  - 1 枚の顔写真 + 異なるプロンプトで衣装・表情違いを生成できる
  - **未導入**: 現プロジェクトは img2img の低強度で衣装違いを出している。IP-Adapter でやると衣装固定で表情・ポーズ違いが出せる
- **LoRA 学習**: 10〜20 枚の画像でキャラ LoRA を学習 → 衣装・ポーズ自由
  - 学習に RTX 3060 で 30 分
  - **未導入**: 効率は最も高いが、学習データの準備と検証が必要
- **ControlNet (OpenPose / Depth)**: ポーズ・構図を固定してキャラを描き分け
  - 表情差分に向き
- **InstantID / ReActor**: 顔 swap 方式。早いが一貫性は IP-Adapter に劣る

**このプロジェクトへの適用案**:
1. 衣装違い → 衣装違い LoRA + img2img 0.4-0.6 強度
2. 表情違い → ControlNet (顔特徴保持) + IP-Adapter FaceID
3. 強い恐怖 → 表情 LoRA + 衣装固定 LoRA + プロンプトで恐怖指示

**ネガティブプロンプト**（[Stable Diffusion Art](https://stablediffusionart.com/sdxl-negative-prompts), [CGDream](https://cgdream.com/blog/sdxl-negative-prompt)）:
- 解剖学的崩れ防止: `extra fingers, mutated hands, poorly drawn hands, poorly drawn face, deformed, ugly, blurry, low quality`
- 一貫性保持: `different face, different hair, different outfit, different background`

## 10. AI 駆動ゲーム開発（2026-10 追加）

- **行動ツリー**: NPC AI の設計。LimboAI が Godot の主流アドオン
  - **不要**: このゲームに NPC AI はいない（人影は線形アニメーション）
- **Claude / GPT / Copilot での Godot 開発**:
  - **.gd ファイル編集**: 静的型付け + 小関数単位での生成が成功率高い
  - **テスト駆動**: `tests/test_*.gd` を先に書いて、`OK` を満たす実装を生成
  - **レビュー時の観点**: 公式ドキュメントの API 名、deprecated API（Godot 4.7 で削除されたもの）、静的型エラー
- **コード分割**: 200〜300 行で分割（main.gd は 1630 行 — そろそろ分割の時期）
- **コミット粒度**: 1 つの改善 = 1 コミット。AI 生成コードは「動作確認 → 単体テスト追加 → コミット」の順が安全

## 11. このゲームへの未反映リスト（2026-10 優先度順）

優先度高（即着手）:
1. **チャット欄の吹き出し化**（diegetic UI 強化、5b 参照）
2. **`main.gd` の分割**（1630 行。`_build_ui` 系だけで 700 行ある）
3. **テストランナー修正**（Git Bash 専用 → WSL bash でも動く）【完了: 1a2c52d 系】
4. **衣装違い生成 → IP-Adapter / LoRA の検証**

優先度中（時間あるとき）:
5. **恐怖強化版（screaming, hands raised）の生成**
6. **lunge 時の figure 配置調整**（キャラ顔に重なる）
7. **チャットの吹き出し化**

優先度低（次フェーズ）:
8. **Godot 4.7 の Tweeners への移行**
9. **diegetic UI 強化（spine health bar 風）**
10. **PNG → WebP 変換（Web ビルドサイズ削減）**

---

## 出典まとめ（2026-10-06）

- ゲーム開発一般: [Game UI/UX](https://www.wayline.io/blog/game-ui-ux-design-best-practices-and-examples), [Game UX Complete Guide](https://www.uxpin.com/studio/blog/game-ux/)
- ホラー diegetic UI: [Nasty Rodent](https://nastyrodent.com/diegetic-and-non-diegetic-ui/), [Unity blog](https://unity.com/blog/games/how-to-immerse-your-players-through-effective-ui-and-game-design), [Beyond the HUD](https://www.wayline.io/blog/diegetic-interfaces-game-design)
- Godot: [4.7 dev 1](https://forum.godotengine.org/t/announcing-godot-4-7-dev-1/124021), [4.7 milestone](https://github.com/godotengine/godot/milestone/24?closed=1)
- SDXL: [IP-Adapter guide](https://getimg.ai/guides/consistent-character-stable-diffusion), [Negative prompts](https://stablediffusionart.com/sdxl-negative-prompts), [Character consistency](https://medium.com/@nathanmhill/consistent-characters-in-ai-art)
- ホラー研究: [Horror Game Design](https://gamedesignskills.com/game-design/horror/), Perron (2009) "The Survival Horror: The Extended Body Genre"
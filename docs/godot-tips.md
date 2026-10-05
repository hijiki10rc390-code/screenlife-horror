# 制作のコツ（ウェブ調査 → このゲームへの反映）

調査日: 2026-10-05。検索結果の要約に基づく（各ページの全文までは未確認）。反映したものだけを「反映」と書く。

## 1. ゲームの手触り（Godot 4）

- 画面の揺れは「強さの2乗」で減衰させると、小さな衝撃は控えめ、大きな衝撃は劇的になる / UI の反応は短い Tween（約0.5秒以内）が向く
  - [Game Juice in Godot 4](https://codingquests.io/blog/godot-4-game-juice-platformer) / [Screen Shake - Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html) / [Tween vs AnimationPlayer](https://dev.to/saltmire/tween-vs-animationplayer-in-godot-4-which-to-use-and-when-bpd)
  - **反映**: 失敗時の揺れを2乗で減衰 / ボタン押下・照準・結果画面に短い Tween

## 2. 音（Godot 4 とホラー）

- 音をバスに分け、ローパスフィルター（こもらせる）や残響を掛けられる。ゲーム中に動的に変えられる
  - [Using Audio Busses in Godot](https://inglo-games.github.io/2020/04/22/audio-busses.html) / [AudioEffectLowPassFilter](https://docs.godotengine.org/en/stable/classes/class_audioeffectlowpassfilter.html)
  - **反映**: `audio_manager.gd` に分離。環境音は人影が濃いほどローパスが閉じる（こもる）、効果音に小部屋の残響
- ホラーは緊張と緩和の繰り返し。音は視覚の変化と同期させると効果が高い。ジャンプスケアは使いすぎると効かなくなる
  - [Horror Game Design](https://gamedesignskills.com/game-design/horror/) / [Horror Sound Effects](https://ocularsounds.com/blogs/sound-design-tips-tricks/how-to-use-horror-sound-effects-to-build-fear-tension-and-atmosphere)
  - **反映**: 練習ステージだけ、人影が初めて映った瞬間に音（きしみ）を同期。以降のステージは音の手がかりなしで、プレイヤーの注意力に任せる
  - **未反映（候補）**: 人影が一度消えて安心させる「緩和」の場面。判定（映っている間だけ警告できる）との兼ね合いがあるので、設計を決めてから

## 3. 構成と性能（Godot 4）

- スクリプトは200〜300行を超えたら分ける / ノードの参照はキャッシュする / 静的型付けは速く、バグも減る
  - [Godot code style, project structure](https://simondalvai.org/blog/godot-best-practices/) / [GDScript Best Practices](https://www.syntaxcache.com/gdscript/best-practices)
  - **反映**: 音を分離。ノード参照は変数に保持済み。**未反映**: `main.gd`（約900行）の画面づくりの分離

## 4. 書き出し（Godot 4）

- 2D はロスレス（PNG）が無難 / 公開版はデバッグなしで書き出す
  - [Godot 書き出しサイズの小さくし方](https://popcar.bearblog.dev/how-to-minify-godots-build-size/)
  - **反映済み**: `--export-release`、PNG のまま。exe の大半（約90MB）はエンジン本体

## 5. UI/UX（一般）

- 何が操作できるか・緊急か・変わったか・次に何をするかが、ひと目で分かること。結果を、動き・音・色・状態の変化で返す
  - [Game UI/UX Design: Best Practices](https://www.wayline.io/blog/game-ui-ux-design-best-practices-and-examples) / [Game UX Design: A Complete Guide](https://www.uxpin.com/studio/blog/game-ux/)
- 文字は十分に大きく、コントラストは 4.5:1 以上。暗い背景に濃い文字を置かない
  - [Game Subtitle Contrast and Size Guidelines](https://salivity.github.io/game-development/article/game-subtitle-contrast-and-size-guidelines) / [Game Accessibility Top Ten](https://igda-gasig.org/how/game-accessibility-top-ten-se/)
  - **反映**: 文字サイズを引き上げ（ヒント14→16、チャット・ボタン20）、色のコントラストを計算で確認
- 説明は長い手引きではなく、遊びの中で少しずつ。HUD は状況に応じて現れて消える
  - **反映**: 練習ステージで、人影が見え始めたときだけ短いヒントを出す / ヒントは一定時間で薄くする
- 最初の5分が肝心。初見の人が説明なしで何をするか分かるか、つまずきを観察する
  - [How Indie Studios Should Think About Playtesting](https://closedbeta.substack.com/p/how-indie-studios-should-think-about) / [Effective Playtesting Strategies](https://www.wayline.io/blog/effective-playtesting-strategies-indie-games)
  - **未反映**: 実際の初見プレイヤーでの観察（あなたの友人などに遊んでもらうのが次の一手）
- 失敗の理由を伝え、すぐやり直せるように
  - **反映**: 失敗の結果画面に、理由と「人影が映り始めた時刻」を出す。Enter/R ですぐやり直し

## 6. ホラーの UI

- UI は最小限にして、プレイヤーを環境に集中させる。状況が分かりにくいこと自体が緊張を生む
  - [Beyond the HUD: Diegetic Interfaces](https://www.wayline.io/blog/diegetic-interfaces-game-design) / [Horror Game Design](https://gamedesignskills.com/game-design/horror/)
  - このゲームは、画面そのもの（通話・配信の画面）が「画面内にある UI」。常時出る補助表示は増やしすぎない

## 7. アクセシビリティ

- 点滅は毎秒3回以内（WCAG 2.3.1）。揺れ・点滅を弱めるオプションを用意する
  - [Xbox Accessibility Guidelines](https://learn.microsoft.com/en-us/xbox/accessibility/xag-version-history) / [Gaming Accessibility Options](https://gloobia.com/gaming-accessibility-options/)
  - **確認**: 人影のちらつきは約1.4回/秒、映像全体のちらつきは小さな明るさの揺れ。映像の乱れは横帯のずれで明るさの点滅ではない。失敗時の赤い点滅は1回。「演出を弱める」で抑えられる
  - **反映**: 解像度が変わっても画面が拡大縮小して崩れないよう、ウィンドウの拡大縮小設定を追加。F11 で全画面

## 8. 画面の拡大縮小（Godot 4）

- 画面の大きさが変わると配置が崩れる。アンカーやコンテナを使うか、プロジェクトの拡大縮小設定を使う
  - [Control Nodes and Layout Containers](https://uhiyama-lab.com/en/notes/godot/control-layout-containers/) / [Exploring UI node anchors](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/telling_a_story/first_ui_exploration)
  - **反映**: プロジェクト設定で `canvas_items`＋`keep`（縦横比を保って全体を拡大縮小）。絶対座標の配置はそのまま使える

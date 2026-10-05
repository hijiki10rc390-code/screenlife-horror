# 計画 03: 好感度（信頼度）の見える化

## 目的
魅力の柱「可愛い女の子」を伸ばす（docs/character-direction.md の優先 2）。いまの「信頼度」（`belief`）は、画面に数字（`信頼 30%`）で出るだけ。これを、見て分かるゲージにし、信頼が高まると相手の台詞が親しげに変わるようにする。
対象は「疑り深い相手」のステージ（`use_phrases == true`、いまは stage2 だけ）。ほかのステージの見た目・動作は変えない。

## 仕様
1. **信頼ゲージ**（`use_phrases` のステージだけ）
   - 映像の上端のすぐ上（タイトルバーと映像のあいだ）に、細い横棒を出す。位置 `VIDEO_POS.y - 8` あたり、x は `VIDEO_POS.x`、幅は `VIDEO_SIZE.x`（750）、高さ 5px。背景（暗い色 `Color(0.1, 0.1, 0.14)`）と、中身（`belief` に比例した幅）の 2 つの `ColorRect`
   - 中身の色: `belief` が 0.0〜0.5 は赤みのある色 `Color(0.75, 0.3, 0.3)`、0.5〜0.8 は琥珀色 `Color(0.85, 0.65, 0.25)`、0.8 以上は緑 `Color(0.35, 0.75, 0.5)`。色は `belief` に応じてなめらかに（`lerp`）変える
   - 毎フレーム `_process` で更新する。幅の変化は急にせず、`move_toward` などで 1 秒に 0.5 ぶんほどの速さで追従させる（見た目だけ。判定には使わない）
   - 既存の `status_label` の `信頼 N%` の表示はそのまま残す
   - ゲージは変数 `trust_bar_fill`（中身の ColorRect）を使い、テストから幅を読めるようにする
2. **信頼で変わる台詞**
   - ステージ設定に、任意の項目 `idle_trust` を足す: `{"low": [...], "high": [...]}`。無ければ従来の `idle`（`idle_lines`）だけを使う（stage1 の挙動は変えない）
   - `_on_talk` で、`idle_trust` があるとき: `belief >= 0.6` なら `high` の台詞、そうでなければ `low` の台詞を、それぞれの中で順番に（`idle_idx` と同様に、別の添字で）出す。`belief` は **話しかけの効果を足す前** の値で判定する
   - `idle_trust` が空・片方が空のときは、`idle_lines` にフォールバックする
3. **信頼が高まった瞬間の一言**
   - ステージ設定に、任意の項目 `trust_milestone_line`（文字列）を足す。`belief` が初めて 0.6 以上になった瞬間（`_on_talk` の中で、足したあとに判定）、1 回だけ `_say(friend, その台詞)` を出し、`hint_label.text = "信頼が高まった。警告が通りやすくなる。"` にする
   - 1 回だけ出すための変数（例: `milestone_said`）を使う
4. **ステージ設定（stages/stage2.json）**
   - `"idle_trust": {"low": ["うん…。", "そっか…。", "…ありがと。"], "high": ["ありがと。話してると、落ち着く。", "なんか、あなたの声だと安心するな。", "ねえ、このまま通話してていい？"]}`
   - `"trust_milestone_line": "…ちょっと話したら、気が楽になった。ありがとね。"`
   - 既存の `idle` はそのまま残す
5. **難易度レポート（balance_report.py）**: `belief` が 0.6 に達するのに必要な話しかけの回数（初期値 `belief_start`、1 回あたり `TALK_TRUST`）を、疑り深い相手のステージに `信頼 60% まで 話しかけ N 回` と 1 行足す。ほかの出力は変えない

## テスト（tests/test_logic.gd の末尾の `quit(...)` の直前に足す。既存のテストは変更しない）
- stage2 で `trust_bar_fill` があり、`_start_call()` のあと `_process` を数フレーム回すと、幅が `VIDEO_SIZE.x * belief`（初期値 0.3）に近づく（誤差 ±10%、追従の速さを考えて十分な回数を回す）
- stage1 では、信頼ゲージが表示されない（`trust_bar_fill == null` または親が invisible。実装に合わせてよい）
- `belief` を 0.7 にして `_on_talk()` → 直近のチャットに `high` の台詞のどれかが含まれる（`chat_log.get_parsed_text()`）
- `belief` を 0.2 にして `_on_talk()` → `low` の台詞のどれかが含まれる
- `belief` を 0.58（`TALK_TRUST` 0.05 で 0.63 になる値）にして `_on_talk()` → `trust_milestone_line` がチャットに出る。もう一度（クールダウン `talk_left = 0` にして）`_on_talk()` しても、一言は 2 回目が出ない（本文の出現回数が 1 回）
- stage1 で `_on_talk()` を呼ぶと、`idle_lines` の台詞が出る（従来どおり）

## 受け入れ条件
- `bash tools/run_tests.sh` が成功する（既存 112 件 + 新規）
- `bash tools/shot.sh 2` がエラーなく終わる（実際の画面でゲージが出る）
- stage1・stage3 の見た目・動作が変わらない

## やらないこと
- 新しい画像・効果音・シェーダーの追加
- stage1・stage3 の設定の変更
- 信頼の増え方・判定（`TALK_TRUST`、`PHRASE_BONUS` など）の変更
- `tools/`・`project.godot` の変更（禁止されている）
- 既存のテストの変更・削除

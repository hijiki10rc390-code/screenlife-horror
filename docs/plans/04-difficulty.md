# 計画 04: 難易度の選択（やさしい / ふつう / むずかしい）

## 目的
初めて遊ぶ人にも、繰り返し遊ぶ人にも合うよう、難易度を選べるようにする（遊びやすさ・アクセシビリティ）。画像・音の追加は不要。ゲームの仕組みと画面（タイトル・一時停止）の変更だけ。

## 難易度の中身（0=やさしい / 1=ふつう / 2=むずかしい。既定は 1 で、いまの挙動と完全に同じ）
| 項目 | やさしい | ふつう | むずかしい |
|---|---|---|---|
| 誤警告の上限（失敗になる回数） | 5 | 3 | 2 |
| 誤警告のあと警告できない秒数 | 2.0 | 3.0 | 4.0 |
| 制限時間（`fail_at`）の倍率 | 1.25 | 1.0 | 0.9 |
| 疑り深い相手の初期信頼への加算（`belief_start` が 1.0 未満のステージだけ） | +0.1 | 0 | -0.1 |
| 配信で必要な警告コメントの数への加算（`need_warnings`、最小 2） | -1 | 0 | +1 |

## 仕様
1. **変数と定数**（main.gd）
   - 定数 `DIFFICULTY_NAMES := ["やさしい", "ふつう", "むずかしい"]` と、上の表を持つ定数（辞書の配列など。見やすく）
   - `static var difficulty := 1`（`stage_no` と同じく、画面の再読み込みをまたいで保持する）
   - 既存の定数 `MAX_FALSE_ALARMS`（3）と `FALSE_ALARM_LOCK`（3.0）は、**既定値として残す**（テストが参照している）。新しく変数 `max_false_alarms`、`false_alarm_lock` を作り、実際の判定にはこちらを使う
2. **適用**: `_apply_difficulty()` を作り、`_ready` で `_load_stage()` と `_load_settings()` の**両方のあと**に 1 回だけ呼ぶ。内容は、表のとおりに `max_false_alarms`・`false_alarm_lock`・`fail_at`（掛ける）・`belief_start`（加算、0.05〜0.95 に収める。`belief_start >= 1.0` のステージは変えない）・`belief`（`belief_start` と同じにする）・`need_warnings`（配信だけ）を設定する
3. **判定の置き換え**: `MAX_FALSE_ALARMS` を使っている箇所（`_on_warn`、`_on_comment`、`_finish`、`_process` の表示 `誤警告 %d/%d`）を `max_false_alarms` に、`FALSE_ALARM_LOCK` を使っている箇所を `false_alarm_lock` に置き換える。ヒント文などに「3回」と直接書かれている箇所があれば、`max_false_alarms` から作る
4. **設定の保存**: `settings.cfg` の `[game]` に `difficulty` を保存・読み込み（`_save_settings`・`_load_settings`）
   - **重要**: `persist == false`（テスト用）のときは、`_load_settings` も何もしない（早期 return）。保存した設定が、テストの結果を変えないようにするため
5. **タイトル画面**: 副題（`（仮題）画面の向こうの異変に…`）と「はじめから」ボタンのあいだ（y=270 前後）に、「難しさ」の見出しと、3 つのボタン（やさしい / ふつう / むずかしい）を横に並べる（幅 120、高さ 40、間隔 10、中央寄せ）。選んでいるものを明るく（`_button` の色を変えるか、`modulate`）。押すと `difficulty` を変えて保存し、見た目を更新する。タイトル画面は画面の再読み込みなしで更新する（`_title_start` で再読み込みされるまでは、同じ画面のまま）
6. **一時停止画面**: 「再開」ボタンの下（y=565 前後）に `難しさ: ふつう（変更はタイトル画面から）` を表示する（読み取りだけ）。難易度を途中で変えられると、判定が不整合になるため
7. **難易度レポート**（balance_report.py）: ステージごとに 1 行足す。`難しさ別（やさしい/ふつう/むずかしい）: 制限時間 137/110/99秒 / 誤警告の上限 5/3/2`（制限時間は `fail_at` の倍率を掛けて整数に丸める）。疑り深い相手のステージには、初期信頼も `初期信頼 0.40/0.30/0.20` と足す。ほかの出力は変えない

## テスト（tests/test_logic.gd の末尾の `quit(...)` の直前に足す。既存のテストは変更しない）
- 各難易度 d（0〜2）について、`S.difficulty = d` にしてから `fresh()` し、stage1（`S.stage_no = 0`）で `m.max_false_alarms`、`m.false_alarm_lock`、`m.fail_at`（110 に倍率）が表のとおりになる。終わったら `S.difficulty = 1`
- stage2（`S.stage_no = 1`）で `m.belief_start` が 0.4 / 0.3 / 0.2、`m.belief` も同じ値
- stage3（`S.stage_no = 2`）で `m.need_warnings` が 2 / 3 / 4
- stage1 は `belief_start >= 1.0` なので、どの難易度でも `belief_start` が 1.0 のまま
- むずかしい（`S.difficulty = 2`）で stage1: 人影が映る前の誤警告 2 回で `m.state == m.State.FAILED`（`lock_left = 0.0` にして連続で警告する）
- やさしい（`S.difficulty = 0`）で stage1: 誤警告 3 回では失敗にならず、5 回で失敗になる
- `persist == false` のときは設定を読まない: `S.difficulty = 1` で `fresh()`（`persist = false`）し、`m.max_false_alarms == 3`（保存済みの設定があっても変わらない）
- タイトル画面（`S.title_done = false` で `fresh()`）に、難しさの 3 つのボタンがある（見つけ方は実装に合わせてよい）

## テスト（tests/test_playthrough.gd の末尾の `quit(...)` の直前に足す。既存のテストは変更しない）
- 3 つの難易度 × 全ステージで、名人ボット（既存の `play_master`）が救出できる（`S.difficulty = d` にしてから `fresh()`、終わったら `S.difficulty = 1`、`S.stage_no = 0`）
- 3 つの難易度 × 全ステージで、放置ボット（既存の `play_idle`）は時間切れ失敗になる

## 受け入れ条件
- `bash tools/run_tests.sh` が成功する（既存 122 件 + 新規）
- `bash tools/shot.sh 1` がエラーなく終わる。タイトル画面は `-- --title-shot` で撮れる（Godot を直接実行する必要があるので、撮影はレビュー側で行う）。コードを読んで配置の重なりがないか確認する
- 難易度「ふつう」の挙動が、いまと完全に同じ

## やらないこと
- 難易度ごとの画像・音・台詞の追加
- 途中で難易度を変える機能
- 時間割（`ghost_curve`）や緩和（`relief`）の変更
- `tools/`・`project.godot` の変更（禁止されている）
- 既存のテストの変更・削除（`MAX_FALSE_ALARMS`・`FALSE_ALARM_LOCK` の定数を残すので、置き換えは不要のはず）

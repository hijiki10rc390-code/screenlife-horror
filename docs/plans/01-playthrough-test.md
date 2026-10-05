# 計画 01: 自動の通しプレイのテスト

## 目的
人の代わりにプログラム（ボット）が全ステージを遊び、「詰まらない・落ちない・終わり方が正しい」ことを確認する回帰テストを作る。
**ゲーム本体（main.gd・stages/*.json など）は変更しない。** テストファイルだけを新規作成する。

## 作るもの
`tests/test_playthrough.gd`（新規）。`tools/run_tests.sh` が `tests/test_*.gd` を自動で拾うので、ほかの設定は不要。

## 書き方（既存の `tests/test_logic.gd` と同じ形式）
- `extends SceneTree`、`var fails := 0`、`check(name, cond)` で `OK   名前` / `NG   名前` を出力、最後に `quit(1 if fails > 0 else 0)`
- `fresh()` で `res://main.tscn` を instantiate し、**add_child の前に `m.persist = false`**（実際の設定・進行を書き換えないため）、add_child 後に `await process_frame`
- ステージは `var S: GDScript = load("res://main.gd")` の `S.stage_no = n`（0 始まり）で選ぶ。`S.STAGE_FILES.size()` がステージ数。テストの最初に `S.title_done = true`、最後に `S.stage_no = 0` に戻す
- 時間は実時間で待たず、`m._process(0.1)` を繰り返し呼んで進める（`_start_call()` のあとは state が PLAYING なので、`m.t` が 0.1 ずつ増える）。1回の `_process` で 0.1 秒
- ゲーム側の関数・変数（既存、変更しない）: `m._start_call()`, `m._on_warn(phrase := 0)`, `m._on_comment(i)`, `m._on_talk()`, `m._set_mark(Vector2)`, `m._set_paused(bool)`, `m.state`（`m.State.PLAYING/SAVED/FAILED`）, `m.t`, `m.fail_at`, `m.mode`（"call"/"stream"）, `m.use_phrases`, `m.belief`, `m.lock_left`, `m.talk_left`, `m.ghost_box`（Rect2。`get_center()` が人影の位置）, `m.ghost_layer.modulate.a`（人影の濃さ）, `m._first_seen_time()`, `m._next_stage_no()`, `m.false_alarms`, `m.MAX_FALSE_ALARMS`

## テストの内容
1. **名人ボット（全ステージ）**: 各ステージで、`_start_call()` のあと 0.1 秒ずつ進め、次のやり方で救出できること（制限時間 `m.fail_at` までに state が SAVED になる）。
   - 通話（`mode == "call"` で `use_phrases == false`）: 人影が映る時刻（`_first_seen_time()` + 2 秒）を過ぎたら、`_set_mark(m.ghost_box.get_center())` → `_on_warn()`
   - 疑り深い相手（`use_phrases == true`）: 4.1 秒おきに `_on_talk()`。人影の濃さが 0.5 以上になったら `_set_mark(m.ghost_box.get_center())` → `_on_warn(1)`（「逃げて！」）。信頼不足で流されたら、`lock_left` が 0 になるまで進めて、もう一度警告する
   - 配信（`mode == "stream"`）: 人影が映る時刻 + 2 秒を過ぎたら、`lock_left == 0` のとき `_on_comment(0)` を 1 秒おきに（3 回で救出される）
2. **放置ボット（全ステージ）**: 何もしない → `m.fail_at` を過ぎると state が FAILED になる
3. **連打ボット（全ステージ）**: 0.5 秒ごとに、人影のいない場所（例: `Vector2(50, 50)`）を指して警告（配信は `_on_comment(0)`、人影が映る前の 10 秒間だけ）。誤警告が `m.MAX_FALSE_ALARMS` 回になる前に FAILED になること、`lock_left` が 0 を超えている間は誤警告が増えないこと（連打しても 1 回分）
4. **連続クリア**: ステージ 0 → 1 → 2 を、名人ボットで順にクリア。クリアのたびに `m._next_stage_no()` が次の番号になり、最後のステージのクリアでは 0 に戻ること
5. **不変条件**: 名人ボットのプレイ中、毎フレーム次が成り立つ。人影の濃さは 0〜1、`m.t` は減らない、`m.lock_left >= 0`、`m.talk_left >= 0`、`m.belief` は 0〜1
6. **一時停止**: プレイ中に `_set_paused(true)` → `_process(0.1)` を 20 回 → `m.t` が変わらない → `_set_paused(false)` → `_process(0.1)` で `m.t` が増える

## 実装のヒント
- ボットは関数にまとめる（例: `play_master(m) -> bool`、`play_idle(m)`、`play_masher(m)`）。ステージごとのループで使い回す
- 無限ループ防止: 進める回数に上限を付ける（`m.fail_at / 0.1 + 50` 回まで）
- 各テストの最後に `m.queue_free()`

## 受け入れ条件
- `bash tools/run_tests.sh` が成功する（test_logic.gd の 76 件と、新しい test_playthrough.gd の全部が OK）
- ゲーム本体のファイルに差分がない

## やらないこと
- main.gd・stages/*.json・audio_manager.gd・シェーダーの変更（バグらしきものを見つけたら、直さずに報告する）
- 既存の tests/test_logic.gd の変更

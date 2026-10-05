# 計画 05: 人影の動きと迫力（棒立ちをやめる）

## 目的
ユーザーの指摘: 「霊や犯罪者が棒立ちで迫力がない」。いまは人影が同じ場所で濃くなるだけ。**動き・不意打ち・音の方向・照明の反応**で迫力を出す。画像の追加は不要（既存の重ね画像を、コードで動かす）。

## 仕様

### 1. 人影の道筋（`ghost_path`）
ステージ設定に任意の項目 `ghost_path`: `[[秒, dx, dy, 倍率], ...]`（時刻順）。重ね画像を、元の位置から (dx, dy) ピクセルずらし、大きさに倍率を掛ける。キー間は、なめらかに補間する（`smoothstep` 相当）。範囲の外は、最初／最後の値のまま。無ければ従来どおり（ずれなし・倍率 1）。
- 関数を作る: `ghost_offset_at(time) -> Vector2`（dx, dy）、`ghost_mult_at(time) -> float`（倍率）、`ghost_box_now() -> Rect2`（`ghost_box` を、いまの `ghost_offset_at(t)` だけ平行移動した範囲）
- **警告の当たり判定は `ghost_box_now()` を使う**（`_on_warn` の `ghost_box.has_point(mark_scene)`）。人影が動いたら、当たり判定も一緒に動く
- 描画: `_process` で `ghost_layer.position = ghost_offset_at(t) + 揺れ`。大きさは今の `ghost_scale` の補間（`approach`）に `ghost_mult_at(t)` を掛ける
- 設定値（stages/*.json に足す）:
  - stage1: `"ghost_path": [[28, 0, 0, 1.0], [70, -25, 0, 1.0], [95, -80, 10, 1.05]]`（左の彼女のほうへ、ゆっくり寄ってくる）
  - stage2: `"ghost_path": [[22, 0, 0, 1.0], [50, 0, 0, 1.0], [66, 30, 0, 1.0], [85, 100, 10, 1.05]]`（ドアの奥から、部屋へ出てくる）
  - stage3: `"ghost_path": [[25, 0, 0, 1.0], [60, 50, 0, 1.0], [84, 140, 12, 1.05]]`（壁際から、配信者のほうへ寄る）

### 2. 揺れとコマ落ち（不気味さ）
- **揺れ**: 人影の位置に、ごく小さな揺れ（呼吸のよう）を足す。`Vector2(sin(clock * 0.8) * 2.0, sin(clock * 1.3) * 1.5) * _curve_alpha(t)`（`clock = Time.get_ticks_msec() / 1000.0`）
- **コマ落ち**: 人影の濃さが 0.3 以上の間、0.6〜2.0 秒に 1 回（乱数）、0.07 秒だけ、人影の位置がランダムに ±6px 飛び、濃さが半分になる。ストップモーションのような不自然さを出す。変数 `stutter_left`（残り秒数）などで管理する
- **「演出を弱める」（`calm`）では、揺れもコマ落ちも出さない**

### 3. 失敗の瞬間の「襲いかかり」（`lunge`）
- 失敗した瞬間（`_finish(State.FAILED, ...)`。時間切れでも、信頼を失った場合でも）、人影がカメラに向かって襲いかかる: 0.35 秒かけて、大きさを `現在の大きさ → 2.6 倍` に、位置を **映像の中心**（`Vector2(SCENE_W, SCENE_H) / 2`）へ、加速しながら（`progress * progress`）寄せる。変数 `lunge`（0〜1）を、失敗後に `move_toward(lunge, 1.0, delta / 0.35)` で進める
- 襲いかかりの間、`_process` の通常の大きさ・位置の更新は、`lunge` に置き換える（上書きしない）
- 結果画面（`end_panel`）の出現を、襲いかかりが終わるまで遅らせる（0.5 秒の `tween_interval` のあとに、既存の 0.5 秒のフェードイン）
- `calm` のときは、大きさを 1.4 倍までにし、時間を 0.6 秒にする（急な動きを避ける）。既存の画面の揺れ・点滅の抑制はそのまま

### 4. 音の方向
- `audio_manager.gd` の `Ambient` バスと `Sfx` バスに、`AudioEffectPanner` を足す（既にある効果の後ろ。バスを作り直すたびに重複しないよう、効果の数で確かめる）
- `audio.update(...)` に引数 `pan: float`（-1〜1）を足し、両方のバスのパンナーの `pan` に反映する。`main.gd` からは、`pan = clampf((映像内の人影の中心 x / SCENE_W) * 2.0 - 1.0, -1.0, 1.0) * 0.6`（人影の中心 = `ghost_box_now().get_center().x`）を渡す。`calm` でも有効（音の位置の手がかり）
- `audio.update` を呼んでいる他の場所（テスト含む）の引数を、合わせる

### 5. 照明の反応（きしみに合わせた暗転）
- `webcam.gdshader` に `uniform float dim = 0.0;` を足し、`c *= 1.0 - dim * 0.6;` を、最終の `COLOR` の直前に入れる
- `main.gd`: きしみの音（`creaks` の時刻、緩和の終わり）が鳴った瞬間から 0.3 秒、`dim` を `0.5 * (0.5 + 0.5 * sin(経過 * 60.0))` のように素早く点滅させ、0.3 秒で 0 に戻す。変数 `dim_left`。`cam_mat.set_shader_parameter("dim", ...)` で反映。**`calm` のときは常に 0**

## テスト（tests/test_logic.gd の末尾の `quit(...)` の直前に足す）
- `ghost_offset_at`: stage1 で 28 秒は (0,0)、95 秒は (-80,10)、70 秒は (-25,0)。`ghost_mult_at(95.0)` は 1.05。キーの外（0 秒）は最初の値。`ghost_path` が無い設定（例えば stage1 の `ghost_path` を空にした状態）では (0,0) と 1.0
- `ghost_box_now()`: stage1 で 95 秒のとき、`ghost_box.position + Vector2(-80, 10)` に一致
- 判定が人影と一緒に動く: stage1 で、`at(m, 90.0)`、`m._set_mark(m.ghost_box.get_center())`（元の位置）→ `_on_warn()` が**救出にならない**（誤警告）。`m._set_mark(m.ghost_box_now().get_center())` なら救出になる（新しいボットで確かめる。同じ `m` を使い回さず、それぞれ新しく `fresh()` する）
- 揺れ・コマ落ち: `calm = false` で、濃さが 0.3 以上の状態を作り、`_process` を数百回回すと、`ghost_layer.position` が `ghost_offset_at(t)` からずれる回がある。`calm = true` では、常に `ghost_offset_at(t)` と一致（揺れなし）
- 襲いかかり: `at(m, m.fail_at + 1.0)` で FAILED → `_process(0.1)` を 5 回 → `ghost_layer.scale.x >= 2.0`。`calm = true` では、同じ手順のあと `ghost_layer.scale.x` が `ghost_scale` の最大値より大きく、かつ 1.6 以下
- 音の方向: stage1 で `at(m, 90.0)` のあと、`Sfx` バスのパンナーの `pan` が正（人影は右寄り）、stage2 で負（左寄り）。取得は `AudioServer.get_bus_effect(AudioServer.get_bus_index("Sfx"), 1)`（インデックスは実装に合わせてよい）
- 照明: `creaks` の時刻を過ぎた直後のフレームで `dim` が 0 より大きい。`calm = true` では常に 0

## 既存のテストについて
- 既存のテスト・ボットが `m.ghost_box.get_center()` で人影を指している箇所は、人影が動くようになるので、**`m.ghost_box_now().get_center()` に置き換えてよい**（`tests/test_logic.gd` と `tests/test_playthrough.gd`）。置き換えた箇所は報告する。それ以外の既存テストは変更しない
- `audio.update` の引数が増える影響で、直す必要があれば直す

## 受け入れ条件
- `bash tools/run_tests.sh` が成功する（既存 169 件 + 新規）
- `bash tools/shot.sh 1` / `2` / `3` がエラーなく終わる
- 難易度「ふつう」の判定のしくみ（誤警告の上限・ロック・信頼）は変わらない。人影が動くだけ

## やらないこと
- 新しい画像・効果音の追加
- 難易度の数値（`fail_at`・誤警告の上限など）の変更（次の計画で行う）
- UI の見た目の変更
- `tools/`・`project.godot` の変更（禁止されている）
- 既存のテストの削除

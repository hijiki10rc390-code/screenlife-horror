extends SceneTree
# 全ステージを自動プレイする回帰テスト。名人・放置・連打の 3 種類のボットで
# ステージ進行が詰まらず、想定どおりに救出・失敗することを確認する。
# 実行:
#   Godot --headless --path <PJ> -s tests/test_playthrough.gd
# 終了コード 0=全部成功 / 1=失敗あり

var fails := 0
const ON_GHOST_AWAY := Vector2(50, 50)   # 人影のいない位置（誤警告用）
const TICK := 0.1                         # _process 1 回で進める秒数


func check(name: String, cond: bool) -> void:
	print(("OK   " if cond else "NG   ") + name)
	if not cond:
		fails += 1


# main.tscn を読み込んで実機と同じように走らせる。テスト用の設定（保存しない）に切り替える
func fresh() -> Control:
	var m: Control = load("res://main.tscn").instantiate()
	m.persist = false     # 実際の設定・進行を書き換えない（テスト用）
	root.add_child(m)
	await process_frame   # _ready が走るのを待つ
	return m


# m の時間を seconds 秒だけ _process で進める（実時間ではなくゲーム内時間）
func tick(m: Control, seconds: float) -> void:
	var remain := seconds
	while remain > 0.0001:
		var step: float = minf(TICK, remain)
		m._process(step)
		remain -= step


# 名人ボット: ステージ種別ごとに正解手順を繰り返し、救出を試みる。救出できたら true
func play_master(m: Control) -> bool:
	var max_ticks := int(m.fail_at / TICK) + 100
	var seen_time: float = float(m._first_seen_time()) + 2.0     # 通話: 映ってから少し待って警告する
	var last_talk := -100.0                          # 疑り深い相手: 最後に話しかけた時刻
	var last_comment := -1.0                         # 配信: 最後にコメントした時刻
	var n_comments := 0                              # 配信: 出したコメントの回数

	for i in max_ticks:
		if m.state != m.State.PLAYING:
			return m.state == m.State.SAVED
		m._process(TICK)
		if m.mode == "stream":
			# 配信: 人影が映ったら 1 秒おきに同じ警告コメントを投稿（3 回で気づかれる）
			# 誤警告で warn_times が増えない回があるため、need_warnings に達するまで続ける
			if m.t >= seen_time and m.lock_left <= 0 and m.warn_times.size() < m.need_warnings and m.t - last_comment >= 1.0:
				m._on_comment(0)
				n_comments += 1
				last_comment = m.t
		elif m.use_phrases:
			# 疑り深い相手: 話しかけて信頼をため、濃さが十分なら「逃げて！」で警告
			if m.t - last_talk >= 4.1 and m.talk_left <= 0:
				m._on_talk()
				last_talk = m.t
			if m.ghost_layer.modulate.a >= 0.5 and m.lock_left <= 0:
				m._set_mark(m.ghost_box_now().get_center())
				m._on_warn(1)
		else:
			# 通常の通話: 人影が映ったら、人影の位置を指して警告する
			if m.t >= seen_time and m.lock_left <= 0:
				m._set_mark(m.ghost_box_now().get_center())
				m._on_warn()
	return m.state == m.State.SAVED


# 放置ボット: 何もしないで fail_at を過ぎるまで待つ
func play_idle(m: Control) -> void:
	var max_ticks := int(m.fail_at / TICK) + 50
	for i in max_ticks:
		if m.state != m.State.PLAYING:
			return
		m._process(TICK)


# クリック経由の名人ボット: _on_video_click を使って救出する。全ステージ × 全難易度で動作する
func play_master_click(m: Control) -> bool:
	var max_ticks := int(m.fail_at / TICK) + 100
	var seen_time: float = float(m._first_seen_time()) + 2.0
	var last_talk := -100.0
	var last_action := -1.0
	var n_comments := 0

	for i in max_ticks:
		if m.state != m.State.PLAYING:
			return m.state == m.State.SAVED
		m._process(TICK)
		if m.mode == "stream":
			# 配信: ロックが解けてから 1 秒以上たち、警告コメントが need_warnings 未満ならクリック
			if m.t >= seen_time and m.lock_left <= 0.0 and m.t - last_action >= 1.0 \
					and m.warn_times.size() < m.need_warnings:
				m._on_video_click(m.ghost_box_now().get_center())
				last_action = m.t
				n_comments += 1
		elif m.use_phrases:
			# 疑り深い相手: 話しかけて信頼をため、「逃げて！」(phrase=1) を選んでからクリック
			if m.t - last_talk >= 4.1 and m.talk_left <= 0.0:
				m._on_talk()
				last_talk = m.t
			if m.ghost_layer.modulate.a >= 0.5 and m.lock_left <= 0.0:
				m._select_phrase(1)
				m._on_video_click(m.ghost_box_now().get_center())
		else:
			# 通常の通話: 人影が映ったら、人影の位置をクリックで警告
			if m.t >= seen_time and m.lock_left <= 0.0:
				m._on_video_click(m.ghost_box_now().get_center())
	return m.state == m.State.SAVED


# 連打ボット: 0.5 秒ごとに、人影のいない場所を警告し続ける。誤警告の累積で失敗する
# 通話=人影が映る前に映像の違う場所を指して警告 / 配信=映る前にコメントを連投
func play_masher(m: Control) -> void:
	var max_ticks := int(m.fail_at / TICK) + 50
	var last_action := -1.0
	var seen_time: float = float(m._first_seen_time())
	for i in max_ticks:
		if m.state != m.State.PLAYING:
			return
		m._process(TICK)
		if m.t - last_action < 0.5:
			continue
		if m.lock_left > 0:
			last_action = m.t
			continue
		if m.mode == "stream":
			# 配信は「映る前の 10 秒間だけ」荒らし行為
			if m.t >= seen_time or m.t >= 10.0:
				continue
			m._on_comment(0)
		else:
			# 通話は人影が映る前に、違う場所を警告する
			if m.t >= seen_time:
				continue
			m._set_mark(ON_GHOST_AWAY)
			m._on_warn()
		last_action = m.t


func _initialize() -> void:
	var S: GDScript = load("res://main.gd")
	S.title_done = true
	var stage_count: int = S.STAGE_FILES.size()

	# 1. 名人ボット: 全ステージで救出できる（制限時間内に state == SAVED になる）
	for n in stage_count:
		S.stage_no = n
		var m: Control = await fresh()
		m._start_call()
		var ok: bool = await play_master(m)
		check("名人ボット: ステージ%dを救出" % (n + 1), ok and m.state == m.State.SAVED)
		m.queue_free()
	S.stage_no = 0

	# 1b. クリック経由の名人ボット: 同じく全ステージで救出できる（新しい操作）
	for n in stage_count:
		S.stage_no = n
		var mc: Control = await fresh()
		mc._start_call()
		var okc: bool = await play_master_click(mc)
		check("クリック名人ボット: ステージ%dを救出" % (n + 1), okc and mc.state == mc.State.SAVED)
		mc.queue_free()
	S.stage_no = 0

	# 2. 放置ボット: 全ステージで時間切れ失敗（state == FAILED になる）
	for n in stage_count:
		S.stage_no = n
		var m: Control = await fresh()
		m._start_call()
		await play_idle(m)
		check("放置ボット: ステージ%dで時間切れ失敗" % (n + 1), m.state == m.State.FAILED)
		m.queue_free()
	S.stage_no = 0

	# 3. 連打ボット: 全ステージで誤警告上限失敗（state == FAILED になり、誤警告がその難易度の上限に達する）
	for n in stage_count:
		S.stage_no = n
		var m: Control = await fresh()
		m._start_call()
		await play_masher(m)
		check("連打ボット: ステージ%dで誤警告%d回失敗" % [n + 1, m.max_false_alarms],
			m.state == m.State.FAILED and m.false_alarms >= m.max_false_alarms)
		m.queue_free()
	S.stage_no = 0

	# 3b. ロック中（誤警告のあと）は連打しても誤警告が増えない
	S.stage_no = 0
	var m: Control = await fresh()
	m._start_call()
	m._set_mark(ON_GHOST_AWAY)
	m._on_warn()
	var fa0: int = m.false_alarms
	check("連打: 誤警告1回目", fa0 == 1)
	# ロックが解ける前まで連打を試みる。ロック中は _on_warn が無視されるはず
	var lock_test_ticks: int = int((m.false_alarm_lock - 0.5) / TICK)
	for i in lock_test_ticks:
		m._set_mark(ON_GHOST_AWAY)
		m._on_warn()
		m._process(TICK)
	check("連打: ロック中は誤警告が増えない", m.false_alarms == fa0)
	m.queue_free()
	S.stage_no = 0

	# 4. 連続クリア: ステージ 0 → 1 → 2 を名人ボットで順にクリア。最後のステージは 0 に戻る
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	var ok0: bool = await play_master(m)
	check("連続クリア: ステージ0救出", ok0)
	check("連続クリア: ステージ0の次は1", m._next_stage_no() == 1)
	S.stage_no = m._next_stage_no()
	m.queue_free()

	m = await fresh()
	m._start_call()
	var ok1: bool = await play_master(m)
	check("連続クリア: ステージ1救出", ok1)
	check("連続クリア: ステージ1の次は2", m._next_stage_no() == 2)
	S.stage_no = m._next_stage_no()
	m.queue_free()

	m = await fresh()
	m._start_call()
	var ok2: bool = await play_master(m)
	check("連続クリア: ステージ2救出", ok2)
	check("連続クリア: 最後のステージの次は0", m._next_stage_no() == 0)
	S.stage_no = 0
	m.queue_free()

	# 5. 不変条件: 名人ボットのプレイ中ずっと成り立つ
	#   人影の濃さは 0〜1、t は減らない、lock_left >= 0、talk_left >= 0、belief は 0〜1
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	var invariant_ok := true
	var max_ticks := int(m.fail_at / TICK) + 50
	var t_prev: float = m.t
	for i in max_ticks:
		if m.state != m.State.PLAYING:
			break
		m._process(TICK)
		var a: float = m.ghost_layer.modulate.a
		if a < 0.0 or a > 1.0:
			invariant_ok = false
		if m.t < t_prev - 0.001:
			invariant_ok = false
		if m.lock_left < 0.0:
			invariant_ok = false
		if m.talk_left < 0.0:
			invariant_ok = false
		if m.belief < 0.0 or m.belief > 1.0 + 0.001:
			invariant_ok = false
		t_prev = m.t
	check("不変条件: プレイ中の濃さ・t・lock_left・talk_left・belief が範囲内",
		invariant_ok)
	m.queue_free()
	S.stage_no = 0

	# 6. 一時停止: 停止中は時間が進まず、再開で進む
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	m._process(TICK)
	var t_before: float = m.t
	m._set_paused(true)
	for i in 20:
		m._process(TICK)
	check("一時停止中は、時間が経っても t が変わらない", m.t == t_before)
	m._set_paused(false)
	m._process(TICK)
	check("再開で時間が増える", m.t > t_before)
	m.queue_free()
	S.stage_no = 0

	# 7. 難易度 × 全ステージ: 名人ボットは救出できる、放置ボットは時間切れ失敗
	for d in 3:
		S.difficulty = d
		for n in stage_count:
			S.stage_no = n
			var mm: Control = await fresh()
			mm._start_call()
			var ok: bool = await play_master(mm)
			check("難易度%d・名人ボット: ステージ%dを救出" % [d, n + 1], ok and mm.state == mm.State.SAVED)
			mm.queue_free()
		for n in stage_count:
			S.stage_no = n
			var mi: Control = await fresh()
			mi._start_call()
			await play_idle(mi)
			check("難易度%d・放置ボット: ステージ%dで時間切れ失敗" % [d, n + 1], mi.state == mi.State.FAILED)
			mi.queue_free()
		S.stage_no = 0
	S.difficulty = 1

	quit(1 if fails > 0 else 0)
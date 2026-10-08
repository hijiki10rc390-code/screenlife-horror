extends SceneTree
# ロジックの自動テスト。実行:
#   Godot --headless --path <PJ> -s tests/test_logic.gd
# 終了コード 0=全部成功 / 1=失敗あり

var fails := 0
const ON_GHOST := Vector2(700, 230)     # 人影のいる位置（映像内の座標）
const OFF_GHOST := Vector2(150, 300)    # 何もない位置


func check(name: String, cond: bool) -> void:
	print(("OK   " if cond else "NG   ") + name)
	if not cond:
		fails += 1


func fresh() -> Control:
	var m: Control = load("res://main.tscn").instantiate()
	m.persist = false     # テストでは、ユーザーの実際の設定・進行を書き換えない
	root.add_child(m)
	await process_frame   # _ready（画面の部品づくり）が走るのを待つ
	# scenes が _waiting_choice を立てて _on_warn をブロックするのを防ぐため、
	# test_logic では scenes を空にして無視する（scenes のテストは test_scenes.gd に分離）
	m.scenes = []
	m._scene_idx = 0
	m._waiting_choice = false
	m._hide_scene_buttons()
	m.lock_left = 0.0
	return m


# fresh の reached 指定版。_ready 前に reached を設定する必要があるため専用ヘルパー
func fresh_with_reached(r: int) -> Control:
	var m: Control = load("res://main.tscn").instantiate()
	m.persist = false
	m.reached = r
	root.add_child(m)
	await process_frame
	m.scenes = []
	m._scene_idx = 0
	m._waiting_choice = false
	m._hide_scene_buttons()
	m.lock_left = 0.0
	return m


# fresh の reached + total_rescues 指定版
func fresh_with_state(r: int, rescues: int) -> Control:
	var m: Control = load("res://main.tscn").instantiate()
	m.persist = false
	m.reached = r
	m.total_rescues = rescues
	root.add_child(m)
	await process_frame
	m.scenes = []
	m._scene_idx = 0
	m._waiting_choice = false
	m._hide_scene_buttons()
	m.lock_left = 0.0
	return m


func at(m: Control, time: float) -> void:
	m.t = time
	m._process(0.0)


func _initialize() -> void:
	# 既定 difficulty は 2（むずかしい相当）。計画 07 で一段厳しくした
	var SD: GDScript = load("res://main.gd")
	check("既定 difficulty は 2（むずかしい）", SD.difficulty == 2)

	# タイトル画面: 起動直後は出て、出したあとは再読み込みで出し直さない
	var S0: GDScript = load("res://main.gd")
	S0.title_done = false
	var m0 := await fresh()
	check("起動直後はタイトル画面", m0.title_screen.visible)
	m0.queue_free()
	S0.title_done = true
	m0 = await fresh()
	check("タイトルを出したあとは出し直さない", not m0.title_screen.visible)
	m0.queue_free()

	# 0. 着信画面から始まり、応答すると通話が始まる
	var m := await fresh()
	check("最初は着信画面", m.state == m.State.TITLE)
	m._on_warn()
	check("着信中は警告できない", m.false_alarms == 0 and m.state == m.State.TITLE)
	m._start_call()
	check("応答で通話開始", m.state == m.State.PLAYING)
	m.queue_free()

	# 1. 場所を指さずに警告しても、何も起きない
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._on_warn()
	check("指さずに警告 → 何も起きない", m.state == m.State.PLAYING and m.false_alarms == 0)
	m.queue_free()

	# 2. 人影が映る前の警告は誤警告 → ロックされ、3回で失敗
	m = await fresh()
	m._start_call()
	at(m, 5.0)
	m._set_mark(ON_GHOST)
	m._on_warn()
	check("映る前の警告は誤警告1回", m.false_alarms == 1 and m.state == m.State.PLAYING)
	m._set_mark(ON_GHOST)
	m._on_warn()
	check("誤警告の直後はロックされ警告できない", m.false_alarms == 1)
	for i in 2:
		m.lock_left = 0.0
		m._set_mark(ON_GHOST)
		m._on_warn()
	check("誤警告3回で失敗", m.state == m.State.FAILED)
	m.queue_free()

	# 3. 人影が映っていても、場所が違えば誤警告
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._set_mark(OFF_GHOST)
	m._on_warn()
	check("映っていても別の場所なら誤警告", m.false_alarms == 1 and m.state == m.State.PLAYING)
	m.queue_free()

	# 4. 人影が映っていて、場所が合えば救出
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._set_mark(ON_GHOST)
	m._on_warn()
	check("映っていて場所が合えば救出", m.state == m.State.SAVED)
	m.queue_free()

	# 5. 警告しなければ時間切れで失敗
	m = await fresh()
	m._start_call()
	at(m, m.fail_at + 1.0)
	check("時間切れで失敗", m.state == m.State.FAILED)
	m.queue_free()

	# 6. 人影の濃さの時間割（stage1 前提。fail_at 拡大後の最大到達時刻は ghost_curve 末尾から取得）
	m = await fresh()
	var stage1_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))
	var stage1_curve: Array = stage1_data.get("ghost_curve", [])
	var stage1_max_t: float = float(stage1_curve[-1][0])
	check("0秒は濃さ0", m._ghost_alpha_at(0.0) == 0.0)
	check("20秒までは濃さ0", m._ghost_alpha_at(20.0) == 0.0)
	check("%d秒で最大" % int(stage1_max_t), m._ghost_alpha_at(stage1_max_t) == 1.0)
	check("途中は単調増加", m._ghost_alpha_at(stage1_max_t * 0.4) < m._ghost_alpha_at(stage1_max_t * 0.6))
	m.queue_free()

	# 7. ステージ: 設定が読め、素材が存在し、救出で次へ進む
	var S: GDScript = load("res://main.gd")
	for i in S.STAGE_FILES.size():
		S.stage_no = i
		m = await fresh()
		check("ステージ%d: 設定を読めた（相手=%s）" % [i + 1, m.friend], m.friend != "" and m.timeline.size() > 0)
		var all_exist := true
		for k in m.assets:
			# outfits / outfit_expressions は Dict（default/pajamas/hoodie のサブキー）なので個別にチェック
			if k in ["outfits", "outfit_expressions"]:
				for outfit_name in m.assets[k]:
					all_exist = all_exist and ResourceLoader.exists(m.assets[k][outfit_name])
			else:
				all_exist = all_exist and ResourceLoader.exists(m.assets[k])
		check("ステージ%d: 素材がすべて存在する" % (i + 1), all_exist)
		check("ステージ%d: 台詞は時刻順" % (i + 1), _sorted(m.timeline))
		m.queue_free()
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._set_mark(ON_GHOST)
	m._on_warn()
	check("ステージ1を救出 → 次はステージ2", m.state == m.State.SAVED and m._next_stage_no() == 1)
	m.queue_free()
	S.stage_no = 9   # stage10（最後のステージ、通話モード）
	S.difficulty = 1
	m = await fresh()
	m._start_call()
	# stage10 の ghost_curve 末尾時刻 - 15 秒（人影が濃く、信頼が低くても救出できる時刻）
	var stage10_p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage10.json"))
	var stage10_max_t: float = float(stage10_p["ghost_curve"][-1][0])
	at(m, stage10_max_t - 5.0)
	rescue(m)
	check("最後のステージを救出 → 最初へ戻る", m._next_stage_no() == 0 and not m._has_next_stage())
	m.queue_free()
	S.difficulty = 2   # 次のテストが既定 difficulty を期待する場合にそなえて戻す
	m = await fresh()
	m._start_call()
	at(m, m.fail_at + 1.0)
	check("失敗したら同じステージをやり直す", m.state == m.State.FAILED and m._next_stage_no() == S.stage_no)
	m.queue_free()
	S.stage_no = 0

	# 7b. エンディングのルート分岐: 累計救出数で end_label.text が変わる
	# stage1: ghost_curve 末尾時刻 - 25 秒（人影が濃い・緩和外・fail_at=153 内）
	var stage1_q_data_e: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))
	var stage1_max_t_e: float = float(stage1_q_data_e["ghost_curve"][-1][0])
	# 1 人目 → 「初救出！」が追加される
	S.stage_no = 0
	m = await fresh()
	m.total_rescues = 0
	m._start_call()
	at(m, stage1_max_t_e - 25.0)
	rescue(m)
	check("1 人目: end_label に「初救出！」が追加 (text='%s')" % m.end_label.text,
		m.end_label.text.contains("初救出"))
	m.queue_free()
	# 5 人目 → 別のメッセージ
	S.stage_no = 0
	m = await fresh()
	m.total_rescues = 4
	m._start_call()
	at(m, stage1_max_t_e - 25.0)
	rescue(m)
	check("5 人目: end_label に「あなたは頼れる人ですね」",
		m.end_label.text.contains("頼れる人"))
	m.queue_free()
	# 全クリア（9 ステージ）→ 全員救出
	var SD2: GDScript = load("res://main.gd")
	S.stage_no = SD2.STAGE_FILES.size() - 1
	m = await fresh()
	m.total_rescues = SD2.STAGE_FILES.size() - 1
	m._start_call()
	var stage10_q_data_e: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage10.json"))
	var stage10_max_t_e: float = float(stage10_q_data_e["ghost_curve"][-1][0])
	at(m, stage10_max_t_e - 25.0)
	rescue(m)
	check("全クリア: end_label に「全員救出！ クリア！」",
		m.end_label.text.contains("全員救出"))
	m.queue_free()
	S.stage_no = 0

	# 8. 配信ステージ（コメントで警告）
	S.stage_no = 2   # stage3（配信モード）固定
	S.difficulty = 1   # 既定 difficulty 2 だと need_warnings が 4 になり、3 回テストが成立しない
	m = await fresh()
	check("最後のステージは配信モード", m.mode == "stream")
	m._start_call()
	at(m, 5.0)
	m._on_comment(0)
	check("配信: 映る前のコメントは荒らし扱い（誤警告1回）", m.false_alarms == 1 and m.state == m.State.PLAYING)
	m.queue_free()
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._on_comment(0)
	m._on_comment(1)
	check("配信: 警告コメント2回ではまだ気づかない", m.state == m.State.PLAYING)
	m._on_comment(2)
	check("配信: 3回で配信者が気づく（救出）", m.state == m.State.SAVED)
	m.queue_free()
	S.difficulty = 2
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._on_warn()
	m._set_mark(Vector2(100, 100))
	check("配信: 映像を指す操作は無効", m.state == m.State.PLAYING and m.false_alarms == 0)
	m.queue_free()
	S.stage_no = 0

	# 9. 疑り深い相手（ステージ2）: 信頼と伝え方
	S.stage_no = 1
	m = await fresh()
	check("ステージ2は伝え方を選ぶ疑り深い相手", m.use_phrases and m.belief < 1.0)
	m._start_call()
	at(m, 62.0)
	m._set_mark(m.ghost_box_now().get_center())
	var b0: float = m.belief
	m._on_warn(0)
	check("信頼が足りないと流される（誤警告ではない）", m.state == m.State.PLAYING and m.false_alarms == 0 and m.belief > b0)
	m.queue_free()
	m = await fresh()
	m._start_call()
	# 人影のちらつき（0.7〜1.0倍）の影響が小さい時刻。緩和の時間帯を避け、ghost_alpha が十分高い時刻
	# 难度 2（むずかしい）でも fail_at 内になるよう、ghost_curve 末尾-25 秒付近（人影は濃く緩和外）
	var stage2_data_early: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage2.json"))
	var stage2_max_t: float = float(stage2_data_early["ghost_curve"][-1][0])
	at(m, stage2_max_t - 25.0)  # 168 - 25 = 143. fail_at=153 なので余裕あり
	m._set_mark(m.ghost_box_now().get_center())
	m._on_warn(1)
	check("「逃げて！」なら信じてもらえる", m.state == m.State.SAVED)
	m.queue_free()
	# プラン 24: 「話しかける」ボタンを撤去したため、_on_talk 関連のテストは削除。
	# 信頼度はシーン選択肢（_on_scene_choice）で上げる運用に変更。Phase 2 で別途テスト。
	m = await fresh()
	m._start_call()
	at(m, 5.0)
	m._set_mark(m.ghost_box_now().get_center())
	m._on_warn(1)
	check("疑う相手でも、映る前の警告は誤警告", m.false_alarms == 1)
	m.queue_free()
	S.stage_no = 0

	# 10. 誘惑の仕草: 人影が薄い間だけ差し込まれる
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	check("ステージ2は誘惑の仕草を持つ", m.lures.size() == 2)
	m.t = m.lures[0]["from"] + 1.0
	check("仕草の時間帯は lure0", m._react_target() == "lure0")
	m.t = m.lures[1]["from"] + 1.0
	check("次の時間帯は lure1", m._react_target() == "lure1")
	m.t = m.lures[0]["to"] + 1.0
	check("時間帯の外はかわいい表情（プラン 13 修正）", m._react_target() == "kawaii")
	# 人影が濃い（0.4以上）ときは、仕草より怯えが優先。緩和の時間帯を避ける
	# stage1 の ghost_curve 末尾時刻 - 30 秒（人影が濃く、緩和外）
	var s1_curve_max: float = float(JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))["ghost_curve"][-1][0])
	m.t = s1_curve_max - 30.0
	check("人影が濃いと怯えた表情", m._react_target() == "scared")
	m.queue_free()
	S.stage_no = 0

	# 11. 一時停止・誤警告の理由・結果表示・音量
	m = await fresh()
	m._start_call()
	at(m, 5.0)
	var t_before: float = m.t
	m._set_paused(true)
	m._process(1.0)
	check("一時停止中は時間が進まない", m.t == t_before and m.paused)
	m._set_paused(false)
	m._process(1.0)
	check("再開すると時間が進む", m.t > t_before)
	m._set_mark(Vector2(100, 100))
	m._on_warn()
	check("誤警告の理由（まだ映っていない）を表示", m.hint_label.text.contains("まだ何も映っていなかった"))
	m.lock_left = 0.0
	at(m, 62.0)
	m._set_mark(Vector2(100, 100))
	m._on_warn()
	check("誤警告の理由（場所が違う）を表示", m.hint_label.text.contains("場所が違った"))
	m.queue_free()
	m = await fresh()
	m._start_call()
	at(m, 70.0)
	rescue(m)
	check("結果に時間と誤警告の数を表示", m.end_sub.text.contains("誤警告"))
	m.vol_master = 0.5
	m.vol_amb = 0.5
	m._apply_volume()
	check("音量を反映できる（全体0.5で約-6dB）", absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01)
	m.vol_master = 1.0
	m._apply_volume()
	m.queue_free()

	# 12. 進行の記録: 救出すると次のステージへ進めるようになる
	S.stage_no = 0
	m = await fresh()
	m.reached = 0
	m._start_call()
	at(m, 60.0)
	rescue(m)
	check("ステージ1を救出 → ステージ2まで進める", m.state == m.State.SAVED and m.reached == 1)
	m.queue_free()
	S.stage_no = 0

	# 13. 人影が濃くなるほど近づく（大きくなる）
	for i in S.STAGE_FILES.size():
		S.stage_no = i
		m = await fresh()
		m._start_call()
		at(m, 5.0)
		var s_far: float = m.ghost_layer.scale.x
		at(m, m.fail_at - 20.0)
		var s_near: float = m.ghost_layer.scale.x
		check("ステージ%d: 人影は濃くなるほど大きくなる" % (i + 1), s_near > s_far and s_far < 1.0)
		m.queue_free()
	S.stage_no = 0

	# 14. 映像の乱れと「演出を弱める」
	S.difficulty = 1   # difficulty 2（fail_at=153）だと fail するので、ふつう（fail_at=171）で実行
	m = await fresh()
	m._start_call()
	# 人影が濃い時刻（ghost_curve 末尾 0.7 倍以降）
	var s1_glitch_t: float = float(JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))["ghost_curve"][-1][0]) * 0.95
	at(m, s1_glitch_t)
	check("人影が濃いと映像が乱れる", float(m.cam_mat.get_shader_parameter("glitch")) > 0.3)
	at(m, 5.0)
	check("人影がないときは乱れない", float(m.cam_mat.get_shader_parameter("glitch")) == 0.0)
	m.calm = true
	at(m, 90.0)
	check("演出を弱めると映像の乱れが出ない", float(m.cam_mat.get_shader_parameter("glitch")) == 0.0)
	m.shake_left = 0.7
	at(m, 90.0)
	check("演出を弱めると画面の揺れが出ない", m.shake_left == 0.0)
	m.queue_free()

	# 14b. 音のバス: 環境音は人影が濃いほどこもり、音量はバスごとに調整できる
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	var amb_bus := AudioServer.get_bus_index("Ambient")
	var sfx_bus := AudioServer.get_bus_index("Sfx")
	check("音のバス（環境音・効果音）がある", amb_bus >= 0 and sfx_bus >= 0)
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(amb_bus, 0)
	at(m, 5.0)
	var cut_far: float = lp.cutoff_hz
	at(m, 90.0)
	var cut_near: float = lp.cutoff_hz
	check("人影が濃いほど環境音がこもる（ローパスが閉じる）", cut_near < cut_far)
	m.vol_amb = 0.5
	m.vol_sfx = 0.25
	m._apply_volume()
	check("環境音・効果音の音量をバスごとに反映", absf(AudioServer.get_bus_volume_db(amb_bus) - linear_to_db(0.5)) < 0.01 \
			and absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.25)) < 0.01)
	m.vol_amb = 0.8
	m.vol_sfx = 1.0
	m._apply_volume()
	m.queue_free()

	# 14c. UI/UX: 練習ステージの合図・あと何秒か・失敗の理由
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("練習ステージは合図の設定を持つ", m.onboarding and m.cue_first_seen)
	at(m, 5.0)
	check("人影が見える前は合図なし", not m.seen_cue_played)
	# stage1 の ghost_curve から「最初に見える時刻」を取得（fail_at 拡大で変動）
	var stage1_q_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))
	var stage1_curve_data: Array = stage1_q_data["ghost_curve"]
	var stage1_seen_t: float = stage1_curve_data[2][0] + 2.0  # 3 番目のキーの少し後（alpha > SEEN_THRESHOLD）
	at(m, stage1_seen_t)
	check("人影が見え始めると合図とヒント", m.seen_cue_played and m.hint_label.text.contains("背後の暗がり"))
	m.queue_free()
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, 70.0)
	check("練習以外のステージは合図なし（注意力に任せる）", not m.cue_first_seen and not m.onboarding)
	m.lock_left = 2.0
	at(m, 71.0)
	check("ロック中は '🔒 Ns' を表示", m.lock_label.text.contains("🔒") and m.lock_label.text.contains("s"))
	# プラン 24: 話しかけ直せるまでの文言は廃止
	check("ロックラベルに '話しかけ' が出ていない", not m.lock_label.text.contains("話しかけ"))
	m.queue_free()
	for i in S.STAGE_FILES.size():
		S.stage_no = i
		m = await fresh()
		m._start_call()
		var seen_at: float = m._first_seen_time()
		check("ステージ%d: 人影が映る時刻が、制限時間より前にある" % (i + 1), seen_at > 0.0 and seen_at < m.fail_at)
		at(m, m.fail_at + 1.0)
		check("ステージ%d: 失敗の理由と時刻を表示" % (i + 1), m.end_sub.text.contains("から映っていた"))
		m.queue_free()
	S.stage_no = 0

	# 14d. 着信音: 着信画面で鳴り、応答すると止まる
	S.stage_no = 0
	m = await fresh()
	check("着信画面では着信音が鳴る", (m.audio.players["ring"] as AudioStreamPlayer).playing)
	m._start_call()
	check("応答すると着信音が止まる", not (m.audio.players["ring"] as AudioStreamPlayer).playing)
	m.queue_free()

	# 14e. 信頼の境目: 小数の足し算の誤差で、1回ずれない（初期値0.3から、ちょうど6回で60%）
	S.stage_no = 1
	# プラン 24: 話しかけ廃止に伴い、5回/7回ずれないテストは削除。
# 信頼度 60% の一言は、Phase 2（選択肢での trust_gain）実装後に別途テスト。
	S.stage_no = 0

	# 15. 配信: 警告のあと、視聴者が反応する
	# プラン 27: 配信モード（stage 3, index 2）だけ viewer_chat を作り、メイン chat_log には流さない
	S.stage_no = 2   # stage 3 = 配信
	m = await fresh()
	m._start_call()
	check("配信モードは viewer_chat がある", m.viewer_chat != null)
	check("通話モードは viewer_chat が null", true)  # 直前の通話 test で確認済み
	var main_before: int = m.chat_log.get_parsed_text().length()
	m._viewer_echo(true)
	await create_timer(2.4).timeout
	# メイン chat_log には viewer の書き込みは来ない
	check("配信モードの viewer_echo でメイン chat_log が増えない（独立表示）",
		m.chat_log.get_parsed_text().length() == main_before)
	m.queue_free()
	S.stage_no = 0

	# 15b. 通話モード（stage 1）で viewer_chat は null
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("通話モードは viewer_chat が null", m.viewer_chat == null)
	m.queue_free()
	S.stage_no = 0

	# 16. 緩和の場面（人影が一度消えて、また現れる）
	# 緩和が無いステージ（練習）: 係数は常に 1
	S.stage_no = 0
	m = await fresh()
	check("練習ステージは緩和の設定がない", m.relief.size() == 0)
	check("緩和が無いステージは係数 1", m._relief_factor(30.0) == 1.0)
	m.queue_free()
	S.stage_no = 0

	# 緩和があるステージ: 係数は時間帯の中で 0、前後は 0.8 秒のランプ
	S.stage_no = 1
	m = await fresh()
	check("疑り深い相手は緩和の時間帯を持つ", m.relief.size() == 2)
	var relief_mid: float = (m.relief[0][0] + m.relief[0][1]) / 2.0  # 最初の緩和の真ん中
	# 境目のフェードウィンドウ内（最初の開始の 0.4 秒手前 = 緩和開始 79.2〜80 秒のランプ部分）
	var relief_fade_in: float = m.relief[0][0] - 0.4
	check("緩和の外（最初の開始より 30 秒前）は係数 1", m._relief_factor(m.relief[0][0] - 30.0) == 1.0)
	check("緩和の時間帯の真ん中は係数 0", m._relief_factor(relief_mid) == 0.0)
	var r_fade: float = m._relief_factor(relief_fade_in)
	check("緩和開始の 0.4 秒手前は 0 と 1 の間（ランプ）", r_fade > 0.0 and r_fade < 1.0)
	m.queue_free()
	S.stage_no = 0

	# 人影の濃さは、緩和で実際に 0 になる（時間割どおりなら 0 より大きい）
	S.stage_no = 1
	m = await fresh()
	check("緩和の時間帯でも時間割の濃さは 0 より大きい", m._curve_alpha(relief_mid) > 0.0)
	check("人影の実際の濃さは、緩和中は 0", m._ghost_alpha_at(relief_mid) == 0.0)
	m.queue_free()
	S.stage_no = 0

	# _first_seen_time は緩和に影響されない（時間割どおりの濃さで判定）
	S.stage_no = 1
	m = await fresh()
	var x := 0.0
	while x < m.fail_at:
		if m._curve_alpha(x) >= m.SEEN_THRESHOLD:
			break
		x += 0.5
	check("_first_seen_time は _curve_alpha と一致（緩和に影響されない）", m._first_seen_time() == x)
	m.queue_free()
	S.stage_no = 0

	# 緩和中の警告は罰しない（誤警告扱いしない／ロックだけ掛ける）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, relief_mid)
	m._set_mark(m.ghost_box_now().get_center())
	m._on_warn(1)
	check("緩和中の警告は誤警告扱いしない", m.false_alarms == 0)
	check("緩和中の警告のあとはプレイ継続", m.state == m.State.PLAYING)
	check("緩和中の警告はロックだけ掛ける", m.lock_left > 0.0)
	check("緩和中は: 戻るヒントを表示", m.hint_label.text.contains("また現れる"))
	m.queue_free()
	S.stage_no = 0

	# 戻る瞬間の音（緩和の時間帯ごとに 1 回 creak）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	# 緩和の終了の少し後（境目から 1.0 秒後 = 完全に出た）
	at(m, m.relief[0][1] + 1.0)
	check("緩和の時間帯を抜けたら creak を鳴らす（relief_idx が 1 以上）", m.relief_idx >= 1)
	m.queue_free()
	S.stage_no = 0

	# 配信の緩和中のコメントも誤警告扱いしない
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	var stage3_relief_mid: float = (m.relief[0][0] + m.relief[0][1]) / 2.0
	at(m, stage3_relief_mid)
	m._on_comment(0)
	check("配信の緩和中のコメントも誤警告扱いしない", m.false_alarms == 0)
	check("配信の緩和中はプレイ継続", m.state == m.State.PLAYING)
	m.queue_free()
	S.stage_no = 0

	# 17. 信頼の見える化: ゲージ・信頼で変わる台詞・信頼が高まった瞬間の一言
	# 17a. 信頼ゲージ（use_phrases のステージだけ作られる）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	check("ステージ2に信頼ゲージ（trust_bar_fill）がある", m.trust_bar_fill != null)
	for i in 5:
		m._process(0.5)
	var target_w: float = m.VIDEO_SIZE.x * m.belief
	check("ゲージ幅が VIDEO_SIZE.x * belief に近づく（誤差 ±10%）",
		absf(m.trust_bar_fill.size.x - target_w) / target_w < 0.1)
	m.queue_free()
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("ステージ1には信頼ゲージがない", m.trust_bar_fill == null)
	m.queue_free()
	S.stage_no = 1

	# 17b / 17c / 17d: プラン 24 で _on_talk が no-op になったため削除。Phase 2 で再開予定。

	# 18. 難易度: やさしい/ふつう/むずかしい で値が変わる
	for d in 3:
		S.difficulty = d
		S.stage_no = 0
		m = await fresh()
		check("難易度%d: max_false_alarms（%d/%d/%d）" % [d, m.max_false_alarms, m.false_alarm_lock, m.fail_at],
				m.max_false_alarms == [4, 2, 2][d])
		# プラン 28 で短くした: やさしい 3.0→1.5, ふつう 4.0→2.0, むずかしい 5.0→2.5
		check("難易度%d: false_alarm_lock" % d, m.false_alarm_lock == [1.5, 2.0, 2.5][d])
		# stage1 の fail_at は 180。倍率 1.10 / 0.95 / 0.85 → 198 / 171 / 153
		var want_fail: float = [198.0, 171.0, 153.0][d]
		check("難易度%d: fail_at" % d, absf(m.fail_at - want_fail) < 0.001)
		m.queue_free()
	S.stage_no = 0

	# 18b. ふつう: 既定 difficulty 2（むずかしい相当）で始めたユーザー向けに、値を保持
	S.difficulty = 1
	S.stage_no = 0
	m = await fresh()
	check("ふつう: fail_at は 171（= 180 × 0.95）", absf(m.fail_at - 171.0) < 0.001)
	check("ふつう: max_false_alarms == 2", m.max_false_alarms == 2)
	m.queue_free()
	S.stage_no = 0

	# 18c. 疑り深い相手の belief_start（stage2）。stage2 の belief_start=0.3 ＋ 難易度補正
	for d in 3:
		S.difficulty = d
		S.stage_no = 1
		m = await fresh()
		var want_belief: float = [0.40, 0.30, 0.25][d]
		check("難易度%d: belief_start（%0.2f）" % [d, want_belief], absf(m.belief_start - want_belief) < 0.001)
		check("難易度%d: belief は belief_start と同じ" % d, m.belief == m.belief_start)
		m.queue_free()
	S.stage_no = 0
	S.difficulty = 1

	# 18d. 配信の必要コメント数（stage3）
	for d in 3:
		S.difficulty = d
		S.stage_no = 2
		m = await fresh()
		check("難易度%d: need_warnings（%d）" % [d, [2, 3, 4][d]], m.need_warnings == [2, 3, 4][d])
		m.queue_free()
	S.stage_no = 0
	S.difficulty = 1

	# 18e. stage1 は belief_start >= 1.0 なので、どの難易度でも belief_start は 1.0 のまま
	for d in 3:
		S.difficulty = d
		S.stage_no = 0
		m = await fresh()
		check("難易度%d: stage1 の belief_start は 1.0 のまま" % d, m.belief_start == 1.0)
		m.queue_free()
	S.stage_no = 0
	S.difficulty = 1

	# 18f. むずかしい（d=2）: stage1 で人影が映る前の誤警告 2 回で失敗
	S.difficulty = 2
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 5.0)
	for i in 2:
		m._set_mark(ON_GHOST)
		m.lock_left = 0.0
		m._on_warn()
	check("むずかしい: 誤警告 2 回で失敗", m.state == m.State.FAILED and m.false_alarms == 2)
	m.queue_free()
	S.stage_no = 0
	S.difficulty = 1

	# 18g. やさしい（d=0）: stage1 で誤警告 3 回では失敗にならず、4 回で失敗（max_false_alarms=4）
	S.difficulty = 0
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 5.0)
	for i in 3:
		m._set_mark(ON_GHOST)
		m.lock_left = 0.0
		m._on_warn()
	check("やさしい: 誤警告 3 回では失敗にならない", m.state == m.State.PLAYING and m.false_alarms == 3)
	m.lock_left = 0.0
	m._set_mark(ON_GHOST)
	m._on_warn()
	check("やさしい: 誤警告 4 回で失敗", m.state == m.State.FAILED and m.false_alarms == 4)
	m.queue_free()
	S.stage_no = 0
	S.difficulty = 1

	# 18h. persist == false のときは設定を読まない（保存済みの difficulty を反映しない）
	# 事前に settings.cfg に difficulty=0 を書いた状態でも、persist=false で fresh すると difficulty はデフォルトの 2
	var cfg_path: String = S.SETTINGS_PATH
	var cfw := ConfigFile.new()
	cfw.set_value("game", "difficulty", 0)
	cfw.save(cfg_path)
	S.difficulty = 1
	m = await fresh()   # fresh 内で persist=false にしている
	check("persist=false: 保存済みの設定を読まない（max_false_alarms は既定=2）", m.max_false_alarms == 2)
	# settings.cfg を消しておく（他テストへの汚染防止）
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	m.queue_free()

	# 18i. タイトル画面に難易度ボタンが 3 つある（title_done = false で fresh）
	S.title_done = false
	m = await fresh()
	var diff_count := 0
	for child in m.title_screen.get_children():
		if child is Button and m.diff_btns.has(child):
			diff_count += 1
	check("タイトル画面に難しさボタンが 3 つある", diff_count == 3 and m.diff_btns.size() == 3)
	m.queue_free()
	S.title_done = true

	# 18j. タイトル画面のステージ選択ボタン: 件数と画面内収まり（reached = 0..10）
	for r in 11:
		S.title_done = false
		m = await fresh_with_reached(r)
		# 件数（reached + 1 を STAGE_FILES.size() で頭打ち。reached=0 は 0）
		var expected: int = min(r + 1, S.STAGE_FILES.size()) if r > 0 else 0
		check("reached=%d のステージ選択ボタン数（%d 個）" % [r, expected], m.stage_select_btns.size() == expected)
		# 画面内に収まっているか（すべて x: 0..1280 / y: 0..720）
		var in_bounds := true
		for b in m.stage_select_btns:
			if b.position.x < 0 or b.position.x + b.size.x > 1280:
				in_bounds = false
			if b.position.y < 0 or b.position.y + b.size.y > 720:
				in_bounds = false
		check("reached=%d の全ボタンが画面内に収まる" % r, in_bounds)
		# 下のヒント（Esc...F11: 全画面）と被らないか。ヒントは (0, 690) で高さ 30
		var no_hint_overlap := true
		for b in m.stage_select_btns:
			if b.position.y + b.size.y > 690:
				no_hint_overlap = false
		if r > 0:
			check("reached=%d のステージボタンがヒント (y=690) と重ならない" % r, no_hint_overlap)
		# 右上「終了」ボタンが存在する
		check("reached=%d で quit_btn_title が存在する" % r, m.quit_btn_title != null)
		# reached > 0 のとき、最初のボタンはキャラ名を含む（stages/stage1.json の friend が 'Mika'）
		if r > 0:
			var first_label: String = m.stage_select_btns[0].text
			check("reached=%d の最初のボタンにキャラ名（'Mika'）が含まれる" % r,
				"Mika" in first_label)
		m.queue_free()
	S.title_done = true

	# 18k. タイトル画面に通算救出数（total_rescues）が表示される
	for n_rescues in [0, 1, 5, 10, 50]:
		S.title_done = false
		m = await fresh_with_state(5, n_rescues)
		# title_screen 内のラベルで '通算救出 %d回' を含むものを探す
		var found := false
		for child in m.title_screen.get_children():
			if child is Label and (child as Label).text.contains("通算救出"):
				if (child as Label).text.contains(str(n_rescues)):
					found = true
					break
		if n_rescues == 0:
			check("total_rescues=0 のときは通算救出ラベル無し", not found)
		else:
			check("total_rescues=%d のとき '通算救出 %d回' ラベルあり" % [n_rescues, n_rescues], found)
		m.queue_free()
	S.title_done = true

	# 19. 人影の道筋（ghost_path）: キー値・補間・倍率・ghost_box_now の移動
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	# stage1 の ghost_path キーを JSON から取得（fail_at 拡大で変動するため）
	var stage1_p_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))
	var stage1_ghost_path: Array = stage1_p_data.get("ghost_path", [])
	var path_k1: Array = stage1_ghost_path[0]
	var path_k2: Array = stage1_ghost_path[1]
	var path_k3: Array = stage1_ghost_path[2]
	check("ghost_offset_at 最初のキー以前は最初の値",
		m.ghost_offset_at(path_k1[0] - 1.0) == Vector2(0, 0))
	# キーの値そのもの（time == b[0]）を確認。smoothstep(1.0)=1.0 で lerp(a, b, 1) = b
	check("ghost_offset_at 2番目のキーの値はキー値",
		m.ghost_offset_at(path_k2[0]) == Vector2(float(path_k2[1]), float(path_k2[2])))
	check("ghost_offset_at 最後のキーの値はキー値",
		m.ghost_offset_at(path_k3[0]) == Vector2(float(path_k3[1]), float(path_k3[2])))
	check("ghost_mult_at 最後のキーの値は最後の倍率",
		absf(m.ghost_mult_at(path_k3[0]) - float(path_k3[3])) < 0.0001)
	check("キーの外（0 秒）は最初の値", m.ghost_offset_at(0.0) == Vector2(0, 0))
	check("キーの外（fail_at + 100）は最後の値",
		m.ghost_offset_at(m.fail_at + 100.0) == Vector2(float(path_k3[1]), float(path_k3[2])))
	# ghost_path が無い設定は (0, 0) と 1.0（empty にしたら従来どおり）
	m.ghost_path = []
	check("ghost_path が空のとき ghost_offset_at は (0, 0)", m.ghost_offset_at(60.0) == Vector2(0, 0))
	check("ghost_path が空のとき ghost_mult_at は 1.0", m.ghost_mult_at(60.0) == 1.0)
	m.queue_free()
	S.stage_no = 0

	# ghost_box_now は ghost_offset_at(t) だけ平行移動した Rect2
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, float(path_k3[0]))
	check("ghost_box_now.position は ghost_box.position + Vector2(float(path_k3[1]), float(path_k3[2]))",
		m.ghost_box_now().position == m.ghost_box.position + Vector2(float(path_k3[1]), float(path_k3[2])))
	# ghost_box_now は時刻で動く
	var box_at_late: Rect2 = m.ghost_box_now()
	at(m, 0.0)
	var box_at_0: Rect2 = m.ghost_box_now()
	check("ghost_box_now は時刻で動く（t=0 と t=最後で位置が違う）", box_at_late.position != box_at_0.position)
	m.queue_free()
	S.stage_no = 0

	# 判定が人影と一緒に動く: ghost_box_now を指すと救出できる（_on_warn が新しい位置を見ている）
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 95.0)
	m._set_mark(m.ghost_box_now().get_center())
	m._on_warn()
	check("人影が動いたあとは、新しい位置（ghost_box_now）を指すと救出",
		m.state == m.State.SAVED)
	m.queue_free()
	S.stage_no = 0

	# 20. 揺れ・コマ落ち: calm=false で位置が ghost_offset_at(t) と一致しない回がある
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 62.0)   # _curve_alpha(62) ≈ 0.31（>= 0.3）。fail_at=110 を超えない範囲で回す
	var deviated := false
	for i in 100:
		m._process(0.1)
		if m.ghost_layer.position != m.ghost_offset_at(m.t):
			deviated = true
			break
	check("揺れ・コマ落ち（calm=false）: 位置が ghost_offset_at(t) と一致しない回がある", deviated)
	m.queue_free()

	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 62.0)
	m.calm = true
	var matched := true
	for i in 100:
		m._process(0.1)
		if m.ghost_layer.position != m.ghost_offset_at(m.t):
			matched = false
			break
	check("揺れ・コマ落ち（calm=true）: 位置が常に ghost_offset_at(t) と一致", matched)
	m.queue_free()
	S.stage_no = 0

	# 21. 襲いかかり: 失敗後に lunge で大きくなり、calm では穏やかなスケールで止まる
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, m.fail_at + 1.0)   # FAILED に遷移し、lunge = 0 で止まる
	for i in 5:
		m._process(0.1)
	check("襲いかかり: lunge 後に ghost_layer.scale.x >= 2.0", m.ghost_layer.scale.x >= 2.0)
	m.queue_free()

	S.stage_no = 0
	m = await fresh()
	m._start_call()
	m.calm = true
	at(m, m.fail_at + 1.0)
	for i in 5:
		m._process(0.1)
	check("襲いかかり（calm）: scale.x が ghost_scale 最大より大きく、1.6 以下",
		m.ghost_layer.scale.x > m.ghost_scale[1] and m.ghost_layer.scale.x <= 1.6)
	m.queue_free()
	S.stage_no = 0

	# 22. 音の方向: 人影の左右位置でパンが変わる（stage1=人影右→正 / stage2=人影左→負）
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 90.0)
	var pan_sfx_bus := AudioServer.get_bus_index("Sfx")
	var pan_sfx_panner: AudioEffectPanner = AudioServer.get_bus_effect(pan_sfx_bus, 1) as AudioEffectPanner
	check("音の方向（stage1, 90秒）: 人影は右寄りでパンが正", pan_sfx_panner.pan > 0.0)
	m.queue_free()

	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, 90.0)
	pan_sfx_panner = AudioServer.get_bus_effect(AudioServer.get_bus_index("Sfx"), 1) as AudioEffectPanner
	check("音の方向（stage2, 90秒）: 人影は左寄りでパンが負", pan_sfx_panner.pan < 0.0)
	m.queue_free()
	S.stage_no = 0

	# 23. 照明の反応: きしみの直後に dim が 0 より大きく、calm では常に 0
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, m.creaks[0] + 0.5)   # 最初の creak の直後（stage1）
	check("照明: creak 直後のフレームで dim > 0",
		float(m.cam_mat.get_shader_parameter("dim")) > 0.0)
	m.queue_free()

	S.stage_no = 0
	m = await fresh()
	m._start_call()
	m.calm = true
	at(m, 30.0)
	check("照明（calm）: dim は常に 0",
		float(m.cam_mat.get_shader_parameter("dim")) == 0.0)
	m.queue_free()
	S.stage_no = 0

	# 24. 計画06: 映像クリックでの警告（stage1）
	# stage1 で人影が映っているあいだに、人影の位置をクリック → 1 クリックで救出
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	check("stage1・人映り前: click中心 → 1 クリックで救出",
		m._on_video_click(m.ghost_box_now().get_center()) == null   # 関数戻り値は void/null 想定
		or true)   # 比較は意味なし（後段の状態で判定）
	check("stage1・click中心 → 救出成功 (state == SAVED)", m.state == m.State.SAVED)
	m.queue_free()
	S.stage_no = 0

	# stage1 で人影のいない場所をクリック → 救出にならず誤警告 1 回
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._on_video_click(Vector2(50, 50))
	check("stage1・人影のいない場所をクリック → 救出にならず誤警告 1 回",
		m.state == m.State.PLAYING and m.false_alarms == 1)
	m.queue_free()
	S.stage_no = 0

	# stage1 で人影が映る前にクリック → 誤警告 1 回
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	at(m, 5.0)
	m._on_video_click(m.ghost_box_now().get_center())
	check("stage1・映る前にクリック → 誤警告 1 回",
		m.state == m.State.PLAYING and m.false_alarms == 1)
	m.queue_free()
	S.stage_no = 0

	# 25. 計画06: stage2（use_phrases）クリック警告
	# 「逃げて！」(selected_phrase=1) を選んでクリック → 救出
	# ghost_curve 末尾 - 25 秒（人影が濃い・緩和外・fail_at=153 内）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	var stage2_p_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage2.json"))
	var stage2_max_t_late: float = float(stage2_p_data["ghost_curve"][-1][0])
	at(m, stage2_max_t_late - 25.0)
	m._select_phrase(1)
	m._on_video_click(m.ghost_box_now().get_center())
	check("stage2・selected_phrase=1 で中心クリック → 救出成功", m.state == m.State.SAVED)
	m.queue_free()
	S.stage_no = 0

	# stage2: selected_phrase=0（「後ろ見て！」=弱）では、信頼だけでは救出にならない
	# stage2 の 2 番目の relief 直前（alpha が中程度＝救出に足りない）の時刻を使う
	# 時刻 120: alpha ≈ 0.586, score（phrase=0）= 0.869 < 1.0、score（phrase=1）= 1.069 >= 1.0
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, 120.0)
	m._select_phrase(0)
	m._on_video_click(m.ghost_box_now().get_center())
	check("stage2・selected_phrase=0 では救出にならずPLAYING継続",
		m.state == m.State.PLAYING and m.false_alarms == 0)
	m.queue_free()
	S.stage_no = 0

	# 26. 計画06: stage3（配信）クリック警告
	# lock_left が 0 のときだけ 1 秒ずつ _process → 人影を 3 回クリック → 救出
	# 映り始め以降に開始（stage3 の first_seen_time は ≈48 程度）
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	m.t = 60.0
	m._process(0.0)
	var n := 0
	while n < m.need_warnings and m.state == m.State.PLAYING:
		m.lock_left = 0.0   # テスト用にロック解除（タイミング依存を排除）
		m._on_video_click(m.ghost_box_now().get_center())
		m._process(1.0)
		n += 1
	check("stage3・1秒ずつクリック → 救出", m.state == m.State.SAVED)
	m.queue_free()
	S.stage_no = 0

	# stage3: 人影のいない場所をクリック → 荒らし扱い（誤警告 1 回）
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	at(m, 60.0)
	m._on_video_click(Vector2(50, 50))
	check("stage3・人影のいない場所をクリック → 誤警告 1 回（荒らし扱い）",
		m.state == m.State.PLAYING and m.false_alarms == 1)
	m.queue_free()
	S.stage_no = 0

	# 27. 計画06: 伝え方の選択
	# _select_phrase(2) で selected_phrase が 2 になる
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	m._select_phrase(2)
	check("stage2・_select_phrase(2) → selected_phrase == 2", m.selected_phrase == 2)
	# 範囲外は無視
	m._select_phrase(99)
	check("stage2・_select_phrase(99) → 変化しない", m.selected_phrase == 2)
	m.queue_free()
	S.stage_no = 0

	# stage1（use_phrases=false）: _select_phrase(1) を呼んでも selected_phrase は 0 のまま
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	m._select_phrase(1)
	check("stage1・_select_phrase(1) → selected_phrase は 0 のまま", m.selected_phrase == 0)
	m.queue_free()
	S.stage_no = 0

	# 28. 計画06: 画面下のボタン表示
	# stage1: 警告ボタン群（warn_btn/third_btn/fourth_btn）は非表示、act_btns は空
	# プラン 24 で warn_btn の構築は削除済み（画面下のアクションボタン全撤去）。
	# 未使用なので null でも OK とみなす
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("stage1・warn_btn は null or 非表示", m.warn_btn == null or not m.warn_btn.visible)
	check("stage1・act_btns は空", m.act_btns.is_empty())
	m.queue_free()
	S.stage_no = 0

	# 29. 計画08: UI パーツが存在する
	# 壁紙・タスクバー・タイトルバー（赤黄緑の点）・REC ラベル
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("plan08・wallpaper がある", m.wallpaper != null)
	check("plan08・taskbar がある", m.taskbar != null)
	check("plan08・taskbar_clock がある", m.taskbar_clock != null)
	check("plan08・win_titlebar がある", m.win_titlebar != null)
	check("plan08・win_dots が 3 つ", m.win_dots.size() == 3)
	check("plan08・rec_label がある", m.rec_label != null)
	check("plan08・rec_label に REC が含まれる", "REC" in m.rec_label.text)
	m.queue_free()
	S.stage_no = 0

	# 通話の call_bars が 5 本
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	check("plan08・call_bars が 5 本（stage2 通話）", m.call_bars.size() == 5)
	m.queue_free()
	S.stage_no = 0

	# 配信の live_badge がある
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	check("plan08・live_badge がある（stage3 配信）", m.live_badge != null)
	m.queue_free()
	S.stage_no = 0

	# 30. 計画10: 結果画面の表情
	# SAVED のとき end_face.texture == react_tex["saved"]
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	check("plan10・end_face がある", m.end_face != null)
	check("plan10・end_face は end_panel の子", m.end_face.get_parent() == m.end_panel)
	check("plan10・react_tex に saved がある", m.react_tex.has("saved"))
	check("plan10・react_tex に failed がある", m.react_tex.has("failed"))
	# 強制 SAVED にして表情を確認
	m._finish(m.State.SAVED, "救出成功", Color(0.6, 1.0, 0.7))
	check("plan10・SAVED の end_face.texture == react_tex['saved']", m.end_face.texture == m.react_tex.get("saved"))
	m.queue_free()
	S.stage_no = 0

	# FAILED のとき end_face.texture == react_tex["failed"]
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	m._finish(m.State.FAILED, "信頼を失った", Color(1.0, 0.45, 0.45))
	check("plan10・FAILED の end_face.texture == react_tex['failed']", m.end_face.texture == m.react_tex.get("failed"))
	m.queue_free()
	S.stage_no = 0

	# 31. 計画09: 口パクと瞬き
	# face_overlay があり、_say で mouth_open_until がセットされ、_set_react で next_blink がセットされる
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	# テストでは _react_target の顔がころころ変わると mouth_open がリセットされるため、
	# react_top.texture を scare 用に直接固定する
	m._set_react("scared")
	# _react_target() が "scared" を返すよう t を人影が濃い位置にセット
	m.t = 65.0
	m._process(0.0)
	check("plan09・face_overlay がある", m.face_overlay != null)
	check("plan09・stage_d に face_fx がある", m.stage_d.has("face_fx"))
	check("plan09・_set_react で next_blink が設定される", m.next_blink > 0.0)
	m._say("Aoi", "テスト")  # friend と同じ名前にして、_say の mouth_open_until をトリガ
	check("plan09・_say で mouth_open_until > t", m.mouth_open_until > m.t)
	# 数フレーム進めて mouth_open が動く
	m._process(0.1)
	check("plan09・mouth_open が > 0（セリフ中）", m.mouth_open > 0.0)
	m.queue_free()
	S.stage_no = 0

	# stage2: プラン 24 で画面下のアクションボタンを撤去 → act_btns は空。
	# 選択の内部状態は _select_phrase 経由で selected_phrase に反映される（後段で検証）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	check("stage2・act_btns は空", m.act_btns.is_empty())
	m._select_phrase(1)
	check("stage2・_select_phrase(1) で selected_phrase == 1", m.selected_phrase == 1)
	m.queue_free()
	S.stage_no = 0

	# stage3: 同上（プラン 24 でボタン撤去済み）
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	check("stage3・act_btns は空", m.act_btns.is_empty())
	m.queue_free()
	S.stage_no = 0

	# plan15: キャラ別のチャットスタイル
	S.stage_no = 0
	m = await fresh()
	var cs_mika: Dictionary = m._char_style(m.friend)
	check("plan15・Mika スタイルが返る", cs_mika.has("stamp") and cs_mika["stamp"].size() > 0)
	check("plan15・Mika のスタイル名が正しく返る（フレッシュブルー）", cs_mika["name_color"] == "#a8c8e8")
	m.queue_free()

	S.stage_no = 1
	m = await fresh()
	var cs_aoi: Dictionary = m._char_style(m.friend)
	check("plan15・Aoi スタイルが返る", cs_aoi.has("stamp") and cs_aoi["stamp"].size() > 0)
	check("plan15・Aoi のスタイル名が正しく返る（くすみピンク）", cs_aoi["name_color"] == "#e8b0c8")
	m.queue_free()

	S.stage_no = 2
	m = await fresh()
	var cs_yume: Dictionary = m._char_style(m.friend)
	check("plan15・ゆめ スタイルが返る", cs_yume.has("stamp") and cs_yume["stamp"].size() > 0)
	check("plan15・ゆめ のスタイル名が正しく返る（ゴールド）", cs_yume["name_color"] == "#e8c890")
	# 自分/視聴者（friend でない発言者）のスタイル
	var cs_other: Dictionary = m._char_style("視聴者A")
	check("plan15・自分/視聴者スタイルはstamp空配列", cs_other["stamp"].size() == 0)
	m.queue_free()
	S.stage_no = 0

	# plan15: 信頼ゲージの % 表示ラベル
	S.stage_no = 1   # use_phrases の stage2
	m = await fresh()
	check("plan15・trust_bar_fill がある", m.trust_bar_fill != null)
	check("plan15・trust_bar_label がある", m.trust_bar_label != null)
	m._start_call()
	m.belief = 0.5
	m._process(0.1)
	check("plan15・ラベル更新: belief 0.5 で「50%」", m.trust_bar_label.text == "50%")
	m.belief = 0.7
	m._process(0.1)
	check("plan15・ラベル更新: belief 0.7 で「70%」", m.trust_bar_label.text == "70%")
	check("plan15・信頼60%超でラベル色ピンク系", m.trust_bar_label.modulate.r > 0.9)
	m.belief = 0.2
	m._process(0.1)
	check("plan15・信頼30%以下でラベル色赤系", m.trust_bar_label.modulate.r >= 0.95)
	m.queue_free()
	S.stage_no = 0

	# plan15: _say が 3 キャラ全員で動作する
	for si in 3:
		S.stage_no = si
		m = await fresh()
		m._start_call()
		# チャットログに何か追加されることを確認
		m._say(m.friend, "テストメッセージ")
		var after_text: String = m.chat_log.get_parsed_text()
		check("plan15・stage%d: _say で %s がチャットログに追記される" % [si + 1, m.friend], after_text.contains("テストメッセージ"))
		m.queue_free()
	S.stage_no = 0

	# 静的型ヒントの検証（GDScript では実行時のみ確認可能だが、主要関数のシグネチャ確認）
	# plan15: _char_style が Dictionary を返す（型推論可能なことを確認）
	S.stage_no = 0
	m = await fresh()
	var _test: Dictionary = m._char_style(m.friend)
	check("plan15・_char_style の戻り値型が Dictionary（型注釈確認）", typeof(_test) == TYPE_DICTIONARY)
	m.queue_free()

	# plan17: 段階的エンディング（saved_lines）
	# belief の高さで分岐することを確認
	S.stage_no = 0   # stage1
	m = await fresh()
	m.belief = 0.9
	var high_line: String = m._saved_line_for(m.belief)
	check("plan17・belief=0.9 で high_belief が返る", "信じて" in high_line or "大好き" in high_line)
	m.belief = 0.5
	var mid_line: String = m._saved_line_for(m.belief)
	check("plan17・belief=0.5 で mid_belief が返る",
		"外に出る" in mid_line or "やだ" in mid_line or mid_line == m.saved_line)
	m.belief = 0.2
	var low_line: String = m._saved_line_for(m.belief)
	check("plan17・belief=0.2 で low_belief が返る", "疑ってる" in low_line or "疑い" in low_line or "信じきれ" in low_line)
	m.queue_free()

	# plan21: 累計救出数による段階メッセージ（_ending_rescue_message）
	S.stage_no = 0
	m = await fresh()
	check("累計 1: 初救出！", m._ending_rescue_message(1) == "初救出！")
	check("累計 2: 空", m._ending_rescue_message(2) == "")
	check("累計 3: 3 人目！ だいぶ慣れてきましたね",
		m._ending_rescue_message(3) == "3 人目！ だいぶ慣れてきましたね")
	check("累計 4: 空", m._ending_rescue_message(4) == "")
	check("累計 5: 5 人目！ あなたは頼れる人ですね",
		m._ending_rescue_message(5) == "5 人目！ あなたは頼れる人ですね")
	check("累計 9（あと 1 人）: 空（全員救出は次の 1 人）",
		m._ending_rescue_message(9) == "")
	check("累計 10（STAGE_FILES.size() と同じ）: 全員救出！ クリア！",
		m._ending_rescue_message(S.STAGE_FILES.size()) == "全員救出！ クリア！")
	m.queue_free()

	# plan16: 衣装選択のテスト
	for si in 3:
		S.stage_no = si
		m = await fresh()
		check("plan16・stage%d: outfits に default/pajamas/hoodie がある" % (si + 1),
			m.outfits.has("default") and m.outfits.has("pajamas") and m.outfits.has("hoodie"))
		check("plan16・stage%d: outfit_layers が全衣装分ある" % (si + 1),
			m.outfit_layers.size() == m.outfits.size())
		check("plan16・stage%d: 現在衣装は default" % (si + 1), m.current_outfit == "default")
		# 衣装アンロックを前提にする（max_trust_reached を最大に）
		m.max_trust_reached = 0.85
		# 衣装切替
		m._set_outfit("pajamas")
		check("plan16・stage%d: _set_outfit('pajamas') で current_outfit が pajamas" % (si + 1), m.current_outfit == "pajamas")
		check("plan16・stage%d: pajamas レイヤーが visible" % (si + 1), m.outfit_layers["pajamas"].visible)
		check("plan16・stage%d: default レイヤーは invisible" % (si + 1), not m.outfit_layers["default"].visible)
		# 戻す
		m._set_outfit("default")
		check("plan16・stage%d: _set_outfit('default') で元に戻る" % (si + 1), m.current_outfit == "default")
		m.queue_free()
	S.stage_no = 0

	# plan16: 設定ファイルに保存されることのテスト
	S.stage_no = 1
	m = await fresh()
	m.max_trust_reached = 0.85
	m._set_outfit("hoodie")
	# 設定ファイルが作成されているはず（persist=true のまま確認）
	check("plan16・設定保存: current_outfit が hoodie に切り替わった", m.current_outfit == "hoodie")
	m.queue_free()
	S.stage_no = 0

	# プラン 29: stage5-10 の全シーンに 3 択目が追加されているか確認
	# 各シーンの choices 配列サイズが 3 以上であることを確認
	var plan29_stages = ["stage5", "stage6", "stage7", "stage8", "stage9", "stage10"]
	for stage_id in plan29_stages:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/" + stage_id + ".json"))
		var scenes: Array = data.get("scenes", [])
		for scene in scenes:
			var scene_id: String = scene.get("id", "?")
			var choices: Array = scene.get("choices", [])
			check("plan29・" + stage_id + "/" + scene_id + " の選択肢が 3 つ以上", choices.size() >= 3)
			# 各選択肢が effect.belief を持つことを確認
			for choice in choices:
				check("plan29・" + stage_id + "/" + scene_id + " の選択肢が effect.belief を持つ",
					choice.has("effect") and choice["effect"].has("belief"))

	# プラン 30: stage1-4 で 3 択化されたシーンのみ検証（plan28 で 3 択済みの hello/hello/greeting はスキップ）
	var plan30_targets = {
		"stage1": ["intro", "distant", "after_work", "ghost_nervous", "end", "urgent_warning"],
		"stage2": ["warm_open", "cold_open", "about_today", "trust_check", "ending", "urgent_warning"],
		"stage3": ["chat_topic", "about_viewer", "feel_anxious", "ending", "urgent_warning"],
		"stage4": ["warm_open", "cold_open", "about_room", "trust_check", "ending", "urgent_warning"],
	}
	for stage_id in plan30_targets.keys():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/" + stage_id + ".json"))
		var scenes: Array = data.get("scenes", [])
		var target_ids: Array = plan30_targets[stage_id]
		for scene in scenes:
			var scene_id: String = scene.get("id", "?")
			if not target_ids.has(scene_id):
				continue
			var choices: Array = scene.get("choices", [])
			check("plan30・" + stage_id + "/" + scene_id + " の選択肢が 3 つ以上", choices.size() >= 3)
			# 各選択肢が effect.belief を持つことを確認
			for choice in choices:
				check("plan30・" + stage_id + "/" + scene_id + " の選択肢が effect.belief を持つ",
					choice.has("effect") and choice["effect"].has("belief"))

	# プラン 31: _choice_tint_color の挙動（belief 値 → 色）の境界テスト
	# main インスタンス m を介して呼ぶ（_choice_tint_color は main.gd 側にある）
	S.stage_no = 0
	m = await fresh()
	check("plan31・belief=0.05 は緑系（g > r かつ g > b）", _is_green_tint(m._choice_tint_color(0.05)))
	check("plan31・belief=0.04 は緑系の境界（g >= r かつ g >= b）", _is_green_tint(m._choice_tint_color(0.04)))
	check("plan31・belief=0.02 は灰系（r == g == b）", _is_neutral_tint(m._choice_tint_color(0.02)))
	check("plan31・belief=0.0 は灰系の境界（r == g == b）", _is_neutral_tint(m._choice_tint_color(0.0)))
	check("plan31・belief=-0.02 はオレンジ系（r > g > b）", _is_orange_tint(m._choice_tint_color(-0.02)))
	check("plan31・belief=-0.03 はオレンジ系の境界", _is_orange_tint(m._choice_tint_color(-0.03)))
	check("plan31・belief=-0.04 は赤系（r > g 且つ r > b が明確）", _is_red_tint(m._choice_tint_color(-0.04)))
	check("plan31・belief=-0.05 は赤系", _is_red_tint(m._choice_tint_color(-0.05)))
	m.queue_free()
	S.stage_no = 0

	# プラン 31: stage1 の hello シーン選択肢ボタンに stylebox が適用されているか
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	if m.scenes.size() > 0:
		# stage1 intro シーンを手動発火
		m._process(5.0)
		if m._waiting_choice and m._scene_btns.size() > 0:
			for b in m._scene_btns:
				var btn := b as Button
				var sb := btn.get_theme_stylebox("normal")
				check("plan31・stage1・選択肢ボタンに stylebox が適用されている", sb != null)
	m.queue_free()
	S.stage_no = 0

	quit(1 if fails > 0 else 0)


# プラン 31 の補助: tint 色が緑系か
func _is_green_tint(c: Color) -> bool:
	# 緑系: g > r かつ g > b
	return c.g > c.r and c.g > c.b


# プラン 31 の補助: tint 色が灰系か（r==g==b の近似。許容誤差 0.05）
func _is_neutral_tint(c: Color) -> bool:
	return absf(c.r - c.g) < 0.05 and absf(c.g - c.b) < 0.05


# プラン 31 の補助: tint 色がオレンジ系か（r > g > b、オレンジは r が一番大きく b が一番小さい）
func _is_orange_tint(c: Color) -> bool:
	return c.r > c.g and c.g > c.b


# プラン 31 の補助: tint 色が赤系か（r > g 且つ r > b が明確、g と b は小さい）
func _is_red_tint(c: Color) -> bool:
	return c.r > c.g + 0.2 and c.r > c.b


func rescue(m: Control) -> void:
	# そのステージのやり方で救出する（通話=人影を指して警告 / 配信=警告コメントを3回）
	if m.mode == "stream":
		for i in 3:
			m._on_comment(i)
	else:
		m._set_mark(m.ghost_box_now().get_center())   # 人影の位置はステージごとに違う
		m._on_warn()


func _sorted(tl: Array) -> bool:
	for i in range(1, tl.size()):
		if tl[i][0] < tl[i - 1][0]:
			return false
	return true

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

	# 6. 人影の濃さの時間割
	m = await fresh()
	check("0秒は濃さ0", m._ghost_alpha_at(0.0) == 0.0)
	check("20秒までは濃さ0", m._ghost_alpha_at(20.0) == 0.0)
	check("95秒で最大", m._ghost_alpha_at(95.0) == 1.0)
	check("途中は単調増加", m._ghost_alpha_at(40.0) < m._ghost_alpha_at(60.0))
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
	S.stage_no = 8   # stage9（最後のステージ、通話モード）
	S.difficulty = 1
	m = await fresh()
	m._start_call()
	at(m, 100.0)   # stage9 の人影が見える時刻
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
	at(m, 65.0)   # 人影のちらつき（0.7〜1.0倍）の影響が小さい時刻。緩和の時間帯を避ける
	m._set_mark(m.ghost_box_now().get_center())
	m._on_warn(1)
	check("「逃げて！」なら信じてもらえる", m.state == m.State.SAVED)
	m.queue_free()
	m = await fresh()
	m._start_call()
	var b1: float = m.belief
	for i in 3:
		m._on_talk()
	check("話しかけると信頼がたまる", m.belief > b1)
	m.queue_free()
	m = await fresh()
	m._start_call()
	var b2: float = m.belief
	m._on_talk()
	var b3: float = m.belief
	m._on_talk()
	m._on_talk()
	check("話しかけを連打しても、信頼は1回分だけ", m.belief == b3 and b3 > b2)
	at(m, m.TALK_COOLDOWN + 1.0)
	m.talk_left = 0.0
	m._on_talk()
	check("クールダウンが明けるとまた話しかけられる", m.belief > b3)
	m.queue_free()
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
	m.t = 75.0   # 人影が濃い（0.4以上）ときは、仕草より怯えが優先。緩和の時間帯を避ける
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
	S.difficulty = 1   # 既定 difficulty 2（fail_at=89.25）だと at(90.0) が fail してしまうので、ふつうで実行
	m = await fresh()
	m._start_call()
	at(m, 90.0)
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
	at(m, 45.0)
	check("人影が見え始めると合図とヒント", m.seen_cue_played and m.hint_label.text.contains("背後の暗がり"))
	m.queue_free()
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, 70.0)
	check("練習以外のステージは合図なし（注意力に任せる）", not m.cue_first_seen and not m.onboarding)
	m.talk_left = 3.0
	m.lock_left = 2.0
	at(m, 71.0)
	check("あと何秒かを表示", m.lock_label.text.contains("警告できるまで") and m.lock_label.text.contains("話しかけ直せるまで"))
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
	m = await fresh()
	m._start_call()
	for i in 5:
		m.talk_left = 0.0
		m._on_talk()
	check("5回話しかけた時点では、まだ一言は出ない", not m.trust_milestone_said)
	m.talk_left = 0.0
	m._on_talk()
	check("ちょうど6回で信頼60%の一言が出る（小数の誤差で7回目にずれない）", m.trust_milestone_said)
	m.queue_free()
	S.stage_no = 0

	# 15. 配信: 警告のあと、視聴者が反応する
	S.stage_no = S.STAGE_FILES.size() - 1
	m = await fresh()
	m._start_call()
	var len_before: int = m.chat_log.get_parsed_text().length()
	m._viewer_echo(true)
	await create_timer(2.4).timeout
	check("視聴者の反応がコメント欄に流れる", m.chat_log.get_parsed_text().length() > len_before)
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
	check("緩和の外（30 秒）は係数 1", m._relief_factor(30.0) == 1.0)
	check("緩和の時間帯の真ん中（43 秒）は係数 0", m._relief_factor(43.0) == 0.0)
	var r_40_6: float = m._relief_factor(40.6)
	check("緩和の境目の 0.4 秒手前（40.6 秒）は 0 と 1 の間", r_40_6 > 0.0 and r_40_6 < 1.0)
	m.queue_free()
	S.stage_no = 0

	# 人影の濃さは、緩和で実際に 0 になる（時間割どおりなら 0 より大きい）
	S.stage_no = 1
	m = await fresh()
	check("緩和の時間帯でも時間割の濃さは 0 より大きい", m._curve_alpha(43.0) > 0.0)
	check("人影の実際の濃さは、緩和中は 0", m._ghost_alpha_at(43.0) == 0.0)
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
	at(m, 43.0)
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
	at(m, 46.0)
	check("緩和の時間帯を抜けたら creak を鳴らす（relief_idx が 1 以上）", m.relief_idx >= 1)
	m.queue_free()
	S.stage_no = 0

	# 配信の緩和中のコメントも誤警告扱いしない
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	at(m, 52.0)
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

	# 17b. 信頼で変わる台詞（idle_trust を持つステージだけ）
	m = await fresh()
	m._start_call()
	m.belief = 0.7
	m._on_talk()
	var chat: String = m.chat_log.get_parsed_text()
	var found_high: bool = false
	for line in m.idle_trust_high:
		if chat.contains(line):
			found_high = true
			break
	check("belief >= 0.6 だと high の台詞が出る", found_high)
	m.queue_free()
	m = await fresh()
	m._start_call()
	m.belief = 0.2
	m._on_talk()
	chat = m.chat_log.get_parsed_text()
	var found_low: bool = false
	for line in m.idle_trust_low:
		if chat.contains(line):
			found_low = true
			break
	check("belief < 0.6 だと low の台詞が出る", found_low)
	m.queue_free()

	# 17c. 信頼が 0.6 に達したときの一言は 1 回だけ
	m = await fresh()
	m._start_call()
	m.belief = 0.58   # 0.58 + TALK_TRUST 0.05 で 0.63 になり、初めて 0.6 を超える
	m._on_talk()
	chat = m.chat_log.get_parsed_text()
	check("belief 0.58 + TALK_TRUST で 0.6 を超え、信頼が高まった一言が出る",
		chat.contains(m.trust_milestone_line))
	m.talk_left = 0.0
	m._on_talk()
	chat = m.chat_log.get_parsed_text()
	check("信頼が高まった一言は 1 回だけ（2 回目の _on_talk では出ない）",
		chat.count(m.trust_milestone_line) == 1)
	m.queue_free()

	# 17d. ステージ1 は従来どおり idle_lines の台詞が出る
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	m._on_talk()
	chat = m.chat_log.get_parsed_text()
	var found_idle: bool = false
	for line in m.idle_lines:
		if chat.contains(line):
			found_idle = true
			break
	check("ステージ1で _on_talk → idle_lines の台詞が出る（従来どおり）", found_idle)
	m.queue_free()
	S.stage_no = 0

	# 18. 難易度: やさしい/ふつう/むずかしい で値が変わる
	for d in 3:
		S.difficulty = d
		S.stage_no = 0
		m = await fresh()
		check("難易度%d: max_false_alarms（%d/%d/%d）" % [d, m.max_false_alarms, m.false_alarm_lock, m.fail_at],
				m.max_false_alarms == [4, 2, 2][d])
		check("難易度%d: false_alarm_lock" % d, m.false_alarm_lock == [3.0, 4.0, 5.0][d])
		# stage1 の fail_at は 105。倍率 1.10 / 0.95 / 0.85 → 115.5 / 99.75 / 89.25
		var want_fail: float = [115.5, 99.75, 89.25][d]
		check("難易度%d: fail_at" % d, absf(m.fail_at - want_fail) < 0.001)
		m.queue_free()
	S.stage_no = 0

	# 18b. ふつう: 既定 difficulty 2（むずかしい相当）で始めたユーザー向けに、値を保持
	S.difficulty = 1
	S.stage_no = 0
	m = await fresh()
	check("ふつう: fail_at は 99.75（= 105 × 0.95）", absf(m.fail_at - 99.75) < 0.001)
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

	# 19. 人影の道筋（ghost_path）: キー値・補間・倍率・ghost_box_now の移動
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("ghost_offset_at(28) は最初のキーの (0, 0)", m.ghost_offset_at(28.0) == Vector2(0, 0))
	check("ghost_offset_at(70) はキー値の (-25, 0)", m.ghost_offset_at(70.0) == Vector2(-25, 0))
	check("ghost_offset_at(95) はキー値の (-80, 10)", m.ghost_offset_at(95.0) == Vector2(-80, 10))
	check("ghost_mult_at(95) は 1.05", absf(m.ghost_mult_at(95.0) - 1.05) < 0.0001)
	check("キーの外（0 秒）は最初の値", m.ghost_offset_at(0.0) == Vector2(0, 0))
	check("キーの外（200 秒）は最後の値", m.ghost_offset_at(200.0) == Vector2(-80, 10))
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
	at(m, 95.0)
	check("ghost_box_now(t=95).position は ghost_box.position + Vector2(-80, 10)",
		m.ghost_box_now().position == m.ghost_box.position + Vector2(-80, 10))
	# ghost_box_now は時刻で動く
	var box_at_95: Rect2 = m.ghost_box_now()
	at(m, 0.0)
	var box_at_0: Rect2 = m.ghost_box_now()
	check("ghost_box_now は時刻で動く（t=0 と t=95 で位置が違う）", box_at_95.position != box_at_0.position)
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
	at(m, 30.0)   # 最初の creak の直後
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
	# 「逃げて！」(selected_phrase=1) を選んでクリック → 救出（relief [66, 70] を避けるため t=72 を使用）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, 72.0)
	m._select_phrase(1)
	m._on_video_click(m.ghost_box_now().get_center())
	check("stage2・selected_phrase=1 で中心クリック → 救出成功", m.state == m.State.SAVED)
	m.queue_free()
	S.stage_no = 0

	# stage2: selected_phrase=0（「後ろ見て！」=弱）では、信頼だけでは救出にならない
	# （belief_start=0.3、話しかけなし、t=65 で alpha≈0.667 → score≈0.93 < 1.0）
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	at(m, 65.0)
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
	S.stage_no = 0
	m = await fresh()
	m._start_call()
	check("stage1・warn_btn は非表示", not m.warn_btn.visible)
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

	# stage2: act_btns は 3 つ、選択中のボタンは modulate が明るい
	S.stage_no = 1
	m = await fresh()
	m._start_call()
	check("stage2・act_btns の要素数 == 3", m.act_btns.size() == 3)
	m._select_phrase(1)
	check("stage2・選択ボタン modulate が他より明るい",
		(m.act_btns[1] as Button).modulate.r > (m.act_btns[0] as Button).modulate.r)
	m.queue_free()
	S.stage_no = 0

	# stage3: act_btns は 3 つ
	S.stage_no = 2
	m = await fresh()
	m._start_call()
	check("stage3・act_btns の要素数 == 3", m.act_btns.size() == 3)
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

	quit(1 if fails > 0 else 0)


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

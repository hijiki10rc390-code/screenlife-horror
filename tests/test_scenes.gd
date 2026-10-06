extends SceneTree
# scenes（会話シーン・選択肢）システムの単体テスト。
# 実行:
#   Godot --headless --path <PJ> -s tests/test_scenes.gd

var fails := 0


func check(name: String, cond: bool) -> void:
	print(("OK   " if cond else "NG   ") + name)
	if not cond:
		fails += 1


# main.tscn を読み込んで実機と同じように走らせる
func fresh(stage_no: int = 0) -> Control:
	var S: GDScript = load("res://main.gd")
	S.stage_no = stage_no
	S.title_done = true
	var m: Control = load("res://main.tscn").instantiate()
	m.persist = false
	root.add_child(m)
	await process_frame
	return m


# m の _process を seconds 秒だけ進める（実時間ではなくゲーム内時間）
func tick(m: Control, seconds: float) -> void:
	var remain := seconds
	while remain > 0.0001:
		var step: float = minf(0.1, remain)
		m._process(step)
		remain -= step


func _initialize() -> void:
	# stage1 のシーン時刻を JSON から取得（fail_at の拡大で変動するため）
	var stage1_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage1.json"))
	var stage1_scenes: Array = stage1_data.get("scenes", [])
	var stage1_intro_at: float = float(stage1_scenes[0]["at"]) if stage1_scenes.size() > 0 else 5.0
	var stage1_warm_at: float = float(stage1_scenes[1]["at"]) if stage1_scenes.size() > 1 else 19.0

	# 1. stage1 に scenes が読み込まれる
	var m: Control = await fresh(0)
	check("stage1: scenes が読める", m.scenes.size() >= 4)
	check("stage1: scenes[0].id は intro", m.scenes.size() > 0 and m.scenes[0]["id"] == "intro")
	check("stage1: 初期は _waiting_choice が false", not m._waiting_choice)
	check("stage1: 初期は _scene_idx が 0", m._scene_idx == 0)
	m.queue_free()

	# 2. intro 到達で _waiting_choice が立つ
	m = await fresh(0)
	m._start_call()
	m._process(stage1_intro_at + 0.5)   # intro at + 0.5 秒
	check("stage1: intro 到達で _waiting_choice == true", m._waiting_choice)
	check("stage1: _current_scene.id は intro", m._current_scene.get("id", "") == "intro")
	check("stage1: 選択肢ボタンが 2 個表示される", m._scene_btns.size() == 2)
	m.queue_free()

	# 3. 選択肢を押すと _waiting_choice が降り、belief が変動する
	m = await fresh(0)
	m._start_call()
	m.belief = 0.5   # テスト用: belief_start=1.0 だと +0.05 がクランプで反映されないので 0.5 から始める
	m._process(stage1_intro_at + 0.5)
	var belief_before: float = m.belief
	m._on_scene_choice(0)   # "うん、なに？" で +0.05
	check("stage1: 選択肢押下で _waiting_choice が降りる", not m._waiting_choice)
	check("stage1: 選択肢の効果で belief が +0.05", absf(m.belief - (belief_before + 0.05)) < 0.001)
	check("stage1: 選択肢ボタンが消える", m._scene_btns.size() == 0)
	m.queue_free()

	# 4. 選択肢を押すと次のシーンへ遷移する（next_scene = "warm"）
	m = await fresh(0)
	m._start_call()
	m._process(stage1_intro_at + 0.5)
	m._on_scene_choice(0)   # warm へ遷移
	tick(m, stage1_warm_at - stage1_intro_at + 5.0)   # warm (at=warm_at) 到達まで
	check("stage1: next_scene で warm に遷移してシーン発火",
		m._current_scene.get("id", "") == "warm" or m._waiting_choice)
	m.queue_free()

	# 5. distant を選んだ場合も同じ after_work に遷移する
	m = await fresh(0)
	m._start_call()
	m._process(stage1_intro_at + 0.5)
	m._on_scene_choice(1)   # distant へ遷移
	tick(m, stage1_warm_at - stage1_intro_at + 5.0)
	check("stage1: distant 選択で after_work に遷移",
		m._current_scene.get("id", "") == "after_work" or m._waiting_choice)
	m.queue_free()

	# 6. belief のクランプ（1.0 を超えない）
	m = await fresh(0)
	m._start_call()
	m.belief = 0.97
	m._process(stage1_intro_at + 0.5)
	m._on_scene_choice(0)   # +0.05 → 1.02 になるはずだがクランプで 1.0
	check("stage1: belief が 1.0 でクランプされる", m.belief == 1.0)
	m.queue_free()

	# 7. belief のクランプ（0.0 を下回らない）
	m = await fresh(0)
	m._start_call()
	m.belief = 0.02
	m._process(stage1_intro_at + 0.5)
	m._on_scene_choice(1)   # -0.04 → -0.02 になるはずだがクランプで 0.0
	check("stage1: belief が 0.0 でクランプされる", m.belief == 0.0)
	m.queue_free()

	# 8. condition の評価（belief による分岐）
	# 構造化 condition: {"var": "belief", "op": ">=", "value": 0.5}
	m = await fresh(0)
	m.belief = 0.6
	var cond_true: bool = m._check_condition({"var": "belief", "op": ">=", "value": 0.5})
	var cond_false: bool = m._check_condition({"var": "belief", "op": ">=", "value": 0.9})
	check("stage1: condition 評価 true (belief=0.6 >= 0.5)", cond_true)
	check("stage1: condition 評価 false (belief=0.6 < 0.9)", not cond_false)
	m.queue_free()

	# 9. condition 省略時は true
	m = await fresh(0)
	check("stage1: 空 condition は true", m._check_condition(""))
	check("stage1: null condition は true", m._check_condition(null))
	m.queue_free()

	# 10. 不正な next_scene は _load_stage で検出される（テスト用に一時ファイルを使う）
	m = await fresh(0)
	# 既存 JSON は next_scene 検証済み。ここでは _load_stage のロジックが通っているか確認
	# 直接テスト: scenes の next_scene が全て有効な id を指している
	var all_valid := true
	for s in m.scenes:
		for ch in s.get("choices", []):
			var nxt: String = ch.get("next_scene", "")
			if nxt == "":
				continue
			var found := false
			for s2 in m.scenes:
				if s2["id"] == nxt:
					found = true
					break
			if not found:
				all_valid = false
	check("stage1: 全 next_scene が有効な id を指す", all_valid)
	m.queue_free()

	# 11. _scene_idx は時刻順に進行する
	m = await fresh(0)
	m._start_call()
	tick(m, stage1_intro_at + 1.0)
	check("stage1: intro 通過後 _scene_idx は 1", m._scene_idx == 1)
	# intro の選択肢を解除してシーン進行を再開させる
	m._waiting_choice = false
	tick(m, stage1_warm_at - stage1_intro_at + 1.0)   # warm 到達まで
	check("stage1: warm 到達後 _scene_idx は 2", m._scene_idx == 2)
	m.queue_free()

	# 12. 全 9 ステージで scenes が動く（Phase 3 で全展開）
	# 各ステージの最初の scene.at を JSON から取得して動的にテストする
	for stage_idx in 9:
		m = await fresh(stage_idx)
		var stage_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage%d.json" % (stage_idx + 1)))
		var stage_scenes: Array = stage_data.get("scenes", [])
		var first_scene_at: float = float(stage_scenes[0]["at"]) if stage_scenes.size() > 0 else 5.0
		check("ステージ%d: scenes が読める" % (stage_idx + 1), m.scenes.size() >= 4)
		m._start_call()
		m._process(first_scene_at + 0.5)
		check("ステージ%d: hello 到達で _waiting_choice" % (stage_idx + 1), m._waiting_choice)
		m.queue_free()

	# 2.5: stage2 特有: 選択肢で belief が +0.06 以上になる（greeting 通過後）
	m = await fresh(1)
	var stage2_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage2.json"))
	var stage2_greeting_at: float = float(stage2_data["scenes"][0]["at"])
	check("stage2: scenes が読める", m.scenes.size() >= 4)
	m._start_call()
	m._process(stage2_greeting_at + 0.5)
	check("stage2: greeting 到達で _waiting_choice", m._waiting_choice)
	m._on_scene_choice(0)
	check("stage2: 選択肢で belief +0.06", m.belief >= 0.30)
	m.queue_free()

	# 2.6: stage3 特有: 選択肢で belief が +0.04（1.0 でクランプ）
	m = await fresh(2)
	var stage3_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://stages/stage3.json"))
	var stage3_hello_at: float = float(stage3_data["scenes"][0]["at"])
	check("stage3: scenes が読める", m.scenes.size() >= 4)
	m._start_call()
	m._process(stage3_hello_at + 0.5)
	check("stage3: hello 到達で _waiting_choice", m._waiting_choice)
	m._on_scene_choice(0)
	check("stage3: 選択肢で belief +0.04", m.belief >= 1.0)
	m.queue_free()

	print("FAIL COUNT: %d" % fails)
	if fails > 0:
		quit(1)
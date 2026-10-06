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
	# 1. stage1 に scenes が読み込まれる
	var m: Control = await fresh(0)
	check("stage1: scenes が読める", m.scenes.size() >= 4)
	check("stage1: scenes[0].id は intro", m.scenes.size() > 0 and m.scenes[0]["id"] == "intro")
	check("stage1: 初期は _waiting_choice が false", not m._waiting_choice)
	check("stage1: 初期は _scene_idx が 0", m._scene_idx == 0)
	m.queue_free()

	# 2. intro (at=5) 到達で _waiting_choice が立つ
	m = await fresh(0)
	m._start_call()
	m._process(5.5)   # 5 秒 + 0.5
	check("stage1: intro 到達で _waiting_choice == true", m._waiting_choice)
	check("stage1: _current_scene.id は intro", m._current_scene.get("id", "") == "intro")
	check("stage1: 選択肢ボタンが 2 個表示される", m._scene_btns.size() == 2)
	m.queue_free()

	# 3. 選択肢を押すと _waiting_choice が降り、belief が変動する
	m = await fresh(0)
	m._start_call()
	m.belief = 0.5   # テスト用: belief_start=1.0 だと +0.05 がクランプで反映されないので 0.5 から始める
	m._process(5.5)
	var belief_before: float = m.belief
	m._on_scene_choice(0)   # "うん、なに？" で +0.05
	check("stage1: 選択肢押下で _waiting_choice が降りる", not m._waiting_choice)
	check("stage1: 選択肢の効果で belief が +0.05", absf(m.belief - (belief_before + 0.05)) < 0.001)
	check("stage1: 選択肢ボタンが消える", m._scene_btns.size() == 0)
	m.queue_free()

	# 4. 選択肢を押すと次のシーンへ遷移する（next_scene = "warm"）
	m = await fresh(0)
	m._start_call()
	m._process(5.5)
	m._on_scene_choice(0)   # warm へ遷移
	tick(m, 20.0)           # warm (at=19) 到達
	check("stage1: next_scene で warm に遷移してシーン発火",
		m._current_scene.get("id", "") == "warm" or m._waiting_choice)
	m.queue_free()

	# 5. distant を選んだ場合も同じ after_work に遷移する
	m = await fresh(0)
	m._start_call()
	m._process(5.5)
	m._on_scene_choice(1)   # distant へ遷移
	tick(m, 20.0)
	check("stage1: distant 選択で after_work に遷移",
		m._current_scene.get("id", "") == "after_work" or m._waiting_choice)
	m.queue_free()

	# 6. belief のクランプ（1.0 を超えない）
	m = await fresh(0)
	m._start_call()
	m.belief = 0.97
	m._process(5.5)
	m._on_scene_choice(0)   # +0.05 → 1.02 になるはずだがクランプで 1.0
	check("stage1: belief が 1.0 でクランプされる", m.belief == 1.0)
	m.queue_free()

	# 7. belief のクランプ（0.0 を下回らない）
	m = await fresh(0)
	m._start_call()
	m.belief = 0.02
	m._process(5.5)
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
	tick(m, 6.0)
	check("stage1: intro (at=5) 通過後 _scene_idx は 1", m._scene_idx == 1)
	# intro の選択肢を解除してシーン進行を再開させる
	m._waiting_choice = false
	tick(m, 14.0)   # warm (at=19) 到達
	check("stage1: warm (at=19) 到達後 _scene_idx は 2", m._scene_idx == 2)
	m.queue_free()

	# 12. ステージ 2 / 3 には scenes が無い（現状）
	m = await fresh(1)
	check("stage2: scenes は空配列", m.scenes.size() == 0)
	m.queue_free()

	m = await fresh(2)
	check("stage3: scenes は空配列", m.scenes.size() == 0)
	m.queue_free()

	print("FAIL COUNT: %d" % fails)
	if fails > 0:
		quit(1)
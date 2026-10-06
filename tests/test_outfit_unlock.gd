extends SceneTree
# 衣装アンロックと衣装専用表情の単体テスト。
# 実行:
#   Godot --headless --path <PJ> -s tests/test_outfit_unlock.gd

var fails := 0


func check(name: String, cond: bool) -> void:
	print(("OK   " if cond else "NG   ") + name)
	if not cond:
		fails += 1


# main.tscn を読み込んで実機と同じように走らせる。テスト用の設定（保存しない）に切り替える
func fresh(stage_no: int = 1) -> Control:
	var S: GDScript = load("res://main.gd")
	S.stage_no = stage_no
	S.title_done = true
	var m: Control = load("res://main.tscn").instantiate()
	m.persist = false   # 設定の永続化は行わない
	root.add_child(m)
	await process_frame
	return m


func _initialize() -> void:
	# 1. 初期状態では max_trust_reached = 0 で pajamas / hoodie はロック
	var m: Control = await fresh()
	check("初期: max_trust_reached == 0.0", m.max_trust_reached == 0.0)
	check("初期: default は常に使える", m._is_outfit_unlocked("default"))
	check("初期: pajamas はロック", not m._is_outfit_unlocked("pajamas"))
	check("初期: hoodie はロック", not m._is_outfit_unlocked("hoodie"))
	check("初期: outfit_layers に default/pajamas/hoodie が揃う",
		m.outfit_layers.has("default") and m.outfit_layers.has("pajamas") and m.outfit_layers.has("hoodie"))
	m.queue_free()

	# 2. 信頼度が閾値丁度で解放される
	m = await fresh()
	m.max_trust_reached = 0.6
	check("信頼 0.6 丁度: pajamas 解放", m._is_outfit_unlocked("pajamas"))
	check("信頼 0.6: hoodie はまだロック", not m._is_outfit_unlocked("hoodie"))
	m.queue_free()

	m = await fresh()
	m.max_trust_reached = 0.85
	check("信頼 0.85 丁度: hoodie 解放", m._is_outfit_unlocked("hoodie"))
	m.queue_free()

	# 3. 閾値の境界: 0.5999 ではまだロック、0.6001 では解放
	m = await fresh()
	m.max_trust_reached = 0.5999
	check("信頼 0.5999: pajamas はまだロック", not m._is_outfit_unlocked("pajamas"))
	m.queue_free()

	# 4. ロック中の衣装は _set_outfit で切り替えできない
	m = await fresh()
	var initial: String = m.current_outfit
	m.max_trust_reached = 0.0
	m._set_outfit("pajamas")
	check("ロック中: pajamas への切替は無視される", m.current_outfit == initial)
	m._set_outfit("hoodie")
	check("ロック中: hoodie への切替も無視される", m.current_outfit == initial)
	m.queue_free()

	# 5. アンロック後は切り替えられる
	m = await fresh()
	m.max_trust_reached = 0.6
	m._set_outfit("pajamas")
	check("信頼 0.6 後: pajamas に切替成功", m.current_outfit == "pajamas")
	m.max_trust_reached = 0.85
	m._set_outfit("hoodie")
	check("信頼 0.85 後: hoodie に切替成功", m.current_outfit == "hoodie")
	m.queue_free()

	# 6. default への切替は常に通る
	m = await fresh()
	m.max_trust_reached = 0.0
	m._set_outfit("default")
	check("信頼 0 でも default に切替できる", m.current_outfit == "default")
	m.queue_free()

	# 7. 衣装を切り替えると current_outfit 以外のレイヤーは非表示になる
	m = await fresh()
	m.max_trust_reached = 0.85
	m._set_outfit("pajamas")
	var pajamas_visible: bool = m.outfit_layers["pajamas"].visible
	var default_visible: bool = m.outfit_layers["default"].visible
	var hoodie_visible: bool = m.outfit_layers["hoodie"].visible
	check("衣装切替: pajamas だけ visible", pajamas_visible and not default_visible and not hoodie_visible)
	m.queue_free()

	# 8. outfit_expressions がある衣装に切り替えると kawaii 表情が置き換わる
	#    stage2 は outfit_expressions を持つ唯一のステージ
	m = await fresh()
	var before_kawaii: Texture = m.react_tex["kawaii"]
	m.max_trust_reached = 0.85
	m._set_outfit("pajamas")
	var after_pajamas_kawaii: Texture = m.react_tex["kawaii"]
	check("pajamas 切替で kawaii 表情が変わる", before_kawaii != after_pajamas_kawaii)
	m._set_outfit("hoodie")
	var after_hoodie_kawaii: Texture = m.react_tex["kawaii"]
	check("hoodie 切替で kawaii 表情がさらに変わる",
		after_hoodie_kawaii != after_pajamas_kawaii and after_hoodie_kawaii != before_kawaii)
	m._set_outfit("default")
	check("default に戻すと kawaii 表情が元に戻る", m.react_tex["kawaii"] == before_kawaii)
	m.queue_free()

	# 9. _refresh_outfit_btns: ロック中はボタンが disabled になり modulate が暗い
	#    _build_ui で構築されたボタンを直接検証する
	m = await fresh()
	m.max_trust_reached = 0.0
	m._refresh_outfit_btns()
	check("ロック中: pajamas ボタンは disabled", m.outfit_btn_pajamas.disabled)
	check("ロック中: hoodie ボタンは disabled", m.outfit_btn_hoodie.disabled)
	check("ロック中: default ボタンは enabled", not m.outfit_btn_default.disabled)
	m.queue_free()

	m = await fresh()
	m.max_trust_reached = 0.6
	m._refresh_outfit_btns()
	check("信頼 0.6: pajamas ボタンは enabled", not m.outfit_btn_pajamas.disabled)
	check("信頼 0.6: hoodie ボタンはまだ disabled", m.outfit_btn_hoodie.disabled)
	m.queue_free()

	m = await fresh()
	m.max_trust_reached = 0.85
	m._refresh_outfit_btns()
	check("信頼 0.85: hoodie ボタンも enabled", not m.outfit_btn_hoodie.disabled)
	m.queue_free()

	# 10. 全ステージで outfit_expressions が登録されている
	# stage1 / stage2 / stage3 すべてに pajamas / hoodie の衣装専用表情がある
	# stage4 / stage5 / stage6 / stage7 / stage8 は衣装差分なし
	for stage_idx in 9:
		m = await fresh(stage_idx)
		var assets: Dictionary = m.assets
		if stage_idx >= 3:
			check("ステージ%d: outfit_expressions は無い（衣装非対応）" % (stage_idx + 1),
				not assets.has("outfit_expressions"))
		else:
			check("ステージ%d: outfit_expressions がある" % (stage_idx + 1),
				assets.has("outfit_expressions") and assets["outfit_expressions"].has("pajamas") and assets["outfit_expressions"].has("hoodie"))
		m.queue_free()

	# 11. 全ステージ × 衣装切替で kawaii 表情が変わる
	for stage_idx in 9:
		m = await fresh(stage_idx)
		m.max_trust_reached = 0.85
		if stage_idx >= 3:
			# stage4 以降は衣装非対応なのでスキップ
			check("ステージ%d: 衣装差分なし" % (stage_idx + 1), true)
			m.queue_free()
			continue
		var before: Texture = m.react_tex["kawaii"]
		m._set_outfit("pajamas")
		var pajamas_kawaii: Texture = m.react_tex["kawaii"]
		m._set_outfit("hoodie")
		var hoodie_kawaii: Texture = m.react_tex["kawaii"]
		m._set_outfit("default")
		var default_kawaii: Texture = m.react_tex["kawaii"]
		check("ステージ%d: pajamas 切替で kawaii 表情が変わる" % (stage_idx + 1),
			before != pajamas_kawaii)
		check("ステージ%d: hoodie 切替で kawaii 表情がさらに変わる" % (stage_idx + 1),
			pajamas_kawaii != hoodie_kawaii and hoodie_kawaii != before)
		check("ステージ%d: default に戻すと kawaii 表情が元に戻る" % (stage_idx + 1),
			default_kawaii == before)
		m.queue_free()

	print("FAIL COUNT: %d" % fails)
	if fails > 0:
		quit(1)
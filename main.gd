extends Control
# 画面越しのホラー。ステージ（stages/*.json）を順に遊ぶ。通話2つ（練習・疑り深い相手）と配信1つ。
# 実行: Godot --path <このフォルダ>
# 確認用の起動引数（-- の後ろ）: --shot（画面を撮る） --stage=N（開始ステージ） --title-shot（タイトル画面を撮る）
#
# 遊び方: 相手の背後に何か映ったら、気づいて警告する。
#   通話   = 映像をクリックして「警告する」（疑り深い相手は、話しかけて信頼をため、伝え方を選ぶ）
#   配信   = 警告コメントを、映っている間に何度か投稿する
#   失敗   = 映る前や場所違いの警告が3回 / 気づかないまま時間切れ
# 操作: 映像クリック=警告  1・2・3=伝え方の選択  Enter=応答・話しかける・もう一度  Esc=一時停止・音量  F11=全画面
#       R=もう一度  Esc=一時停止・音量・演出を弱める

const SCENE_W := 1024
const SCENE_H := 576
const VIDEO_POS := Vector2(70, 90)
const VIDEO_SIZE := Vector2(750, 422)

const MAX_FALSE_ALARMS := 3        # 既定値。テストが参照しているので残す。判定は max_false_alarms を使う
const SEEN_THRESHOLD := 0.08       # これ以上濃ければ「異変が映っている」と扱う
const FALSE_ALARM_LOCK := 3.0      # 既定値。テストが参照しているので残す。判定は false_alarm_lock を使う
const TYPING_LEAD := 1.2           # 相手のセリフの何秒前から「入力中」を出すか

# 難易度（0=やさしい / 1=ふつう / 2=むずかしい。既定は 1=ふつう、いまの挙動と完全に同じ）
const DIFFICULTY_NAMES := ["やさしい", "ふつう", "むずかしい"]
# [誤警告の上限, 誤警告のあと警告できない秒数, 制限時間の倍率, 疑り深い相手の初期信頼への加算, 配信で必要な警告コメント数への加算]
const DIFFICULTY_TABLE := [
	[4, 3.0, 1.10, 0.10, -1],   # やさしい: 誤警告 4 回まで、ロック 3 秒、制限時間 +10%、初期信頼 +0.10、配信は -1 回
	[2, 4.0, 0.95, 0.0, 0],     # ふつう: 誤警告 2 回まで、ロック 4 秒、制限時間 -5%、配信 ±0
	[2, 5.0, 0.85, -0.05, 1]    # むずかしい: 誤警告 2 回まで、ロック 5 秒、制限時間 -15%、初期信頼 -0.05、配信 +1 回
]

# ステージの設定ファイル（画像・人影の範囲・時間割・台詞）。順番に遊ぶ
const STAGE_FILES := ["res://stages/stage1.json", "res://stages/stage2.json", "res://stages/stage3.json"]
static var stage_no := 0           # 今のステージ。画面の再読み込みをまたいで保持する
static var difficulty := 2         # 画面の再読み込みをまたいで保持する。設定にも保存される（既定: むずかしい）

# ここから下はステージ設定から読み込む値（_load_stage）
var friend := ""
var assets := {}
var ghost_box := Rect2()           # 人影のいる範囲（映像内の座標）。ここを指して警告すれば正解
var ghost_curve := []              # 人影の濃さの時間割 [秒, 濃さ]。間は直線で補間する
var fail_at := 110.0
var uneasy_at := 48.0
var creaks := []                   # 床のきしみが鳴る時刻
var relief := []                   # 緩和の時間帯 [[開始秒, 終了秒], ...]。人影が一時的に消える区間
var timeline := []                 # 相手のセリフ [秒, 文]
var idle_lines := []
var idle_trust_low := []         # idle_trust.low の台詞（信頼が低いとき）。無ければ空
var idle_trust_high := []        # idle_trust.high の台詞（信頼が高いとき）。無ければ空
var trust_milestone_line := ""   # 信頼が初めて 0.6 に達したときの一言（任意）
var miss_unseen := []
var miss_wrong := []
var saved_line := ""
var trust_lost_line := ""
var timeout_line := ""
var mode := "call"                 # "call"=通話（映像を指して警告） / "stream"=配信（コメントで警告）
var viewer_base := 100
var chatter_lines := []            # 配信：流れる視聴者コメント
var warn_phrases := []             # 配信：プレイヤーが投稿できる警告コメント
var need_warnings := 3             # 配信：気づいてもらうのに必要な警告コメントの数
var warn_window := 20.0            # 配信：その数を数える秒数
var warn_times := []
var chatter_timer := 0.0
var third_btn: Button
var lock_label: Label              # 「あと何秒で操作できるか」の表示
var hint_age := 0.0                # 今のヒントを出してからの秒数（一定時間でうっすら消す）
var last_hint := ""
var onboarding := false            # 練習ステージ: 人影が見え始めたときに、短いヒントを出す
var cue_first_seen := false        # 練習ステージ: 人影が初めて映った瞬間に音で知らせる
var seen_cue_played := false
var fourth_btn: Button
var act_btns := []                 # 警告として押すボタンの一覧（通話の単独ボタン / 伝え方3つ / 配信のコメント3つ）
var belief_start := 1.0            # 相手が最初からどれだけ信じるか（1.0=すぐ信じる。小さいほど疑う）
var belief := 1.0
var doubt_lines := []
var ghost_scale := [1.0, 1.0]      # 人影の大きさ [最初, 最も濃いとき]。濃くなるほど近づいて見える
var ghost_pivot := [512.0, 288.0]  # 大きくなる中心（人影の足元）。映像内の座標
var ghost_face := []                # 人影の顔の中心（映像内の座標）。襲いかかりで、顔が映像の中心に来るように使う
var ghost_path := []                # 人影の道筋 [[秒, dx, dy, 倍率], ...]。無い/空なら従来どおり（ずれなし・倍率 1）
var lures := []                    # 誘惑の仕草 [{asset, from, to}]。人影が薄い間に差し込む
var use_phrases := false           # 警告の伝え方を選ばせるか（疑う相手のステージ）
const PHRASES := ["後ろ見て！", "逃げて！", "外に出て！"]
const PHRASE_BONUS := [0.10, 0.30, 0.20]   # 伝え方ごとの説得力（「逃げて！」が一番強い）
const TALK_TRUST := 0.05                   # 話しかけるたびにたまる信頼
const TALK_COOLDOWN := 4.0                 # 話しかけ直せるまでの秒数（連打で信頼を稼げないように）
const TRUST_HIGH := 0.6                      # この信頼を超えると、相手の台詞が親しげに変わる（小数の足し算の誤差を許容して比べる）
const TRUST_EPS := 0.0001
const DOUBT_GAIN := 0.15                   # 流されたあと、次の警告が通りやすくなる分

enum State { TITLE, PLAYING, SAVED, FAILED }

var t := 0.0
var state := State.TITLE
var false_alarms := 0
var max_false_alarms := 3          # 難易度によって変わる値。判定はこちらを使う
var false_alarm_lock := 3.0        # 難易度によって変わる値。判定はこちらを使う
var timeline_idx := 0
var creak_idx := 0
var relief_idx := 0                # 鳴らした creak の数（緩和の時間帯ごとに 1 回）
var idle_idx := 0
var idle_trust_idx := 0            # idle_trust の台詞の順番
var trust_milestone_said := false  # 信頼の高まりを告げたか（1 回だけ言う）
var lock_left := 0.0
var talk_left := 0.0               # 話しかけのクールダウンの残り秒数
var shake_left := 0.0
var has_mark := false
var mark_scene := Vector2.ZERO
var selected_phrase := 0         # 1・2・3キーで選んだ伝え方（0〜2）。映像クリック時の _on_warn/_on_comment に渡す
var stutter_left := 0.0        # コマ落ち演出の残り秒数（0 のとき非アクティブ）
var stutter_offset := Vector2.ZERO   # コマ落ち中に加える ±6px のランダムなずれ
var stutter_next := 0.0        # 次のコマ落ちを起こせるまでの秒数（0.6〜2.0 の乱数でセット）
var lunge := 0.0               # 失敗の瞬間の襲いかかり（0→1）。0 のとき非アクティブ
var dim_left := 0.0            # きしみに合わせた暗転の残り秒数（0 のとき非アクティブ）

var shot_mode := false
var shot_frame := 0

var stage: Control
var react_bottom: TextureRect      # 表情の切り替え中、古いほうの表情が残る層
var react_top: TextureRect         # 新しい表情が現れる層
var react_tex := {}
var react_name := ""
var react_speed := 1.2
var ghost_layer: TextureRect
var video: TextureRect
var cam_mat: ShaderMaterial
var chat_log: RichTextLabel
var status_label: Label
var timer_label: Label
var typing_label: Label
var hint_label: Label
var trust_bar_fill: ColorRect      # 信頼ゲージの中身（use_phrases のステージだけ作成）
var trust_bar_label: Label          # 信頼ゲージの % 表示（use_phrases のステージだけ作成）
var talk_btn: Button
var warn_btn: Button
var marker: Control
var flash: ColorRect
var title_panel: Control
var end_panel: Control
var end_label: Label
var end_face: TextureRect      # 結果画面の表情（end_panel の子）
const AudioMgrScript := preload("res://audio_manager.gd")
var audio: Node                    # 音の管理（audio_manager.gd）
var paused := false
var pause_panel: Control
var vol_master := 1.0
var vol_amb := 0.8
var vol_sfx := 1.0
var calm := false                  # 演出を弱める（画面の揺れ・点滅・映像の乱れを抑える）
var end_sub: Label
static var title_done := false     # タイトル画面を出したか（画面の再読み込みでは出し直さない）
var title_screen: Control
var title_shot := false
var lunge_shot := false           # 撮影用: 失敗の襲いかかりを撮って終了（-- --lunge-shot）
var reached := 0                   # 到達した（遊べる）最後のステージ番号
var persist := true                # false なら設定・進行を保存しない（テスト用）
const SETTINGS_PATH := "user://settings.cfg"
var viewers := 0
var retry_btn: Button
var diff_btns: Array[Button] = []  # タイトル画面の難易度ボタン（見た目更新に使う）
# --- 計画 08: UI の作り込み ---
var wallpaper: Control             # デスクトップの背景（グラデーション）
var taskbar: Control               # 下の帯（時計・Wi-Fi・バッテリー）
var taskbar_clock: Label           # タスクバーの時計表示
var win_shadow: Control            # メインウィンドウの影
var win_titlebar: Control          # メインウィンドウのタイトルバー
var win_dots: Array[ColorRect] = []   # タイトルバーの赤黄緑の点
var rec_label: Label               # 映像枠の左上の REC インジケーター
var live_badge: Control            # 配信の LIVE バッジ
var call_bars: Array[ColorRect] = []   # 通話品質の縦線バー（5 本）
# --- 計画 09: 口パクと瞬き ---
var face_overlay: Control          # 顔の上のオーバーレイ（口・まぶた）
var mouth_open := 0.0              # 0.0=閉じている、1.0=全開
var mouth_open_until := 0.0        # この時刻まで口を開いている
var next_blink := 0.0              # 次の瞬きの予定時刻
var blink_t := 0.0                 # 瞬きの開始時刻（0=瞬き中ではない）
var face_fx_scale := Vector2(1, 1) # face_fx 座標を画面座標に変換するスケール
var stage_d: Dictionary = {}        # 計画 09: ステージ JSON 全体（face_fx 参照用）


func _ready() -> void:
	shot_mode = "--shot" in OS.get_cmdline_user_args()
	if shot_mode or "--title-shot" in OS.get_cmdline_user_args() or "--lunge-shot" in OS.get_cmdline_user_args():
		persist = false   # 撮影の実行で、実際の進行・設定を書き換えない
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_title("Screenlife Horror（仮題・試作）")
	_load_stage()
	_load_settings()
	_apply_difficulty()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Yu Gothic", "Meiryo"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 20
	var vp := _build_scene_viewport()
	_build_ui(vp)
	_build_audio()
	_apply_volume()
	lunge_shot = "--lunge-shot" in OS.get_cmdline_user_args()
	if lunge_shot:
		_start_call()
		t = fail_at - 0.2   # すぐ時間切れ → 襲いかかり
	elif shot_mode:
		_start_call()
	elif not title_screen.visible:
		audio.play("ring")   # 着信画面: 応答するまで着信音


# --- 映像（実写風の背景＋人影の重ね画像）を SubViewport に組み立てる --------------------

func _build_scene_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(SCENE_W, SCENE_H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	stage = Control.new()
	stage.size = Vector2(SCENE_W, SCENE_H)
	stage.pivot_offset = stage.size / 2.0
	vp.add_child(stage)
	_layer(assets["base"])
	for n in ["uneasy", "scared", "terror", "saved", "failed", "kawaii"]:
		if assets.has(n):
			react_tex[n] = load(assets[n])
	for i in lures.size():
		react_tex["lure%d" % i] = load(lures[i]["asset"])
	react_bottom = _blank_layer()
	react_top = _blank_layer()
	ghost_layer = _layer(assets["ghost"])
	ghost_layer.modulate.a = 0.0
	ghost_layer.pivot_offset = Vector2(ghost_pivot[0], ghost_pivot[1])
	return vp


func _blank_layer() -> TextureRect:
	var tr := _layer(assets["base"])
	tr.texture = null
	tr.modulate.a = 0.0
	return tr


# 今の状況に合う相手の表情。"" は通常の顔
func _react_target() -> String:
	if state == State.SAVED or state == State.FAILED:
		return "terror"
	if state == State.PLAYING:
		if _ghost_alpha_at(t) >= 0.5:
			return "scared"
		# プラン 13: 仕草 > かわいい > 不安 の順
		for i in lures.size():
			if t >= lures[i]["from"] and t < lures[i]["to"]:
				return "lure%d" % i
		if react_tex.has("kawaii"):
			return "kawaii"
		if _ghost_alpha_at(t) >= 0.2:
			return "uneasy"
	return ""


func _set_react(name: String) -> void:
	if name == react_name:
		return
	# 古い表情を下の層に残し、新しい表情を上の層で徐々に出す
	react_bottom.texture = react_top.texture
	react_bottom.modulate.a = 1.0 if react_top.texture else 0.0
	react_top.texture = react_tex.get(name)
	react_top.modulate.a = 0.0
	react_speed = 3.0 if name == "terror" else 1.2
	react_name = name
	# 計画 09: 表情が変わったら瞬きと口のタイマーをリセット
	next_blink = t + randf_range(2.0, 5.0)
	blink_t = 0.0
	mouth_open = 0.0
	mouth_open_until = 0.0
	if face_overlay != null:
		face_overlay.queue_redraw()


func _layer(path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = load(path)
	tr.size = Vector2(SCENE_W, SCENE_H)
	stage.add_child(tr)
	return tr


# --- 画面（通話アプリ風 UI）-----------------------------------------------------

func _panel(pos: Vector2, size: Vector2, color: Color, parent: Control = null) -> ColorRect:
	var p := ColorRect.new()
	p.position = pos
	p.size = size
	p.color = color
	(parent if parent else self).add_child(p)
	return p


func _label(text: String, pos: Vector2, size: Vector2, parent: Control, font_size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	return s


func _button(text: String, pos: Vector2, size: Vector2, base: Color, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE   # Space を押したとき、ボタンが二重に反応しないように
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _style(base))
	b.add_theme_stylebox_override("hover", _style(base.lightened(0.18)))
	b.add_theme_stylebox_override("pressed", _style(base.darkened(0.25)))
	b.add_theme_stylebox_override("disabled", _style(base.darkened(0.45)))
	b.button_down.connect(func() -> void:   # 押した瞬間にわずかに縮み、すぐ戻る
		b.pivot_offset = b.size / 2.0
		b.scale = Vector2(0.95, 0.95))
	b.button_up.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	(parent if parent else self).add_child(b)
	return b


# --- 計画 08: タスクバーの時計とシステムアイコン ---------------------------------

var _taskbar_last := -1   # 最後に時計を更新した秒（毎秒更新を抑える）


func _refresh_taskbar_clock() -> void:
	if taskbar_clock == null:
		return
	var t := Time.get_time_dict_from_system()
	taskbar_clock.text = "%02d:%02d" % [t.hour, t.minute]


func _draw_sysicons_on(c: Control) -> void:
	# Wi-Fi のアイコン（弧 3 本。taskbar 内の子 Control の座標系）
	var wifi_c := Color(0.8, 0.85, 0.9)
	for r in [4.0, 8.0, 12.0]:
		c.draw_arc(Vector2(8, 26), r, PI * 1.25, PI * 1.75, 16, wifi_c, 1.5)
	c.draw_circle(Vector2(8, 28), 1.5, wifi_c)
	# バッテリー（四角 + 内側の縦線）
	var batt_c := Color(0.8, 0.85, 0.9)
	c.draw_rect(Rect2(28, 16, 32, 14), batt_c, false, 1.5)
	c.draw_rect(Rect2(60, 19, 3, 8), batt_c, true)   # 端子
	# 中身（3 セル点灯。あと 30% と仮定）
	c.draw_rect(Rect2(31, 19, 8, 8), batt_c, true)
	c.draw_rect(Rect2(41, 19, 8, 8), Color(0.4, 0.4, 0.45), true)
	c.draw_rect(Rect2(51, 19, 6, 8), Color(0.4, 0.4, 0.45), true)


func _draw_live_badge_on(c: Control) -> void:
	# 配信の LIVE バッジ。赤丸が 1 秒周期で点滅（alpha を sin で）
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * TAU)
	c.draw_circle(Vector2(12, 12), 6.0, Color(1.0, 0.3, 0.3, blink))


# --- 計画 09: 口パク・瞬き -----------------------------------------------------------

const BLINK_DURATION := 0.15   # 瞬きの持続（秒）


func _update_face_overlay(delta: float) -> void:
	# 口の開閉（mouth_open_until まで開き、0.2 秒で閉じる）
	if t < mouth_open_until:
		mouth_open = minf(1.0, mouth_open + delta * 4.0)
	else:
		mouth_open = maxf(0.0, mouth_open - delta * 5.0)
	# 瞬き
	if next_blink < 0.001:
		next_blink = t + randf_range(2.0, 5.0)
	elif t >= next_blink and blink_t == 0.0:
		blink_t = t
		next_blink = t + BLINK_DURATION + randf_range(2.0, 5.0)
	if blink_t > 0.0 and t > blink_t + BLINK_DURATION:
		blink_t = 0.0
	# 口の開閉か瞬き中なら face_overlay を再描画
	if mouth_open > 0.01 or blink_t > 0.0:
		face_overlay.visible = true
		face_overlay.queue_redraw()
	else:
		face_overlay.visible = false


# 口の矩形と瞬きの矩形は face_fx から得る。なければ画面中央にフォールバック
func _current_face_fx() -> Dictionary:
	# react_name → face_*.png ファイル名（"smile_40" 等）のマッピング
	# react_tex["saved"] = face_happy_41 のような対応
	var m := {
		"saved": "happy_41",
		"failed": "despair_41",
		"scared": "fear_40",
		"terror": "fear_41",
		"uneasy": "worry_40",
	}
	if react_name in m and not stage_d.is_empty() and stage_d.get("face_fx", {}).has(m[react_name]):
		return stage_d["face_fx"][m[react_name]]
	return {}


func _draw_face_on(c: Control) -> void:
	# face_fx の座標は元の画像（1280x720 など）での座標。VIDEO_SIZE / 1280 でスケール
	var fx := _current_face_fx()
	var sx := VIDEO_SIZE.x / 1280.0
	var sy := VIDEO_SIZE.y / 720.0
	# デフォルトの口と目の位置（face_fx が無いとき、またはサイズが 0 のとき）
	var mouth_pos := Vector2(VIDEO_SIZE.x * 0.5, VIDEO_SIZE.y * 0.78)
	var mouth_size := Vector2(VIDEO_SIZE.x * 0.06, VIDEO_SIZE.y * 0.03)
	var eye_pos := Vector2(VIDEO_SIZE.x * 0.5, VIDEO_SIZE.y * 0.38)
	var eye_size := Vector2(VIDEO_SIZE.x * 0.18, VIDEO_SIZE.y * 0.04)
	if fx.has("mouth"):
		var mb = fx["mouth"]
		if mb[2] > 0 and mb[3] > 0:
			mouth_pos = Vector2(mb[0] * sx, mb[1] * sy)
			mouth_size = Vector2(mb[2] * sx, mb[3] * sy)
	if fx.has("eye"):
		var eb = fx["eye"]
		if eb[2] > 0 and eb[3] > 0:
			eye_pos = Vector2(eb[0] * sx, eb[1] * sy)
			eye_size = Vector2(eb[2] * sx, eb[3] * sy)
	# 口（mouth_open に応じて縦に開く）
	if mouth_open > 0.01:
		var open_h := mouth_size.y * (0.2 + mouth_open * 0.8)
		var center := mouth_pos + Vector2(mouth_size.x * 0.5, mouth_size.y * 0.5)
		# 口の影（黒い楕円）: draw_circle 2 枚で楕円を表現
		var rx := mouth_size.x * 0.45
		var ry := open_h * 0.5
		c.draw_rect(Rect2(center.x - rx, center.y - ry, rx * 2, ry * 2), Color(0.0, 0.0, 0.0, 0.7), true)
		# 唇の薄い赤（楕円の輪郭）
		var pts := PackedVector2Array()
		for i in 24:
			var a := float(i) / 24.0 * TAU
			pts.append(Vector2(center.x + cos(a) * rx, center.y + sin(a) * ry))
		pts.append(pts[0])
		c.draw_polyline(pts, Color(0.5, 0.15, 0.15, 0.4), 1.5)
	# 瞬き（目の上に矩形が降りてくる）
	if blink_t > 0.0:
		var p := clampf((t - blink_t) / BLINK_DURATION, 0.0, 1.0)
		# 0.0→0.5: 降りてくる、0.5→1.0: 持ち上がる
		var h := eye_size.y * (1.0 - absf(p * 2.0 - 1.0))
		var eye_rect := Rect2(eye_pos.x, eye_pos.y, eye_size.x, h)
		c.draw_rect(eye_rect, Color(0.1, 0.1, 0.15, 0.85))


func _refresh_rec_label() -> void:
	if rec_label == null:
		return
	var tm := int(t)
	rec_label.text = "● REC  %02d:%02d:%02d" % [tm / 3600, (tm / 60) % 60, tm % 60]
	# 赤い丸の点滅
	rec_label.modulate = Color(1.0, 0.55, 0.55, 0.7 + 0.3 * sin(Time.get_ticks_msec() / 1000.0 * TAU))


func _refresh_call_bars() -> void:
	# 通話品質のバー（5 本）。人影の濃さに応じて光る本数を変える
	if call_bars.is_empty():
		return
	var active := int(ghost_layer.modulate.a * 5.0) if ghost_layer != null else 0
	for i in 5:
		var c := Color(0.3, 0.85, 0.5) if i < active else Color(0.4, 0.45, 0.50, 0.4)
		call_bars[i].color = c


func _build_ui(vp: SubViewport) -> void:
	# _build_ui は _ready から呼ばれる。各セクションは下のサブ関数で構築する
	_build_wallpaper()
	_build_taskbar()
	_build_main_window()
	_build_video_overlay(vp)
	_build_hint_and_chat()
	_build_action_buttons()
	_build_marker()
	_build_flash()
	_build_trust_bar()
	_build_call_panel()
	_build_end_panel()
	_build_pause_panel()
	_build_title_screen()


# 背景の縦グラデーション壁紙（計画 08）
func _build_wallpaper() -> void:
	wallpaper = TextureRect.new()
	wallpaper.position = Vector2.ZERO
	wallpaper.size = Vector2(1280, 720)
	wallpaper.stretch_mode = TextureRect.STRETCH_SCALE
	var wgrad := Gradient.new()
	wgrad.set_color(0, Color(0.12, 0.15, 0.22))
	wgrad.set_color(1, Color(0.03, 0.04, 0.08))
	var wtex := GradientTexture1D.new()
	wtex.gradient = wgrad
	wtex.width = 64
	wallpaper.texture = wtex
	add_child(wallpaper)


# タスクバー（下の帯。時計・Wi-Fi・バッテリーのアイコン）
func _build_taskbar() -> void:
	taskbar = _panel(Vector2(0, 680), Vector2(1280, 40), Color(0.06, 0.07, 0.10, 0.95))
	var tbar_clock_label := _label("", Vector2(20, 8), Vector2(120, 24), taskbar, 16)
	tbar_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	taskbar_clock = tbar_clock_label
	_refresh_taskbar_clock()
	# Wi-Fi・バッテリーのアイコン（_draw で描く）
	var sysicons := Control.new()
	sysicons.position = Vector2(1140, 4)
	sysicons.size = Vector2(130, 32)
	sysicons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sysicons.draw.connect(_draw_sysicons_on.bind(sysicons))
	taskbar.add_child(sysicons)


# メインウィンドウ（影・背景・タイトルバー・赤黄緑の点・相手名・LIVE/通話バー）
func _build_main_window() -> void:
	# メインウィンドウの影（暗い矩形を 1〜2 px ずらす）
	win_shadow = _panel(Vector2(54, 46), Vector2(790, 620), Color(0, 0, 0, 0.45))
	var win := _panel(Vector2(50, 40), Vector2(790, 620), Color(0.15, 0.16, 0.19))
	# タイトルバー（メインウィンドウの頭）
	win_titlebar = _panel(Vector2(50, 40), Vector2(790, 32), Color(0.10, 0.11, 0.14))
	# 通話/配信アプリ風の 3 つの点（左に並べる）。押せない（描画のみ）
	var dot_x := 66
	for color in [Color(1.0, 0.36, 0.34), Color(1.0, 0.78, 0.20), Color(0.34, 0.84, 0.40)]:
		var dot := ColorRect.new()
		dot.position = Vector2(dot_x, 50)
		dot.size = Vector2(12, 12)
		dot.color = color
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		win_dots.append(dot)
		dot_x += 20
	# タイトルバー中央に相手名
	_label(("配信中  -  " if mode == "stream" else "通話  -  ") + friend, Vector2(50 + 110, 42), Vector2(300, 28), self, 18)
	# タイトルバー右に通話時間 / LIVE バッジ
	if mode == "stream":
		# LIVE バッジ（赤い丸 + 「LIVE」）。Label 一個で完結させてテキストの切れを防ぐ
		live_badge = _label("● LIVE", Vector2(720, 46), Vector2(110, 24), self, 16)
		live_badge.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		live_badge.add_theme_constant_override("outline_size", 1)
		live_badge.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.0, 0.8))
	else:
		# 通話品質の縦線バー（5 本）。音量や ghost alpha に応じて点灯
		call_bars.clear()
		var bar_x := 50 + 690
		for i in 5:
			var bar := ColorRect.new()
			bar.position = Vector2(bar_x + i * 6, 50)
			bar.size = Vector2(3, 14)
			bar.color = Color(0.4, 0.6, 0.5, 0.4)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(bar)
			call_bars.append(bar)
	# 通話時間 / 状態表示のラベル
	timer_label = _label("00:00", Vector2(380, 48), Vector2(100, 26), self, 18)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.modulate = Color(0.7, 0.8, 0.9)
	status_label = _label("", Vector2(500, 48), Vector2(200, 26), self, 18)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


# 映像の本体・枠・REC ラベル・顔オーバーレイ
func _build_video_overlay(vp: SubViewport) -> void:
	video = TextureRect.new()
	video.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	video.stretch_mode = TextureRect.STRETCH_SCALE
	video.texture = vp.get_texture()
	video.position = VIDEO_POS
	video.size = VIDEO_SIZE
	video.mouse_default_cursor_shape = Control.CURSOR_CROSS
	video.gui_input.connect(_on_video_input)
	cam_mat = ShaderMaterial.new()
	cam_mat.shader = load("res://webcam.gdshader")
	cam_mat.set_shader_parameter("res", Vector2(512.0, 288.0))
	cam_mat.set_shader_parameter("noise_amt", 0.07)
	video.material = cam_mat
	add_child(video)

	# 映像の枠（角丸）と ● REC ラベル。video は矩形なので枠は外側に別レイヤで描く
	var video_frame := PanelContainer.new()
	video_frame.position = VIDEO_POS - Vector2(2, 2)
	video_frame.size = VIDEO_SIZE + Vector2(4, 4)
	video_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsb := StyleBoxFlat.new()
	vsb.bg_color = Color(0, 0, 0, 0)
	vsb.border_color = Color(0.55, 0.55, 0.62, 0.7)
	vsb.set_border_width_all(2)
	vsb.set_corner_radius_all(4)
	video_frame.add_theme_stylebox_override("panel", vsb)
	add_child(video_frame)
	# ● REC + 時刻（左上）
	rec_label = _label("● REC  00:00:00", Vector2(VIDEO_POS.x + 10, VIDEO_POS.y + 6), Vector2(220, 24), self, 16)
	rec_label.modulate = Color(1.0, 0.55, 0.55)
	# 計画 09: 顔オーバーレイ（口パク・瞬き）
	face_overlay = Control.new()
	face_overlay.position = VIDEO_POS
	face_overlay.size = VIDEO_SIZE
	face_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face_overlay.draw.connect(_draw_face_on.bind(face_overlay))
	face_overlay.visible = false
	add_child(face_overlay)


# ヒント表示とチャット欄
func _build_hint_and_chat() -> void:
	hint_label = _label("", Vector2(70, 510), Vector2(750, 40), self, 16)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.modulate = Color(0.65, 0.7, 0.78)

	var chat := _panel(Vector2(860, 40), Vector2(370, 620), Color(0.15, 0.16, 0.19))
	_label("コメント" if mode == "stream" else "チャット", Vector2(16, 8), Vector2(200, 26), chat)
	chat_log = RichTextLabel.new()
	chat_log.position = Vector2(16, 44)
	chat_log.size = Vector2(338, 520)
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.add_theme_font_size_override("normal_font_size", 20)
	chat.add_child(chat_log)
	typing_label = _label(friend + " が入力中…", Vector2(16, 580), Vector2(338, 26), chat, 15)
	typing_label.modulate = Color(0.72, 0.76, 0.84)
	typing_label.visible = false


# アクションボタン（話しかけ・警告・3つ目・4つ目）。ステージ別で配置・表示を切替
func _build_action_buttons() -> void:
	talk_btn = _button("話しかける  (Enter)", Vector2(70, 552), Vector2(200, 56), Color(0.2, 0.22, 0.28))
	talk_btn.pressed.connect(_on_talk)
	warn_btn = _button("警告する  (Space)", Vector2(290, 552), Vector2(200, 56), Color(0.45, 0.16, 0.16))
	warn_btn.pressed.connect(_on_warn)
	third_btn = _button("", Vector2(510, 552), Vector2(200, 56), Color(0.45, 0.16, 0.16))
	third_btn.visible = false
	fourth_btn = _button("", Vector2(630, 552), Vector2(150, 56), Color(0.45, 0.16, 0.16))
	fourth_btn.visible = false
	# stage1（伝え方が 1 つ）: 警告は映像クリックで出すので、画面下の警告ボタンは出さない
	if not use_phrases and mode != "stream":
		warn_btn.visible = false
		third_btn.visible = false
		fourth_btn.visible = false
		act_btns = []
	if use_phrases:   # 疑う相手: 話しかけて信頼をためつつ、伝え方を選んで警告する
		talk_btn.size = Vector2(150, 56)
		talk_btn.text = "話しかける"
		warn_btn.position = Vector2(244, 552)
		warn_btn.size = Vector2(160, 56)
		third_btn.position = Vector2(414, 552)
		third_btn.size = Vector2(160, 56)
		fourth_btn.position = Vector2(584, 552)
		fourth_btn.size = Vector2(160, 56)
		third_btn.visible = true
		fourth_btn.visible = true
		warn_btn.pressed.disconnect(_on_warn)
		act_btns = [warn_btn, third_btn, fourth_btn]
		for i in 3:
			(act_btns[i] as Button).text = "%d  %s" % [i + 1, PHRASES[i]]
			(act_btns[i] as Button).pressed.connect(_select_phrase.bind(i))
		_update_phrase_btns()
	if mode == "stream":   # 配信では、3つのボタンがそれぞれ警告コメントの選択になる（押しただけでは警告しない）
		talk_btn.pressed.disconnect(_on_talk)
		warn_btn.pressed.disconnect(_on_warn)
		third_btn.visible = true
		act_btns = [talk_btn, warn_btn, third_btn]
		for i in 3:
			var b: Button = act_btns[i]
			b.text = "%d  %s" % [i + 1, warn_phrases[i]]
			b.pressed.connect(_select_phrase.bind(i))
		_update_phrase_btns()

	# ロックアウトのラベル（誤警告後のカウントダウン）
	lock_label = _label("", Vector2(70, 614), Vector2(710, 24), self, 15)
	lock_label.modulate = Color(1.0, 0.82, 0.45)


# 指した場所の目印（赤い十字）
func _build_marker() -> void:
	marker = Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.visible = false
	marker.draw.connect(func() -> void:
		marker.draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 40, Color(1.0, 0.35, 0.3, 0.95), 2.5)
		marker.draw_line(Vector2(-36, 0), Vector2(-16, 0), Color(1.0, 0.35, 0.3, 0.95), 2.5)
		marker.draw_line(Vector2(16, 0), Vector2(36, 0), Color(1.0, 0.35, 0.3, 0.95), 2.5)
		marker.draw_line(Vector2(0, -36), Vector2(0, -16), Color(1.0, 0.35, 0.3, 0.95), 2.5)
		marker.draw_line(Vector2(0, 16), Vector2(0, 36), Color(1.0, 0.35, 0.3, 0.95), 2.5))
	add_child(marker)


# 画面の点滅（失敗・救出時のフラッシュ）
func _build_flash() -> void:
	flash = _panel(VIDEO_POS, VIDEO_SIZE, Color(1, 0, 0, 0))
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE


# 信頼ゲージ（疑う相手のステージだけ。タイトルバーと映像のあいだに細い横棒）
func _build_trust_bar() -> void:
	if not use_phrases:
		return
	var bar_pos := Vector2(VIDEO_POS.x, VIDEO_POS.y - 8)
	var bar_size := Vector2(VIDEO_SIZE.x, 5)
	_panel(bar_pos, bar_size, Color(0.1, 0.1, 0.14))   # 背景（保持しない）
	trust_bar_fill = ColorRect.new()
	trust_bar_fill.position = bar_pos
	trust_bar_fill.size = Vector2(0, bar_size.y)   # 初期は空。_process で目標値に追従させる
	trust_bar_fill.color = Color(0.75, 0.3, 0.3)
	add_child(trust_bar_fill)
	# 信頼度の % 表示（ゲージ右側）
	trust_bar_label = Label.new()
	trust_bar_label.position = Vector2(bar_pos.x + bar_size.x - 60, bar_pos.y - 22)
	trust_bar_label.size = Vector2(56, 18)
	trust_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trust_bar_label.add_theme_font_size_override("font_size", 14)
	trust_bar_label.modulate = Color(0.85, 0.85, 0.95)
	add_child(trust_bar_label)


# 着信画面（応答するボタン）
func _build_call_panel() -> void:
	title_panel = _panel(VIDEO_POS, VIDEO_SIZE, Color(0.05, 0.06, 0.09, 0.96))
	_label(friend + (" の配信" if mode == "stream" else " から着信"), Vector2(0, 120), Vector2(750, 60), title_panel, 40).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var intro := "映像の背後に、何かが映ったら——\n映像をクリックして、警告してあげて。"
	if mode == "stream":
		intro = "配信の背後に、何かが映ったら——\n映像をクリックしてコメントを投稿して、配信者に知らせてあげて。"
	elif use_phrases:
		intro = "疑り深い相手。まずは話しかけて、信頼を築こう。\n背後に何かが映ったら、映像をクリックして、強く伝えて。"
	var sub := _label(intro, Vector2(0, 200), Vector2(750, 70), title_panel, 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.75, 0.85)
	var answer := _button("応答する  (Enter)", Vector2(275, 300), Vector2(200, 60), Color(0.15, 0.45, 0.25), title_panel)
	answer.pressed.connect(_start_call)


# 終了画面（結果の表情とリトライボタン）
func _build_end_panel() -> void:
	end_panel = _panel(VIDEO_POS, VIDEO_SIZE, Color(0, 0, 0, 0.78))
	end_panel.visible = false
	# 結果画面のヘッダー帯（メッセージ背景）
	var header_band := _panel(Vector2(0, 30), Vector2(750, 90), Color(0.0, 0.0, 0.0, 0.55), end_panel)
	end_label = _label("", Vector2(0, 50), Vector2(750, 60), end_panel, 44)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 表情表示（end_label の下。中央配置。end_panel の中央付近に大きめに）
	end_face = TextureRect.new()
	end_face.position = Vector2(0, 145)
	end_face.size = Vector2(750, 280)
	end_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	end_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	end_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_face.modulate.a = 0.0
	end_panel.add_child(end_face)
	end_sub = _label("", Vector2(0, 430), Vector2(750, 80), end_panel, 20)
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_sub.modulate = Color(0.8, 0.84, 0.9)
	retry_btn = _button("もう一度  (R)", Vector2(275, 530), Vector2(200, 56), Color(0.2, 0.22, 0.28), end_panel)
	retry_btn.pressed.connect(_after_end)


# --- 音（make_sounds.py で作った自作の効果音）-----------------------------------------

func _build_audio() -> void:
	audio = AudioMgrScript.new()
	add_child(audio)
	audio.setup()


func _play(name: String) -> void:
	audio.play(name)


# 全体・環境音・効果音の音量を反映する（バスごと）
func _apply_volume() -> void:
	audio.apply_volume(vol_master, vol_amb, vol_sfx)


func _load_settings() -> void:
	if not persist:
		return   # テスト用: 保存済みの設定でテストの結果が変わらないように
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) == OK:
		vol_master = c.get_value("audio", "master", 1.0)
		vol_amb = c.get_value("audio", "ambient", 0.8)
		vol_sfx = c.get_value("audio", "sfx", 1.0)
		calm = c.get_value("visual", "calm", false)
		reached = clampi(int(c.get_value("progress", "reached", 0)), 0, STAGE_FILES.size() - 1)
		difficulty = clampi(int(c.get_value("game", "difficulty", 2)), 0, DIFFICULTY_TABLE.size() - 1)


func _save_settings() -> void:
	if not persist:
		return
	var c := ConfigFile.new()
	c.set_value("progress", "reached", reached)
	c.set_value("audio", "master", vol_master)
	c.set_value("audio", "ambient", vol_amb)
	c.set_value("audio", "sfx", vol_sfx)
	c.set_value("visual", "calm", calm)
	c.set_value("game", "difficulty", difficulty)
	c.save(SETTINGS_PATH)


# 難易度テーブルに基づいて各値を適用する。_load_stage と _load_settings のあとに 1 回だけ呼ぶ
func _apply_difficulty() -> void:
	var d := clampi(difficulty, 0, DIFFICULTY_TABLE.size() - 1)
	var row: Array = DIFFICULTY_TABLE[d]
	max_false_alarms = row[0]
	false_alarm_lock = row[1]
	fail_at *= row[2]
	if belief_start < 1.0:
		belief_start = clampf(belief_start + float(row[3]), 0.05, 0.95)
	belief = belief_start
	if mode == "stream":
		need_warnings = maxi(2, need_warnings + int(row[4]))


# --- 一時停止（Esc）と音量 -------------------------------------------------------

func _build_pause_panel() -> void:
	pause_panel = _panel(Vector2.ZERO, Vector2(1280, 720), Color(0.04, 0.05, 0.07, 0.92))
	pause_panel.visible = false
	_label("一時停止", Vector2(0, 110), Vector2(1280, 60), pause_panel, 40).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rows := [["全体の音量", vol_master, 0], ["環境音（部屋の音・唸り・心音）", vol_amb, 1], ["効果音（通知・きしみ・悲鳴）", vol_sfx, 2]]
	for i in 3:
		var y := 230 + i * 80
		_label(rows[i][0], Vector2(340, y), Vector2(600, 30), pause_panel, 20)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = rows[i][1]
		sl.position = Vector2(340, y + 34)
		sl.size = Vector2(600, 24)
		sl.focus_mode = Control.FOCUS_NONE
		sl.value_changed.connect(_on_volume_changed.bind(rows[i][2]))
		pause_panel.add_child(sl)
	var cb := CheckBox.new()
	cb.text = "演出を弱める（画面の揺れ・点滅・映像の乱れ）"
	cb.button_pressed = calm
	cb.position = Vector2(340, 458)
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(_on_calm_toggled)
	pause_panel.add_child(cb)
	var resume := _button("再開  (Esc)", Vector2(540, 500), Vector2(200, 56), Color(0.15, 0.45, 0.25), pause_panel)
	resume.pressed.connect(_set_paused.bind(false))
	_label("難しさ: %s（変更はタイトル画面から）" % DIFFICULTY_NAMES[difficulty], Vector2(0, 575), Vector2(1280, 28), pause_panel, 18).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("音の聞こえ方は、ここで好みに調整できます（設定は保存されます）", Vector2(0, 610), Vector2(1280, 30), pause_panel, 16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_title_screen() -> void:
	title_screen = _panel(Vector2.ZERO, Vector2(1280, 720), Color(0.04, 0.05, 0.07, 1.0))
	title_shot = "--title-shot" in OS.get_cmdline_user_args()   # 撮影用: タイトル画面を撮って終了
	title_screen.visible = title_shot or (not title_done and not shot_mode and not ("--lunge-shot" in OS.get_cmdline_user_args()))
	_label("SCREENLIFE HORROR", Vector2(0, 150), Vector2(1280, 70), title_screen, 52).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("（仮題）画面の向こうの異変に、いちばん早く気づけ", Vector2(0, 232), Vector2(1280, 30), title_screen, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.75, 0.85)
	# 遊び方の要約（diegetic 風のメッセージ）
	var intro := _label("通話・配信の画面の向こうで何が起きているか——\n背後の異変に気づいて、彼女を守ってあげて。", Vector2(0, 268), Vector2(1280, 50), title_screen, 18)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.modulate = Color(0.78, 0.78, 0.85)
	# 難易度ボタン（サブタイトルと「はじめから」のあいだ）。見出し + 横並び 3 つ
	_label("難しさ", Vector2(0, 322), Vector2(1280, 28), title_screen, 18).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var diff_w := 120
	var diff_h := 40
	var diff_gap := 10
	var diff_total := diff_w * 3 + diff_gap * 2   # 380
	var diff_x := (1280 - diff_total) / 2          # 450。中央寄せ
	diff_btns.clear()
	for i in 3:
		var b := _button(DIFFICULTY_NAMES[i], Vector2(diff_x + i * (diff_w + diff_gap), 355), Vector2(diff_w, diff_h), Color(0.2, 0.22, 0.28), title_screen)
		b.pressed.connect(_on_difficulty_pressed.bind(i))
		diff_btns.append(b)
	_refresh_diff_btns()
	var y := 415   # 説明文と難易度ボタンが追加されたので位置調整
	var start := _button("はじめから", Vector2(500, y), Vector2(280, 56), Color(0.15, 0.45, 0.25), title_screen)
	start.pressed.connect(_title_start.bind(0))
	if reached > 0:
		var cont := _button("つづきから（ステージ%d）  (Enter)" % (reached + 1), Vector2(450, y + 64), Vector2(380, 56), Color(0.2, 0.22, 0.28), title_screen)
		cont.pressed.connect(_title_start.bind(reached))
		for i in reached + 1:
			var b := _button("ステージ%d" % (i + 1), Vector2(450 + i * 130, y + 130), Vector2(120, 44), Color(0.2, 0.22, 0.28), title_screen)
			b.pressed.connect(_title_start.bind(i))
	var quit_btn := _button("終了", Vector2(560, y + 196), Vector2(160, 44), Color(0.3, 0.14, 0.14), title_screen)
	quit_btn.pressed.connect(get_tree().quit)
	_label("Esc: 一時停止・音量　1・2・3: 伝え方　クリック: 危険を警告　F11: 全画面", Vector2(0, 690), Vector2(1280, 30), title_screen, 16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _on_difficulty_pressed(d: int) -> void:
	difficulty = d
	_refresh_diff_btns()
	_save_settings()


# 選んでいる難易度のボタンを明るくする
func _refresh_diff_btns() -> void:
	for i in diff_btns.size():
		diff_btns[i].modulate = Color(1.4, 1.4, 1.4) if i == difficulty else Color(1.0, 1.0, 1.0)


func _title_start(n: int) -> void:
	stage_no = n
	title_done = true
	_restart()


func _on_calm_toggled(on: bool) -> void:
	calm = on
	_save_settings()


func _on_volume_changed(v: float, which: int) -> void:
	match which:
		0: vol_master = v
		1: vol_amb = v
		2: vol_sfx = v
	_apply_volume()
	_save_settings()


func _set_paused(on: bool) -> void:
	paused = on
	pause_panel.visible = on
	audio.set_paused(on)


# --- ゲーム進行 -------------------------------------------------------------------

func _start_call() -> void:
	state = State.PLAYING
	t = 0.0
	title_panel.visible = false
	audio.stop("ring")
	audio.start_loops()
	_play("ping")
	if mode == "stream":
		hint_label.text = "伝え方を選び（1・2・3）、映像の怪しいものをクリックして警告コメント。映る前に騒ぐと荒らし扱い。同じ警告を%d回、%d秒以内に。" % [need_warnings, int(warn_window)]
	elif use_phrases:
		hint_label.text = "話しかけて（Enter）信頼をためてから、伝え方を選び（1・2・3）、怪しいものをクリック。「逃げて！」が一番強い。"
	else:
		hint_label.text = "怪しいものを、クリック！ 見えないうちにクリックすると信頼を失います。"


func _load_stage() -> void:
	for a in OS.get_cmdline_user_args():     # 撮影・確認用: -- --stage=2 でステージを指定
		if a.begins_with("--stage="):
			stage_no = int(a.substr(8)) - 1
	stage_no = clampi(stage_no, 0, STAGE_FILES.size() - 1)
	var d = JSON.parse_string(FileAccess.get_file_as_string(STAGE_FILES[stage_no]))
	if d == null:
		push_error("ステージ設定を読めません: " + STAGE_FILES[stage_no])
		return
	friend = d["friend"]
	assets = d["assets"]
	var b: Array = d["ghost_box"]
	ghost_box = Rect2(b[0], b[1], b[2], b[3])
	ghost_curve = d["ghost_curve"]
	fail_at = d["fail_at"]
	uneasy_at = d["uneasy_at"]
	creaks = d["creaks"]
	relief = d.get("relief", [])
	timeline = d["timeline"]
	idle_lines = d["idle"]
	var trust_lines: Dictionary = d.get("idle_trust", {})
	idle_trust_low = trust_lines.get("low", [])
	idle_trust_high = trust_lines.get("high", [])
	idle_trust_idx = 0
	trust_milestone_line = d.get("trust_milestone_line", "")
	trust_milestone_said = false
	miss_unseen = d["miss_unseen"]
	miss_wrong = d["miss_wrong"]
	saved_line = d["saved_line"]
	trust_lost_line = d["trust_lost_line"]
	timeout_line = d["timeout_line"]
	mode = d.get("mode", "call")
	viewer_base = d.get("viewer_base", 100)
	chatter_lines = d.get("chatter", [])
	warn_phrases = d.get("warn_phrases", [])
	need_warnings = d.get("need_warnings", 3)
	warn_window = d.get("warn_window", 20.0)
	belief_start = d.get("belief_start", 1.0)
	lures = d.get("lures", [])
	onboarding = d.get("onboarding", false)
	cue_first_seen = d.get("cue_first_seen", false)
	ghost_scale = d.get("ghost_scale", [1.0, 1.0])
	ghost_pivot = d.get("ghost_pivot", [512.0, 288.0])
	ghost_path = d.get("ghost_path", [])
	ghost_face = d.get("ghost_face", [])
	belief = belief_start
	doubt_lines = d.get("doubt", ["...またそうやって脅かす。", "え、ほんとに？ いたずらじゃなくて？"])
	use_phrases = mode != "stream" and belief_start < 1.0
	stage_d = d


func _has_next_stage() -> bool:
	return stage_no + 1 < STAGE_FILES.size()


# 終了後に進むステージ番号。救出なら次へ（最後まで救ったら最初へ）、失敗なら同じステージ
func _next_stage_no() -> int:
	if state == State.SAVED:
		return stage_no + 1 if _has_next_stage() else 0
	return stage_no


func _after_end() -> void:
	stage_no = _next_stage_no()
	_restart()


func _restart() -> void:
	get_tree().reload_current_scene()


func _say(who: String, text: String) -> void:
	var is_friend := who == friend
	# キャラ別の色・装飾（character-bible.md の性格の三軸に対応）
	var cs := _char_style(who)
	var deco := ""
	if is_friend and belief >= 0.6 - TRUST_EPS:
		# 信頼度が高いとき、キャラごとに違うハート・スタンプを添える
		deco = "  [color=#ff8db0]" + cs["stamp"][randi() % cs["stamp"].size()] + "[/color]"
	var name_color: String = cs["name_color"]
	var bubble_color: String = cs["bubble_color"]
	var text_color: String = cs["text_color"]
	var outline_color: String = cs["outline_color"]
	var align_tag := "" if is_friend else "[right]"
	var end_tag := "" if is_friend else "[/right]"
	var tm := int(t)
	var time_str := "%02d:%02d" % [(tm / 60) % 60, tm % 60]
	# 吹き出し形式の BBCode。親しげのとき左上にピンクの小さいハート 💗
	var heart := "[color=#ff8db0]💗[/color]  " if is_friend and belief >= TRUST_HIGH - TRUST_EPS else ""
	# outline= で視認性を上げる（暗い背景に薄いチャットが溶ける問題を緩和）
	# indent= で左寄せ時に余白を作って「吹き出し感」を出す
	var indent := "[indent=12]" if is_friend else "[indent=12]"
	var end_indent := "[/indent]"
	var line := "%s%s[bgcolor=%s][outline_color=%s][color=%s]%s[/color]%s  %s[/outline_color][color=%s]%s[/color]  [color=#888]%s[/color][/bgcolor]%s%s\n\n" % [
		align_tag, indent, bubble_color, outline_color, name_color, who, deco, heart, text_color, text, time_str, end_indent, end_tag
	]
	chat_log.append_text(line)
	if is_friend:
		_play("ping")
		# 計画 09: セリフの表示中、口を開ける
		mouth_open_until = maxf(mouth_open_until, t + 0.8)
		face_overlay.visible = true
		face_overlay.queue_redraw()


# キャラ別のチャットスタイル。`character-bible.md` の性格の三軸を色と装飾に反映
# who: 発言者名（friend / 自分 / 視聴者）
# 戻り値: name_color / bubble_color / text_color / outline_color / stamp（信頼度の高いとき添える）の dict
func _char_style(who: String) -> Dictionary:
	if who == friend:
		# 自分のキャラ。Mika / Aoi / ゆめ で色を差別化
		match friend:
			"Mika":
				# Mika: 明るい・元気。フレッシュなブルー寄りに
				return {
					"name_color": "#a8c8e8",
					"bubble_color": "#1f2c3a",
					"text_color": "#dde6f0",
					"outline_color": "#3a5070",  # バブルの枠線
					"stamp": ["💕", "🌸", "✨", "(//ω//)", "(>ω<)", "(≧▽≦)"]
				}
			"Aoi":
				# Aoi: 柔らか・甘え。ピンク寄りに
				return {
					"name_color": "#e8b0c8",
					"bubble_color": "#2a1f2c",
					"text_color": "#f0e0ea",
					"outline_color": "#70504a",
					"stamp": ["💕", "🌸", "💗", "(//ω//)", "(*ˊᗜˋ*)", "(>ω<)"]
				}
			"ゆめ":
				# ゆめ: 配信・元気。ビビッドなオレンジ系で
				return {
					"name_color": "#e8c890",
					"bubble_color": "#2c2818",
					"text_color": "#f0e8d8",
					"outline_color": "#705a40",
					"stamp": ["💕", "🌸", "✨", "(≧▽≦)", "(*≧▽≦)", "(>ω<)"]
				}
			_:
				# デフォルト（後方互換）
				return {
					"name_color": "#a8b8d0",
					"bubble_color": "#2a2d36",
					"text_color": "#dde2ea",
					"outline_color": "#3e4250",
					"stamp": ["💕", "🌸", "✨", "(//ω//)", "(>ω<)"]
				}
	else:
		# 自分 / 視聴者。元の挙動を維持
		return {
			"name_color": "#e0c8a0",
			"bubble_color": "#3a3220",
			"text_color": "#f0e0c8",
			"outline_color": "#5a4838",
			"stamp": []
		}


# 人影の濃さを時間割（ghost_curve）から求める。ちらつきや緩和は含めない素の値
func _curve_alpha(time: float) -> float:
	for i in range(1, ghost_curve.size()):
		var a: Array = ghost_curve[i - 1]
		var b: Array = ghost_curve[i]
		if time <= b[0]:
			var k := inverse_lerp(a[0], b[0], time)
			return lerpf(a[1], b[1], k)
	return ghost_curve[-1][1]


# 緩和の時間帯の中では 0、前後 0.8 秒で 1 ↔ 0 を直線で変える。時間帯の外は 1
func _relief_factor(time: float) -> float:
	if relief.size() == 0:
		return 1.0
	var f := 1.0
	for w in relief:
		var a: float = float(w[0])
		var b: float = float(w[1])
		var local := 1.0
		if time < a - 0.8 or time > b + 0.8:
			local = 1.0
		elif time < a:
			local = 1.0 - inverse_lerp(a - 0.8, a, time)
		elif time <= b:
			local = 0.0
		else:
			local = inverse_lerp(b, b + 0.8, time)
		f = minf(f, local)
	return f


# 人影の実際の濃さ（時間割の濃さに緩和を掛ける）。表示・判定の基準値
func _ghost_alpha_at(time: float) -> float:
	return _curve_alpha(time) * _relief_factor(time)


# 人影が「映った」と扱われる最初の時刻（秒）。緩和を含めない時間割の濃さで判定する
func _first_seen_time() -> float:
	var x := 0.0
	while x < fail_at:
		if _curve_alpha(x) >= SEEN_THRESHOLD:
			return x
		x += 0.5
	return fail_at


# 人影の道筋（ghost_path）の指定時刻での (dx, dy) ピクセルずれ。キー間は smoothstep で補間する
# ghost_path が空なら (0, 0)。範囲の外は、最初／最後のキーの値をそのまま返す
func ghost_offset_at(time: float) -> Vector2:
	if ghost_path.size() == 0:
		return Vector2.ZERO
	if time <= float(ghost_path[0][0]):
		return Vector2(float(ghost_path[0][1]), float(ghost_path[0][2]))
	if time >= float(ghost_path[-1][0]):
		return Vector2(float(ghost_path[-1][1]), float(ghost_path[-1][2]))
	for i in range(1, ghost_path.size()):
		var b: Array = ghost_path[i]
		if time <= float(b[0]):
			var a: Array = ghost_path[i - 1]
			var k := inverse_lerp(float(a[0]), float(b[0]), time)
			var s := smoothstep(0.0, 1.0, k)
			return Vector2(lerpf(float(a[1]), float(b[1]), s), lerpf(float(a[2]), float(b[2]), s))
	return Vector2.ZERO


# 人影の道筋（ghost_path）の指定時刻での大きさ倍率。ghost_path が空なら 1.0
func ghost_mult_at(time: float) -> float:
	if ghost_path.size() == 0:
		return 1.0
	if time <= float(ghost_path[0][0]):
		return float(ghost_path[0][3])
	if time >= float(ghost_path[-1][0]):
		return float(ghost_path[-1][3])
	for i in range(1, ghost_path.size()):
		var b: Array = ghost_path[i]
		if time <= float(b[0]):
			var a: Array = ghost_path[i - 1]
			var k := inverse_lerp(float(a[0]), float(b[0]), time)
			var s := smoothstep(0.0, 1.0, k)
			return lerpf(float(a[3]), float(b[3]), s)
	return 1.0


# いまの人影の当たり判定範囲（ghost_box を ghost_offset_at(t) だけ平行移動した Rect2）
func ghost_box_now() -> Rect2:
	var o := ghost_offset_at(t)
	return Rect2(ghost_box.position + o, ghost_box.size)


func _on_video_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_video_click(event.position / VIDEO_SIZE * Vector2(SCENE_W, SCENE_H))
	elif event is InputEventScreenTouch and event.pressed:
		# モバイル Web: Godot はマウスイベントも吐くが、明示的にも拾う（DPI 差分を吸収）
		_on_video_click(event.position / VIDEO_SIZE * Vector2(SCENE_W, SCENE_H))


# 映像クリックの入口。通話は場所を指して _on_warn を、配信はクリック位置を _on_comment に渡す
func _on_video_click(scene_pos: Vector2) -> void:
	if state != State.PLAYING:
		return
	_set_mark(scene_pos)
	if mode == "stream":
		_on_comment(selected_phrase, scene_pos)
	else:
		_on_warn(selected_phrase)


# 伝え方を選ぶ（use_phrases のステージだけ。範囲外は無視）
func _select_phrase(i: int) -> void:
	if not use_phrases:
		return
	if i < 0 or i >= len(PHRASES):
		return
	selected_phrase = i
	_update_phrase_btns()


# 選ばれている伝え方のボタンを明るくする（ロック中・誤警告中でも無効化しない）
# 選択中のボタンには「▶」マーカーを先頭に付けて、選択中であることを明確にする
func _update_phrase_btns() -> void:
	for i in len(act_btns):
		var b: Button = act_btns[i] as Button
		b.modulate = Color(1.4, 1.4, 1.5) if i == selected_phrase else Color(1.0, 1.0, 1.0)
		# 選択マーカー。テキストの先頭に ▶ を付ける（stage2/3 の PHRASES のみ）
		if b.text.begins_with("▶") or b.text.begins_with("  "):
			b.text = b.text.substr(2)
		if i == selected_phrase:
			b.text = "▶ " + b.text


func _set_mark(scene_pos: Vector2) -> void:
	has_mark = true
	mark_scene = scene_pos
	marker.position = VIDEO_POS + scene_pos / Vector2(SCENE_W, SCENE_H) * VIDEO_SIZE
	marker.visible = true
	marker.modulate.a = 1.0   # 前回のフェード後に再クリックしても見えるよう alpha を戻す
	marker.queue_redraw()
	marker.scale = Vector2(1.6, 1.6)   # 指した瞬間に少し大きく、すぐ収まる
	create_tween().tween_property(marker, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 0.4 秒後に自動で消す（救出時は _finish が marker を残し、結果画面が上に被さる）
	create_tween().tween_property(marker, "modulate:a", 0.0, 0.25).set_delay(0.4)


func _on_talk() -> void:
	if state != State.PLAYING or mode == "stream" or talk_left > 0.0:
		return
	_say("あなた", "うん、聞いてるよ。")
	var belief_now := belief   # 話しかけの効果を足す前の値で、信頼度による台詞分岐を判断する
	if use_phrases and idle_trust_low.size() > 0 and idle_trust_high.size() > 0:
		var trust_pick: Array = idle_trust_high if belief_now >= TRUST_HIGH - TRUST_EPS else idle_trust_low
		_say(friend, trust_pick[idle_trust_idx % trust_pick.size()])
		idle_trust_idx += 1
	elif idle_lines.size() > 0:
		_say(friend, idle_lines[idle_idx % idle_lines.size()])
		idle_idx += 1
	belief = minf(1.0, belief + TALK_TRUST)
	# 信頼が初めて 0.6 を超えた瞬間だけ、一言と合図を出す（疑う相手のステージだけ）
	if use_phrases and not trust_milestone_said and belief >= TRUST_HIGH - TRUST_EPS and trust_milestone_line != "":
		_say(friend, trust_milestone_line)
		hint_label.text = "信頼が高まった。警告が通りやすくなる。"
		trust_milestone_said = true
	talk_left = TALK_COOLDOWN


func _on_warn(phrase := 0) -> void:
	if state != State.PLAYING or lock_left > 0.0 or mode == "stream":
		return
	if not has_mark:
		hint_label.text = "映像をクリックして、警告しよう。"
		return
	# 緩和で消えている間（時間割では映っているはずなのに、実際は映っていない）: 警告しても罰しない
	if _curve_alpha(t) >= SEEN_THRESHOLD and _ghost_alpha_at(t) < SEEN_THRESHOLD:
		hint_label.text = "人影が消えた…。また現れるはず。"
		lock_left = 1.0
		return
	_play("send")
	_say("あなた", PHRASES[phrase] if use_phrases else "そこ！ 後ろ、見て！")
	var seen := _ghost_alpha_at(t) >= SEEN_THRESHOLD
	if seen and ghost_box_now().has_point(mark_scene):
		# 信じてもらえるか: 信頼 + 人影の濃さ + 伝え方の強さ。足りなければ流されるが、誤警告にはならない
		# 濃さは時間割どおりの値で評価（ちらつきに影響されない）
		var score: float = belief + _ghost_alpha_at(t) * 0.8 + float(PHRASE_BONUS[phrase])
		if belief_start < 1.0 and score < 1.0:
			belief = minf(1.0, belief + DOUBT_GAIN)
			lock_left = 2.0
			_say(friend, doubt_lines.pick_random())
			hint_label.text = "信頼が足りなかった。話しかけて信頼をためるか、「逃げて！」で強く伝えよう。"
			return
		_say(friend, saved_line)
		_finish(State.SAVED, "救出成功", Color(0.6, 1.0, 0.7))
		return
	false_alarms += 1
	hint_label.text = "人影の場所が違った。人影そのものを指そう。" if seen else "まだ何も映っていなかった。見えてから警告しよう。"
	has_mark = false
	marker.visible = false
	lock_left = false_alarm_lock
	if false_alarms >= max_false_alarms:
		_say(friend, trust_lost_line)
		_finish(State.FAILED, "信頼を失った", Color(1.0, 0.45, 0.45))
	elif seen:
		_say(friend, miss_wrong.pick_random())
	else:
		_say(friend, miss_unseen.pick_random())
		flash.color = Color(1, 1, 1, 0.12)


# 配信：警告コメントを投稿する。人影が映っている間に必要な数がそろえば、配信者が気づく
# pos: クリック経由のとき映像内の位置（Vector2）。null なら従来どおり位置を問わない（テスト・ボット互換）
func _on_comment(i: int, pos: Variant = null) -> void:
	if state != State.PLAYING or lock_left > 0.0 or mode != "stream":
		return
	_say("あなた", warn_phrases[i])
	_play("send")
	# クリック経由: 人影が映っていても、ghost_box の外をクリックしたら誤警告（荒らし扱い）
	if pos != null and _ghost_alpha_at(t) >= SEEN_THRESHOLD and not ghost_box_now().has_point(pos):
		false_alarms += 1
		hint_label.text = "人影の場所が違った。人影そのものをクリックしよう。"
		has_mark = false
		marker.visible = false
		lock_left = false_alarm_lock
		if false_alarms >= max_false_alarms:
			_say(friend, trust_lost_line)
			_finish(State.FAILED, "荒らし扱いされた", Color(1.0, 0.45, 0.45))
		else:
			_say(friend, miss_wrong.pick_random())
			flash.color = Color(1, 1, 1, 0.12)
		return
	# 緩和で消えている間（時間割では映っているはずなのに、実際は映っていない）: 荒らし扱いしない
	if _curve_alpha(t) >= SEEN_THRESHOLD and _ghost_alpha_at(t) < SEEN_THRESHOLD:
		hint_label.text = "人影が消えた…。また現れるはず。"
		lock_left = 1.0
		return
	# 映っているかの判定は時間割どおりの濃さ（ちらつきに影響されない）
	if _ghost_alpha_at(t) >= SEEN_THRESHOLD:
		warn_times.append(t)
		warn_times = warn_times.filter(func(x: float) -> bool: return t - x <= warn_window)
		if warn_times.size() >= need_warnings:
			_say(friend, saved_line)
			_finish(State.SAVED, "配信者に伝わった", Color(0.6, 1.0, 0.7))
		else:
			_say(friend, miss_wrong.pick_random())
			hint_label.text = "警告コメントが %d / %d 回。もう少し重ねよう。" % [warn_times.size(), need_warnings]
			_viewer_echo(true)
		return
	false_alarms += 1
	hint_label.text = "まだ何も映っていなかった。映ってから、同じ警告を重ねよう。"
	_viewer_echo(false)
	lock_left = false_alarm_lock
	if false_alarms >= max_false_alarms:
		_say(friend, trust_lost_line)
		_finish(State.FAILED, "荒らし扱いされた", Color(1.0, 0.45, 0.45))
	else:
		_say(friend, miss_unseen.pick_random())
		flash.color = Color(1, 1, 1, 0.12)


# 配信: 警告コメントのあと、視聴者が少し遅れて反応する。本物なら同調、嘘なら荒らし扱い
func _viewer_echo(real: bool) -> void:
	var lines: Array = ["え、うしろ…？", "ほんとだ、何かいる…", "え、待って怖い", "私も見えた、壁のとこ"] if real \
			else ["またかよw", "釣りか？", "ネタ？", "うるさいなあ"]
	for i in 2:
		get_tree().create_timer(0.8 + i * 1.1).timeout.connect(func() -> void:
			if state == State.PLAYING:
				_say_viewer(lines.pick_random()))


func _say_viewer(text: String) -> void:
	var names := ["ゆう", "kai_", "のの", "たろう", "MM", "ぱんだ", "ひなた"]
	chat_log.append_text("[color=#8a9]%s[/color]  %s\n" % [names.pick_random(), text])


func _finish(new_state: State, message: String, color: Color) -> void:
	state = new_state
	end_label.text = message
	end_label.modulate = color
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	# 結果画面の表情（end_label の下）
	if new_state == State.SAVED:
		end_face.texture = react_tex.get("saved", react_tex.get("happy"))
		end_face.modulate = Color(0.85, 1.0, 0.9, 0.0)
	else:
		end_face.texture = react_tex.get("failed", react_tex.get("terror"))
		end_face.modulate = Color(1.0, 0.75, 0.75, 0.0)
	if new_state == State.FAILED:
		# 襲いかかり中は result 画面のフェードを遅らせる（lunge 完了 + 0.5 秒待ってから 0.5 秒で出す）
		lunge = 0.0
		var lunge_time := 0.6 if calm else 0.35
		var tt := create_tween()
		tt.tween_interval(lunge_time + 0.5)
		tt.tween_property(end_panel, "modulate:a", 1.0, 0.5)
		tt.parallel().tween_property(end_face, "modulate:a", 1.0, 0.5)
	else:
		var tt2 := create_tween()
		tt2.tween_property(end_panel, "modulate:a", 1.0, 0.5)
		tt2.parallel().tween_property(end_face, "modulate:a", 1.0, 0.5)
	end_sub.text = "%02d:%02d   誤警告 %d回" % [int(t) / 60, int(t) % 60, false_alarms]
	if use_phrases:
		end_sub.text += "   信頼 %d%%" % int(belief * 100.0)
	if new_state == State.FAILED:   # 失敗の理由と、人影が映り始めた時刻を伝える（学べるように）
		var seen_at := int(_first_seen_time())
		if false_alarms >= max_false_alarms:
			end_sub.text += "\n映る前や場所違いの警告は、信頼を失う。人影が映るのは約%d秒から。" % seen_at
		else:
			end_sub.text += "\n人影は約%d秒から映っていた。次は早めに目を凝らそう。" % seen_at
	if new_state == State.SAVED:
		reached = maxi(reached, mini(stage_no + 1, STAGE_FILES.size() - 1))
		_save_settings()
		retry_btn.text = "次の通話へ  (Enter)" if _has_next_stage() else "最初から  (Enter)"
		if not _has_next_stage():
			end_label.text = "すべての通話を救出した"
	typing_label.visible = false
	marker.visible = false
	if new_state == State.FAILED:
		shake_left = 1.0
		flash.color = Color(1, 0, 0, 0.45)
		_play("lunge")   # プラン 13: 風切り + インパクト + 叫びの合成 SE
	else:
		flash.color = Color(1, 1, 1, 0.35)
		_play("relief")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if title_screen != null and title_screen.visible:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_title_start(reached)
		return
	match event.keycode:
		KEY_ESCAPE:
			if state == State.PLAYING or paused:
				_set_paused(not paused)
			return
		KEY_SPACE:
			pass   # 警告は映像クリックでのみ出す。Space は誤操作を避けるため何もしない
		KEY_1, KEY_2, KEY_3:
			if mode == "stream" or use_phrases:
				_select_phrase(event.keycode - KEY_1)
		KEY_ENTER, KEY_KP_ENTER:
			match state:
				State.TITLE:
					_start_call()
				State.PLAYING:
					_on_talk()
				_:
					_after_end()
		KEY_R:
			if state == State.SAVED or state == State.FAILED:
				_after_end()


func _process(delta: float) -> void:
	if title_shot:
		shot_frame += 1
		if shot_frame == 5:
			_save("shot_h_title.png")
			get_tree().quit()
		return
	if lunge_shot:
		shot_frame += 1
		if shot_frame == 45:
			_save("shot_i_lunge.png")
			get_tree().quit()
	# 計画 08: タスクバーの時計（毎秒）、REC ラベル（毎秒）、通話品質バー（毎秒）
	var now_sec := int(Time.get_ticks_msec() / 1000.0)
	if now_sec != _taskbar_last:
		_taskbar_last = now_sec
		_refresh_taskbar_clock()
		_refresh_rec_label()
		_refresh_call_bars()
		# LIVE バッジの点滅（Label 化済み。modulate.a を変える）
		if live_badge != null:
			var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * TAU)
			live_badge.modulate.a = blink
	# 計画 09: 口パクと瞬き
	if state == State.PLAYING and face_overlay != null:
		_update_face_overlay(delta)
	if paused:
		if shot_mode:
			shot_frame += 1
			if shot_frame == 210:
				_save("shot_g_pause.png")
				get_tree().quit()
		return
	if shot_mode:
		_shot_step()
	elif state == State.PLAYING:
		t += delta
	if state == State.PLAYING:
		lock_left = maxf(0.0, lock_left - delta)
		talk_left = maxf(0.0, talk_left - delta)
		while timeline_idx < timeline.size() and t >= timeline[timeline_idx][0]:
			_say(friend, timeline[timeline_idx][1])
			timeline_idx += 1
		while creak_idx < creaks.size() and t >= creaks[creak_idx]:
			_play("creak")
			if not calm:
				dim_left = 0.3   # きしみに合わせて映像を 0.3 秒だけ素早く暗転させる
			creak_idx += 1
		while relief_idx < relief.size() and t >= float(relief[relief_idx][1]):
			_play("creak")
			if not calm:
				dim_left = 0.3   # 緩和から戻る瞬間にもきしみを入れるので、同じく暗転をトリガする
			relief_idx += 1
		if t >= fail_at:
			_say(friend, timeout_line)
			_finish(State.FAILED, "救えなかった", Color(1.0, 0.45, 0.45))

	# 配信：視聴者のコメントが流れ続ける
	if mode == "stream" and state == State.PLAYING and chatter_lines.size() > 0:
		chatter_timer -= delta
		if chatter_timer <= 0.0:
			chatter_timer = randf_range(1.2, 2.8)
			_say_viewer(chatter_lines.pick_random())

	# 相手の「入力中」表示
	typing_label.visible = state == State.PLAYING and timeline_idx < timeline.size() \
			and timeline[timeline_idx][0] - t <= TYPING_LEAD

	# 人影の濃さ: 救出後は素早く消える。失敗後は最大のまま
	var target := _ghost_alpha_at(t)
	if state == State.SAVED:
		target = 0.0
	elif state == State.FAILED:
		target = 1.0
	# 人影が濃くなるほど近づいて（大きく）見える。失敗後は最も近い
	# 緩和の影響を受けない（消えて戻ったとき、前より大きくなる）
	var approach := 1.0 if state == State.FAILED else clampf(_curve_alpha(t), 0.0, 1.0)
	var base_scale := lerpf(float(ghost_scale[0]), float(ghost_scale[1]), approach) * ghost_mult_at(t)
	# 失敗の襲いかかり（lunge）: 0.35 秒（calm なら 0.6 秒）で大きさを最大 2.6 倍 / 1.4 倍にする
	if state == State.FAILED:
		var lunge_time := 0.6 if calm else 0.35
		lunge = move_toward(lunge, 1.0, delta / lunge_time)
	if lunge > 0.0:
		var max_scale := 1.4 if calm else 2.6
		base_scale *= lerpf(1.0, max_scale, lunge)
	ghost_layer.scale = Vector2.ONE * base_scale
	var cur := ghost_layer.modulate.a
	if state == State.PLAYING:
		var alpha := clampf(target * (0.85 + 0.15 * sin(t * 9.0)), 0.0, 1.0) if target > 0.0 else 0.0
		# コマ落ち演出: 0.07 秒だけ濃さを半分にする
		if not calm and stutter_left > 0.0:
			alpha *= 0.5
		ghost_layer.modulate.a = alpha
	else:
		ghost_layer.modulate.a = move_toward(cur, target, delta * 1.5)

	# 人影の位置: 道筋（ghost_path）+ 揺れ + コマ落ち。失敗の襲いかかり中は中心へ寄せる
	var path_offset := ghost_offset_at(t)
	var shake_offset := Vector2.ZERO
	if not calm:
		var clock := Time.get_ticks_msec() / 1000.0
		shake_offset = Vector2(sin(clock * 0.8) * 2.0, sin(clock * 1.3) * 1.5) * _curve_alpha(t)
	var stutter_pos := Vector2.ZERO
	if not calm and _curve_alpha(t) >= 0.5:   # プラン 13: 0.3→0.5 に上げて頻度を半減
		if stutter_left > 0.0:
			stutter_left = maxf(0.0, stutter_left - delta)
			stutter_pos = stutter_offset
		elif stutter_next <= 0.0:
			stutter_left = 0.07
			stutter_offset = Vector2(randf_range(-4, 4), randf_range(-4, 4))   # ±6→±4 に縮小
			stutter_next = randf_range(1.5, 3.5)   # 0.6-2.0→1.5-3.5 に増やして頻度減
			stutter_pos = stutter_offset
		else:
			stutter_next = maxf(0.0, stutter_next - delta)
	else:
		stutter_left = 0.0
		stutter_next = 0.0
	var base_pos := path_offset + shake_offset + stutter_pos
	if lunge > 0.0:
		# 襲いかかり: 足元(ghost_pivot)を中心に大きくなるので、顔（箱の上寄り）が映像の中心付近に来るよう、
		# 位置を毎フレーム求め直す。顔の描画位置 = 位置 + 中心 + 大きさ * (顔 - 中心)  を、目標に合わせる
		var pivot := Vector2(float(ghost_pivot[0]), float(ghost_pivot[1]))
		var head := ghost_box.position + Vector2(ghost_box.size.x * 0.5, ghost_box.size.y * 0.22)
		if ghost_face.size() == 2:
			head = Vector2(float(ghost_face[0]), float(ghost_face[1]))
		var target_pos := Vector2(SCENE_W * 0.5, SCENE_H * 0.42)
		var desired := target_pos - pivot - ghost_layer.scale.x * (head - pivot)
		ghost_layer.position = base_pos.lerp(desired, lunge * lunge)
	else:
		ghost_layer.position = base_pos

	# 相手の表情の切り替え（クロスフェード）
	_set_react(_react_target())
	if react_top.texture:
		react_top.modulate.a = move_toward(react_top.modulate.a, 1.0, delta * react_speed)
		if react_top.modulate.a >= 1.0:
			react_bottom.modulate.a = 0.0
	else:
		react_bottom.modulate.a = move_toward(react_bottom.modulate.a, 0.0, delta * react_speed)

	# 信頼ゲージ（use_phrases のステージだけ。判定は変えずに、見た目だけ追従させる）
	if trust_bar_fill:
		var target_w := VIDEO_SIZE.x * belief
		trust_bar_fill.size.x = move_toward(trust_bar_fill.size.x, target_w, delta * VIDEO_SIZE.x * 0.5)
		# 色: belief に応じて赤 → 琥珀 → 緑へ、なめらかに lerp する
		var red := Color(0.75, 0.3, 0.3)
		var amber := Color(0.85, 0.65, 0.25)
		var green := Color(0.35, 0.75, 0.5)
		var t1 := clampf(belief / 0.5, 0.0, 1.0)
		var t2 := clampf((belief - 0.5) / 0.3, 0.0, 1.0)
		trust_bar_fill.color = red.lerp(amber, t1).lerp(green, t2)
		# % 表示を更新（信頼度 60% を超えたら色も少し明るく）
		if trust_bar_label:
			trust_bar_label.text = "%d%%" % int(round(belief * 100))
			# 60% 超は親しみ、30% 以下は警告色
			if belief >= TRUST_HIGH - TRUST_EPS:
				trust_bar_label.modulate = Color(1.0, 0.9, 0.95)
			elif belief <= 0.3:
				trust_bar_label.modulate = Color(1.0, 0.6, 0.6)
			else:
				trust_bar_label.modulate = Color(0.85, 0.85, 0.95)

	# 音: 唸り・心音・環境音のこもり（人影が濃いほど強い）。人影の左右位置をパンに反映する
	var pan := clampf((ghost_box_now().get_center().x / SCENE_W) * 2.0 - 1.0, -1.0, 1.0) * 0.6
	audio.update(delta, ghost_layer.modulate.a, state == State.PLAYING, state == State.SAVED, pan)

	# 映像を生きたものに見せる: ごくわずかな拡大・揺れ。失敗時は大きく揺らす
	var s := 1.0 + 0.006 * sin(t * 0.7)
	stage.scale = Vector2(s, s)
	stage.position = Vector2(sin(t * 0.9) * 1.5, cos(t * 1.3) * 1.0)
	shake_left = maxf(0.0, shake_left - delta * 1.4)
	var clock := Time.get_ticks_msec() / 1000.0   # 失敗後は t が止まるので、実時間で揺らす
	var shake := shake_left * shake_left
	video.position = VIDEO_POS + Vector2(sin(clock * 53.1) + sin(clock * 31.7), cos(clock * 47.3) + cos(clock * 29.9)) * 0.5 * 22.0 * shake
	flash.color.a = move_toward(flash.color.a, 0.0, delta * 0.9)
	cam_mat.set_shader_parameter("time", t)
	# 映像の乱れ: 人影が濃くなるほど強い。プラン 13（過剰演出削減）:
	# ghost alpha 0.4 までは出さない、0.4〜1.0 で 0.0〜0.5（半減）。stutter も同条件
	var glitch_amt := 0.0 if calm else clampf((ghost_layer.modulate.a - 0.4) / 0.6, 0.0, 0.5)
	cam_mat.set_shader_parameter("glitch", glitch_amt)
	# きしみに合わせた暗転（dim）: 0.3 秒だけ素早く点滅させて 0 に戻す。calm では常に 0
	var dim := 0.0
	if not calm and dim_left > 0.0:
		var dim_elapsed := 0.3 - dim_left
		dim = 0.5 * (0.5 + 0.5 * sin(dim_elapsed * 60.0))
		dim_left = maxf(0.0, dim_left - delta)
	cam_mat.set_shader_parameter("dim", dim)
	if calm:
		shake_left = 0.0
		flash.color.a = minf(flash.color.a, 0.12)

	# 練習ステージだけ: 人影が初めて映った瞬間に、音と短いヒントで知らせる（遊びながら覚える）
	if state == State.PLAYING and not seen_cue_played and ghost_layer.modulate.a >= SEEN_THRESHOLD:
		seen_cue_played = true
		if cue_first_seen:
			_play("creak")
		if onboarding:
			hint_label.text = "背後の暗がりに、何か…？ 気になるものを、クリック！"

	# ヒントは出してから9秒たつと、うっすら消える（邪魔にならず、新しいヒントではまた濃く出る）
	if hint_label.text != last_hint:
		last_hint = hint_label.text
		hint_age = 0.0
	else:
		hint_age += delta
	hint_label.modulate.a = 1.0 if hint_age < 9.0 else move_toward(hint_label.modulate.a, 0.4, delta * 0.5)

	# 表示
	if mode == "stream":
		viewers = viewer_base + int(sin(t * 0.5) * 8.0) + int(clampf(ghost_layer.modulate.a, 0.0, 1.0) * 60.0)
		timer_label.text = "視聴者 %d" % viewers
	else:
		timer_label.text = "%02d:%02d" % [int(t) / 60, int(t) % 60]
	status_label.text = "誤警告 %d/%d" % [false_alarms, max_false_alarms]
	if use_phrases:
		status_label.text += "   信頼 %d%%" % int(belief * 100.0)
	var can_act := state == State.PLAYING
	var locked := lock_left > 0.0
	var notes := []
	if locked:
		notes.append("警告できるまで あと %d 秒" % ceili(lock_left))
	if mode != "stream" and talk_left > 0.0:
		notes.append("話しかけ直せるまで あと %d 秒" % ceili(talk_left))
	lock_label.text = "   /   ".join(PackedStringArray(notes))
	# act_btns（stage2/3 の選択用）はいつでも押せる。ロック中・誤警告中でも選択だけは無効化しない
	if mode != "stream":
		talk_btn.disabled = not can_act or talk_left > 0.0


# --- 画像確認用（-- --shot）---------------------------------------------------------

func _shot_step() -> void:
	shot_frame += 1
	# 撮影の t は 70（むずかしい difficulty でも fail_at=78.2 を超えない）
	var plan := {10: ["shot_a_t02.png", 2.0], 20: ["shot_f_lure.png", 34.0], 40: ["shot_b_t45.png", 45.0], 70: ["shot_e_t60.png", 60.0], 100: ["shot_c_t85.png", 70.0]}
	for f in plan:
		if shot_frame == f - 1:
			t = plan[f][1]
			# 撮影用: 時間を飛ばすので、表情の切り替えも待たずに完了させる
			_set_react(_react_target())
			if react_top.texture:
				react_top.modulate.a = 1.0
				react_bottom.modulate.a = 0.0
		if shot_frame == f:
			_save(plan[f][0])
	if shot_frame == 105:
		_set_mark(ghost_box.get_center())
		_on_warn(1)
	if shot_frame == 199:
		# 救出の終盤を確実に撮る。フレーム 199 で組み立て、フレーム 201 で save（描画反映後）
		state = State.SAVED
		end_label.text = "救出成功"
		end_label.modulate = Color(0.6, 1.0, 0.7)
		end_panel.visible = true
		end_panel.modulate.a = 1.0
		end_face.texture = react_tex.get("saved", react_tex.get("happy"))
		end_face.modulate = Color(0.85, 1.0, 0.9, 1.0)
		end_sub.text = "01:10   誤警告 0回   信頼 25%"
	if shot_frame == 201:
		_save("shot_d_saved.png")
	if shot_frame == 202:
		_set_paused(true)
	if shot_frame == 201:
		_set_paused(true)   # 一時停止画面の撮影（停止中は _process の先頭で数える）


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://outputs/" + ("" if stage_no == 0 else "s%d_" % (stage_no + 1)) + name))

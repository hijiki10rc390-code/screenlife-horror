extends Node
# 音の管理（main.gd から分離）。
#   バス Ambient = 環境音・唸り・心音 / Sfx = 効果音。音量はバスごとに調整する。
#   環境音: 人影が濃いほど高音が削れて「こもる」（ローパスフィルター）。息苦しさを出す。
#   効果音: 小部屋の残響を少し掛けて、空間に馴染ませる。

const AMBIENT := "Ambient"
const SFX := "Sfx"

# 名前: [ファイル, 基準の大きさ(dB), ループするか, バス]
const FILES := {
	"ambient": ["res://assets/sound/ambient_room.wav", -6.0, true, AMBIENT],
	"drone": ["res://assets/sound/drone.wav", -60.0, true, AMBIENT],
	"heart": ["res://assets/sound/heart.wav", -60.0, true, AMBIENT],
	"ping": ["res://assets/sound/ping.wav", -8.0, false, SFX],
	"creak": ["res://assets/sound/creak.wav", -12.0, false, SFX],
	"scream": ["res://assets/sound/scream.wav", -2.0, false, SFX],
	"lunge": ["res://assets/sound/lunge.wav", -3.0, false, SFX],   # プラン 13: 風切り + インパクト + 叫びの合成 SE（少し控えめ）
	"relief": ["res://assets/sound/relief.wav", -8.0, false, SFX],
	"send": ["res://assets/sound/send.wav", -10.0, false, SFX],
	"ring": ["res://assets/sound/ring.wav", -16.0, true, SFX],
}

var players := {}
var lowpass: AudioEffectLowPassFilter
var ambient_pan: AudioEffectPanner   # 環境音バスのパンナー（人影の左右位置）
var sfx_pan: AudioEffectPanner       # 効果音バスのパンナー


func setup() -> void:
	var amb := _ensure_bus(AMBIENT)
	var sfx := _ensure_bus(SFX)
	# 画面の再読み込みでバスは残るので、効果は最初の1回だけ足す
	if AudioServer.get_bus_effect_count(amb) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 16000.0
		AudioServer.add_bus_effect(amb, lp)
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.25
		rv.wet = 0.12
		rv.dry = 0.9
		AudioServer.add_bus_effect(sfx, rv)
	# パンナー: 既にある効果の後ろに足す（バスの再読み込みで重複しないよう、最後が Panner かで確かめる）
	ambient_pan = _ensure_panner(amb)
	sfx_pan = _ensure_panner(sfx)
	lowpass = AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter
	for name in FILES:
		players[name] = _player(FILES[name])


func _ensure_panner(bus: int) -> AudioEffectPanner:
	var n := AudioServer.get_bus_effect_count(bus)
	if n > 0 and AudioServer.get_bus_effect(bus, n - 1) is AudioEffectPanner:
		return AudioServer.get_bus_effect(bus, n - 1) as AudioEffectPanner
	var p := AudioEffectPanner.new()
	p.pan = 0.0
	AudioServer.add_bus_effect(bus, p)
	return p


func _ensure_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


func _player(spec: Array) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: AudioStream = load(spec[0])
	if spec[2] and s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2   # 16bit・モノラルなので、バイト数の半分がサンプル数
	p.stream = s
	p.volume_db = spec[1]
	p.bus = spec[3]
	add_child(p)
	return p


func db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


# 全体・環境音・効果音の音量（0〜1）を反映する
func apply_volume(master: float, ambient: float, sfx: float) -> void:
	AudioServer.set_bus_volume_db(0, db(master))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AMBIENT), db(ambient))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX), db(sfx))


func play(name: String) -> void:
	if players.has(name):
		(players[name] as AudioStreamPlayer).play()


func stop(name: String) -> void:
	if players.has(name):
		(players[name] as AudioStreamPlayer).stop()


func start_loops() -> void:
	for name in ["ambient", "drone", "heart"]:
		play(name)


func set_paused(on: bool) -> void:
	for name in players:
		(players[name] as AudioStreamPlayer).stream_paused = on


# 毎フレーム: 人影の濃さ ghost_a（0〜1）に合わせて、唸り・心音・こもり具合を変える
# pan: 人影の左右位置（-1〜1）。両バスのパンナーに反映する
# プラン 13: 通常は明るい BGM、危険時にドローン・心音を増やし ambient の pitch を下げて不協和音を出す
func update(delta: float, ghost_a: float, playing: bool, saved: bool, pan: float = 0.0) -> void:
	var ga := clampf(ghost_a, 0.0, 1.0)
	# ドローン: 危険時に大きく。不協和音を強調
	var drone: AudioStreamPlayer = players["drone"]
	var drone_target := -60.0 if saved else lerpf(-60.0, -3.0, pow(ga, 0.6))
	drone.volume_db = move_toward(drone.volume_db, drone_target, delta * 30.0)
	drone.pitch_scale = lerpf(1.0, 0.7, ga)   # プラン 13: ドローンのピッチを下げて不協和音
	# 心音: 危険時に大きく、速く
	var heart: AudioStreamPlayer = players["heart"]
	var heart_target := lerpf(-60.0, -6.0, clampf((ga - 0.05) / 0.95, 0.0, 1.0)) if playing else -60.0
	heart.volume_db = move_toward(heart.volume_db, heart_target, delta * 30.0)
	heart.pitch_scale = lerpf(1.0, 1.8, ga)   # 心音を速く
	# ambient: 危険時は音量を少し下げ、ピッチも下げて不穏にする
	var amb: AudioStreamPlayer = players["ambient"]
	var amb_target := -6.0 if saved else lerpf(-6.0, -10.0, ga)
	amb.volume_db = move_toward(amb.volume_db, amb_target, delta * 8.0)
	amb.pitch_scale = lerpf(1.0, 0.85, ga)   # プラン 13: ピッチを下げてチューニング狂わせる
	if lowpass:
		lowpass.cutoff_hz = lerpf(16000.0, 2200.0, ga)
	if ambient_pan:
		ambient_pan.pan = clampf(pan, -1.0, 1.0)
	if sfx_pan:
		sfx_pan.pan = clampf(pan, -1.0, 1.0)

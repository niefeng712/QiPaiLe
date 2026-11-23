extends Node
## 背景音乐（自动加载单例 Music）：全部用程序合成，不需要音频文件
## 启动时在后台线程生成两首循环曲子：大厅（舒缓）和牌桌（轻快），生成好之后自动播放
## 用法：Music.play_track("hall") / Music.play_track("game")；Music.set_enabled(false) 关闭

const RATE = 16000
const VOLUME_DB = -13.0

## [音高(MIDI), 时长(八分音符个数)]，-1 表示休止；每首 8 小节，每小节 8 个八分音符
const HALL = {
	"bpm": 84,
	"chords": [48, 45, 41, 43, 48, 45, 41, 43],
	"minor": [false, true, false, false, false, true, false, false],
	"melody": [
		[76, 2], [79, 2], [81, 2], [79, 2],
		[76, 4], [74, 2], [72, 2],
		[74, 2], [76, 2], [79, 2], [76, 2],
		[74, 6], [-1, 2],
		[76, 2], [79, 2], [81, 2], [84, 2],
		[81, 4], [79, 2], [76, 2],
		[74, 2], [76, 2], [74, 2], [72, 2],
		[72, 6], [-1, 2],
	],
	"hat": false,
}
const GAME = {
	"bpm": 108,
	"chords": [45, 41, 43, 40, 45, 41, 43, 45],
	"minor": [true, false, false, true, true, false, false, true],
	"melody": [
		[69, 1], [72, 1], [76, 2], [74, 1], [72, 1], [69, 2],
		[67, 2], [69, 2], [72, 2], [74, 2],
		[76, 1], [79, 1], [76, 2], [74, 2], [72, 2],
		[74, 6], [-1, 2],
		[69, 1], [72, 1], [76, 2], [79, 2], [81, 2],
		[79, 2], [76, 2], [74, 2], [76, 2],
		[72, 2], [74, 2], [72, 1], [69, 1], [67, 2],
		[69, 6], [-1, 2],
	],
	"hat": true,
}

var enabled = true
var loaded = false
var _tracks = {}
var _want = "hall"
var _player: AudioStreamPlayer
var _thread: Thread
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_thread = Thread.new()
	_thread.start(_generate)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _generate() -> void:
	var out = {"hall": _render(HALL), "game": _render(GAME)}
	_on_generated.call_deferred(out)


func _on_generated(data: Dictionary) -> void:
	_thread.wait_to_finish()
	for k in data:
		var s = AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = RATE
		s.stereo = false
		s.data = data[k]
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data[k].size() / 2
		_tracks[k] = s
	loaded = true
	_apply()


func play_track(name: String) -> void:
	if _want == name and _player.playing:
		return
	_want = name
	_apply()


func set_enabled(on: bool) -> void:
	enabled = on
	_apply()


func _apply() -> void:
	if not loaded:
		return
	if not enabled:
		_player.stop()
		return
	var s = _tracks.get(_want)
	if s == null:
		return
	if _player.stream == s and _player.playing:
		return
	if _tween != null:
		_tween.kill()
	_player.stream = s
	_player.volume_db = -40.0
	_player.play()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", VOLUME_DB, 1.5)


# ---------------------------------------------------------------- 合成

static func _hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


static func _render(song: Dictionary) -> PackedByteArray:
	var step = 60.0 / float(song["bpm"]) / 2.0
	var sps = int(step * RATE)
	var total = sps * 64
	var buf = PackedFloat32Array()
	buf.resize(total)
	buf.fill(0.0)
	# 旋律：拨弦音色（基音 + 泛音，指数衰减）
	var pos = 0
	for n in song["melody"]:
		var m = int(n[0])
		var ln = int(n[1])
		if m >= 0:
			_pluck(buf, pos * sps, _hz(m), minf(ln * step + 0.6, 2.2), 0.42, 2.6)
		pos += ln
	# 低音：每小节第1、3拍；和弦铺底：每小节一个柔和的长音
	var chords = song["chords"]
	var minor = song["minor"]
	for b in 8:
		var root = float(chords[b])
		for beat in [0, 4]:
			_bass(buf, (b * 8 + beat) * sps, _hz(root), step * 3.5, 0.30)
		var third = 3.0 if bool(minor[b]) else 4.0
		for iv in [12.0, 12.0 + third, 19.0]:
			_pad(buf, b * 8 * sps, _hz(root + iv), step * 8.0, 0.045)
		if bool(song["hat"]):
			for k in 4:
				_hat(buf, (b * 8 + k * 2 + 1) * sps, 0.05)
	var peak = 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var g = 0.85 / peak
	var data = PackedByteArray()
	data.resize(total * 2)
	for i in total:
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 30000.0))
	return data


static func _pluck(buf: PackedFloat32Array, start: int, f: float, dur: float, vol: float, decay: float) -> void:
	var n = int(dur * RATE)
	var total = buf.size()
	var att = int(0.006 * RATE)
	var w = TAU * f / RATE
	for i in n:
		var t = float(i) / RATE
		var env = minf(1.0, float(i) / att) * exp(-t * decay)
		var v = sin(w * i) + 0.35 * sin(2.0 * w * i) + 0.12 * sin(3.0 * w * i)
		var j = (start + i) % total
		buf[j] += v * env * vol


static func _bass(buf: PackedFloat32Array, start: int, f: float, dur: float, vol: float) -> void:
	var n = int(dur * RATE)
	var total = buf.size()
	var att = int(0.01 * RATE)
	for i in n:
		var ph = fmod(f * i / RATE, 1.0)
		var v = 4.0 * absf(ph - 0.5) - 1.0
		var env = minf(1.0, float(i) / att) * exp(-float(i) / RATE * 2.2)
		buf[(start + i) % total] += v * env * vol


static func _pad(buf: PackedFloat32Array, start: int, f: float, dur: float, vol: float) -> void:
	var n = int(dur * RATE)
	var total = buf.size()
	var w = TAU * f / RATE
	for i in n:
		var x = float(i) / n
		var env = sin(PI * x)
		buf[(start + i) % total] += sin(w * i) * env * vol


static func _hat(buf: PackedFloat32Array, start: int, vol: float) -> void:
	var n = int(0.03 * RATE)
	var total = buf.size()
	var rng = RandomNumberGenerator.new()
	rng.seed = start
	for i in n:
		var env = 1.0 - float(i) / n
		buf[(start + i) % total] += rng.randf_range(-1.0, 1.0) * env * env * vol

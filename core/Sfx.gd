extends Node
## 音效（自动加载单例 Sfx）：全部用代码合成，不需要任何音频文件
## 用法：Sfx.play("click")；可用的音效：click card turn win lose chat tick start end

const RATE = 22050

var enabled = true
var _players = []
var _streams = {}
var _last_ms = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["click"] = _make([[900, 0.035, 0.30, "sq"]])
	_streams["card"] = _make([[0, 0.045, 0.45, "noise"], [300, 0.07, 0.45, "sin"]])
	_streams["turn"] = _make([[660, 0.10, 0.50, "sin"], [990, 0.18, 0.50, "sin"]])
	_streams["win"] = _make([[523, 0.11, 0.45, "tri"], [659, 0.11, 0.45, "tri"], [784, 0.11, 0.45, "tri"], [1047, 0.35, 0.50, "tri"]])
	_streams["lose"] = _make([[440, 0.16, 0.42, "tri"], [370, 0.16, 0.42, "tri"], [294, 0.36, 0.42, "tri"]])
	_streams["chat"] = _make([[1180, 0.05, 0.32, "sin"], [1560, 0.09, 0.32, "sin"]])
	_streams["tick"] = _make([[1500, 0.03, 0.25, "sq"]])
	_streams["start"] = _make([[392, 0.09, 0.42, "tri"], [523, 0.09, 0.42, "tri"], [784, 0.20, 0.42, "tri"]])
	_streams["end"] = _make([[600, 0.12, 0.38, "tri"], [600, 0.22, 0.38, "tri"]])


func has_sound(name: String) -> bool:
	return _streams.has(name)


func play(name: String) -> void:
	if not enabled or not _streams.has(name):
		return
	var now = Time.get_ticks_msec()
	if now - int(_last_ms.get(name, -1000)) < 60:
		return
	_last_ms[name] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.play()
			return
	_players[0].stream = _streams[name]
	_players[0].play()


## parts: [[频率, 秒数, 音量, 波形]]，波形 sin / sq / tri / noise，依次连起来
func _make(parts: Array) -> AudioStreamWAV:
	var total = 0
	for p in parts:
		total += int(float(p[1]) * RATE)
	var data = PackedByteArray()
	data.resize(total * 2)
	var off = 0
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	for p in parts:
		var f = float(p[0])
		var n = int(float(p[1]) * RATE)
		var vol = float(p[2])
		var kind = str(p[3])
		var att = maxi(1, int(0.004 * RATE))
		for i in n:
			var t = float(i) / RATE
			var env = minf(1.0, float(i) / att) * pow(1.0 - float(i) / n, 1.6)
			var ph = fmod(f * t, 1.0)
			var v = 0.0
			if kind == "sin":
				v = sin(TAU * ph)
			elif kind == "sq":
				v = 1.0 if ph < 0.5 else -1.0
			elif kind == "tri":
				v = 4.0 * absf(ph - 0.5) - 1.0
			else:
				v = rng.randf_range(-1.0, 1.0)
			data.encode_s16(off, int(clampf(v * env * vol, -1.0, 1.0) * 32000.0))
			off += 2
	var s = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

extends Control
## 全屏动画层（不挡点击）：
##   celebrate(true/false, 文字)：一局结束时的胜利彩带 / 失败提示
##   banner(文字)：中间弹出的短提示，例如「轮到你了！」

const COLORS = [Color("#ffd54f"), Color("#ff6b6b"), Color("#4fc3f7"), Color("#81c784"), Color("#ba68c8"), Color("#ffb74d")]

var _parts = []
var _mode = ""
var _text = ""
var _start = 0
var _dur = 2.8
var _banner = ""
var _banner_ms = -10000
var _was_busy = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func celebrate(win: bool, text: String) -> void:
	_mode = "win" if win else "lose"
	_text = text
	_start = Time.get_ticks_msec()
	_parts = []
	if win:
		for i in 110:
			_parts.append({
				"p": Vector2(randf() * size.x, -randf() * size.y * 0.5 - 20.0),
				"v": Vector2(randf_range(-60, 60), randf_range(160, 420)),
				"r": randf() * TAU,
				"w": randf_range(-6, 6),
				"s": randf_range(6, 13),
				"c": COLORS[randi() % COLORS.size()],
			})


func banner(text: String) -> void:
	_banner = text
	_banner_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var busy = false
	if _mode != "":
		var t = (Time.get_ticks_msec() - _start) / 1000.0
		if t > _dur:
			_mode = ""
			_parts = []
		else:
			busy = true
			for p in _parts:
				p["p"] += p["v"] * delta
				p["v"].y += 60.0 * delta
				p["r"] += p["w"] * delta
	if Time.get_ticks_msec() - _banner_ms < 1100:
		busy = true
	if busy:
		queue_redraw()
		_was_busy = true
	elif _was_busy:
		queue_redraw()
		_was_busy = false


func _ease_back(t: float) -> float:
	var c = 1.7
	t = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (c + 1.0) * t * t * t + c * t * t


func _draw() -> void:
	var font = get_theme_default_font()
	var now = Time.get_ticks_msec()
	if _mode != "":
		var t = (now - _start) / 1000.0
		var alpha = clampf(minf(t / 0.2, (_dur - t) / 0.5), 0.0, 1.0)
		if _mode == "lose":
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.15, 0.35 * alpha))
		for p in _parts:
			var s = float(p["s"])
			draw_set_transform(p["p"], float(p["r"]), Vector2.ONE)
			draw_rect(Rect2(-s / 2.0, -s / 4.0, s, s / 2.0), Color(p["c"], alpha))
		draw_set_transform(Vector2.ZERO)
		var sc = _ease_back(t / 0.45)
		var fs = 84
		var c = size / 2.0 - Vector2(0, size.y * 0.08)
		draw_set_transform(c, 0.0, Vector2(sc, sc))
		var col = Color("#ffd54f") if _mode == "win" else Color("#cfd8dc")
		draw_string(font, Vector2(-size.x / 2.0 + 4, fs * 0.36 + 4), _text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0, 0, 0, 0.5 * alpha))
		draw_string(font, Vector2(-size.x / 2.0, fs * 0.36), _text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(col, alpha))
		draw_set_transform(Vector2.ZERO)
	var bt = (now - _banner_ms) / 1000.0
	if bt >= 0.0 and bt < 1.1:
		var a = clampf(minf(bt / 0.12, (1.1 - bt) / 0.3), 0.0, 1.0)
		var sc2 = _ease_back(bt / 0.3)
		var c2 = Vector2(size.x / 2.0, size.y * 0.42)
		draw_set_transform(c2, 0.0, Vector2(sc2, sc2))
		var r = Rect2(-170, -42, 340, 84)
		draw_rect(r, Color(0, 0, 0, 0.6 * a))
		draw_rect(r, Color(1, 0.84, 0.3, a), false, 3.0)
		draw_string(font, Vector2(-170, 16), _banner, HORIZONTAL_ALIGNMENT_CENTER, 340, 42, Color(1, 0.88, 0.4, a))
		draw_set_transform(Vector2.ZERO)

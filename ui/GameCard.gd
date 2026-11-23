extends Button
## 大厅里的游戏卡片：圆形图标 + 游戏名 + 自己的战绩

var glyph = ""
var title = ""
var tint = Color.GRAY
var sub = ""
var is_ready = true
var cat = ""


func setup(g: Dictionary, icon: Array, stat: String) -> void:
	title = str(g["name"])
	glyph = str(icon[0])
	cat = str(icon[1])
	tint = Color(str(icon[2]))
	is_ready = bool(g.get("ready", false))
	sub = stat if is_ready else "即将上线"
	text = ""
	toggle_mode = true
	disabled = not is_ready
	custom_minimum_size = Vector2(150, 136)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0.30), Color(1, 1, 1, 0.10), 1))
	add_theme_stylebox_override("hover", _sb(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.35), 1))
	add_theme_stylebox_override("pressed", _sb(Color(1, 0.85, 0.3, 0.18), Color("#ffd54f"), 3))
	add_theme_stylebox_override("hover_pressed", _sb(Color(1, 0.85, 0.3, 0.24), Color("#ffd54f"), 3))
	add_theme_stylebox_override("disabled", _sb(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.05), 1))
	mouse_entered.connect(func(): _hover(true))
	mouse_exited.connect(func(): _hover(false))
	button_down.connect(func(): _hover(false))
	queue_redraw()


var _tw: Tween


func _hover(on: bool) -> void:
	if not is_ready:
		return
	pivot_offset = size / 2.0
	if _tw != null:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2.ONE * (1.05 if on else 1.0), 0.12)


func _sb(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(16)
	return s


func set_stat(s: String) -> void:
	if is_ready:
		sub = s
		queue_redraw()


func _draw() -> void:
	var font = get_theme_default_font()
	var c = Vector2(size.x / 2.0, size.y * 0.38)
	var r = minf(size.x * 0.24, size.y * 0.25)
	var col = tint if is_ready else tint.darkened(0.55)
	draw_circle(c + Vector2(2, 4), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, col.darkened(0.15))
	draw_circle(c - Vector2(0, r * 0.06), r * 0.86, col)
	draw_circle(c - Vector2(r * 0.3, r * 0.38), r * 0.22, Color(1, 1, 1, 0.18))
	var ring = Color("#ffd54f") if button_pressed else Color(1, 1, 1, 0.55)
	draw_arc(c, r, 0, TAU, 48, ring, 3.0 if button_pressed else 1.5)
	var fs = int(r * (1.0 if glyph.length() == 1 else 0.78))
	draw_string(font, Vector2(c.x - r, c.y + fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
	var tc = Color.WHITE if is_ready else Color(1, 1, 1, 0.45)
	draw_string(font, Vector2(4, size.y * 0.80), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 21, tc)
	var sc = Color("#ffe066") if is_ready else Color(1, 1, 1, 0.40)
	draw_string(font, Vector2(4, size.y * 0.95), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 14, sc)

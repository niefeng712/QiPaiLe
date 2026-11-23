extends Control
## 连连看界面：点一张牌，再点一张一样的牌；能用两个拐弯以内的线连起来就消掉
## 右边显示倒计时、得分、剩余提示/重排次数；多人时显示每个人还剩多少张

const L = preload("res://games/lianliankan/LlkLogic.gd")
const TILE_COLS = [Color("#e74c3c"), Color("#e67e22"), Color("#27ae60"), Color("#2980b9"), Color("#8e44ad"), Color("#16a085"), Color("#c0392b")]

var st = {}
var my_seat = -1
var names = []
var sel = -1
var _recv_ms = 0
var _flash = []
var _flash_ms = 0
var _o = Vector2.ZERO
var _t = 40.0
var bar: VBoxContainer
var hint_btn: Button
var shuf_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bar = VBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	hint_btn = Button.new()
	hint_btn.custom_minimum_size = Vector2(170, 56)
	hint_btn.pressed.connect(func(): Net.send_action.call_deferred({"type": "hint"}))
	bar.add_child(hint_btn)
	shuf_btn = Button.new()
	shuf_btn.custom_minimum_size = Vector2(170, 56)
	shuf_btn.pressed.connect(func(): Net.send_action.call_deferred({"type": "shuffle"}))
	bar.add_child(shuf_btn)
	resized.connect(_layout)


func _layout() -> void:
	if st.is_empty():
		return
	var gw = int(st["w"]) + 2
	var gh = int(st["h"]) + 2
	_t = minf((size.x - 220.0) / gw, size.y / gh)
	_o = Vector2((size.x - 210.0 - gw * _t) / 2.0, (size.y - gh * _t) / 2.0)
	bar.position = Vector2(size.x - 190.0, size.y - 140.0)
	queue_redraw()


func _process(_d: float) -> void:
	if not st.is_empty() and not bool(st.get("over", false)):
		queue_redraw()


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var first = st.is_empty()
	var old_last = st.get("last", [])
	st = s
	my_seat = seat
	names = seat_names
	_recv_ms = Time.get_ticks_msec()
	var lst = s.get("last", [])
	if not lst.is_empty() and str(lst) != str(old_last):
		_flash = lst
		_flash_ms = Time.get_ticks_msec()
	if sel >= 0 and (sel >= s["board"].size() or int(s["board"][sel]) < 0):
		sel = -1
	var playing = bool(s.get("playing", false)) and not bool(s.get("over", false))
	hint_btn.text = "提示（%d）" % int(s.get("hints", 0))
	shuf_btn.text = "重排（%d）" % int(s.get("shuffles", 0))
	hint_btn.disabled = not playing or int(s.get("hints", 0)) <= 0
	shuf_btn.disabled = not playing or int(s.get("shuffles", 0)) <= 0
	if first:
		_layout()
	queue_redraw()


func _time_now() -> float:
	var t = float(st.get("time_left", 0.0))
	if bool(st.get("over", false)):
		return t
	return maxf(0.0, t - (Time.get_ticks_msec() - _recv_ms) / 1000.0)


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func status_text(s: Dictionary, seat: int, n: Array) -> String:
	names = n
	var ev = str(s.get("event", ""))
	for i in range(3, -1, -1):
		ev = ev.replace("座位%d" % (i + 1), _nm(i))
	if bool(s.get("over", false)):
		var w = s.get("winners", [])
		var res = "你赢了！" if w.has(seat) else "没有赢"
		return "%s ｜ %s" % [res, ev]
	return "点两张一样的牌，能用不超过两个拐弯的线连起来就消掉 ｜ %s" % ev


func _draw() -> void:
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var gw = int(st["w"]) + 2
	var b = st.get("board", [])
	var hint = st.get("hint", [])
	var fs = int(_t * 0.58)
	for i in b.size():
		var k = int(b[i])
		if k < 0:
			continue
		var p = _o + Vector2(i % gw, i / gw) * _t
		var r = Rect2(p + Vector2(1, 1), Vector2(_t - 2, _t - 2))
		draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.3))
		draw_rect(r, Color("#fdf6e3"))
		var col = TILE_COLS[k % TILE_COLS.size()]
		draw_rect(r, col, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), L.KINDS[k % L.KINDS.size()], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
		if i == sel:
			draw_rect(r, Color(1, 0.85, 0.2, 0.45))
			draw_rect(r, Color("#ffcc00"), false, 3.0)
		elif hint.has(i):
			draw_rect(r, Color(0.2, 0.9, 0.4, 0.35))
	if not _flash.is_empty() and Time.get_ticks_msec() - _flash_ms < 450:
		for k2 in range(1, _flash.size()):
			var a = int(_flash[k2 - 1])
			var c = int(_flash[k2])
			draw_line(_o + (Vector2(a % gw, a / gw) + Vector2(0.5, 0.5)) * _t, _o + (Vector2(c % gw, c / gw) + Vector2(0.5, 0.5)) * _t, Color("#ff3b30"), 4.0)
	_draw_panel(font)


func _draw_panel(font: Font) -> void:
	var x = size.x - 200.0
	var t = _time_now()
	draw_rect(Rect2(x, 6, 194, 120 + st.get("players", []).size() * 30), Color(0, 0, 0, 0.35))
	var tc = Color("#ff6b6b") if t <= 30.0 else Color.WHITE
	draw_string(font, Vector2(x + 12, 40), "剩余 %d:%02d" % [int(t) / 60, int(t) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, tc)
	draw_string(font, Vector2(x + 12, 74), "得分 %d" % int(st.get("score", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#ffe066"))
	var y = 110.0
	for p in st.get("players", []):
		var s = int(p["seat"])
		var txt = "%s%s 剩%d张" % [_nm(s), "（你）" if s == my_seat else "", int(p["left"])]
		if bool(p["done"]):
			txt = "%s 已消完" % _nm(s)
		draw_string(font, Vector2(x + 12, y), txt, HORIZONTAL_ALIGNMENT_LEFT, 180, 17, Color.WHITE)
		y += 30.0


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if st.is_empty() or bool(st.get("over", false)) or not bool(st.get("playing", false)):
		return
	var gw = int(st["w"]) + 2
	var q = (mb.position - _o) / _t
	var x = int(floor(q.x))
	var y = int(floor(q.y))
	if x < 0 or y < 0 or x >= gw or y >= int(st["h"]) + 2:
		return
	var i = y * gw + x
	var b = st.get("board", [])
	if int(b[i]) < 0:
		sel = -1
	elif sel < 0 or sel == i:
		sel = i if sel != i else -1
	elif int(b[sel]) == int(b[i]):
		Net.send_action({"type": "pick", "a": sel, "b": i})
		sel = -1
	else:
		sel = i
	queue_redraw()

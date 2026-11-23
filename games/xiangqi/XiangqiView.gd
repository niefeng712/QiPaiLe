extends Control
## 中国象棋界面：自己执的颜色永远在下方；点棋子选中，能走的位置会出现小圆点，再点目标就走

const X = preload("res://games/xiangqi/XqRules.gd")

var st = {}
var my_seat = -1
var names = []
var sel = -1
var dests = []
var flip = false
var _o = Vector2.ZERO
var _c = 50.0
var resign_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resign_btn = Button.new()
	resign_btn.text = "认输"
	resign_btn.custom_minimum_size = Vector2(110, 54)
	resign_btn.pressed.connect(func(): Net.send_action.call_deferred({"type": "resign"}))
	add_child(resign_btn)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_c = minf((size.x - 300.0) / 9.0, (size.y - 10.0) / 10.0)
	_c = maxf(_c, 20.0)
	_o = Vector2((size.x - 9.0 * _c) / 2.0 + _c / 2.0, (size.y - 10.0 * _c) / 2.0 + _c / 2.0)
	if resign_btn != null:
		resign_btn.position = Vector2(size.x - 130.0, size.y - 70.0)
	queue_redraw()


func _my_side() -> int:
	if my_seat == int(st.get("red_seat", -9)):
		return 1
	if my_seat == int(st.get("black_seat", -9)):
		return -1
	return 0


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	st = s
	my_seat = seat
	names = seat_names
	flip = _my_side() < 0
	sel = -1
	dests = []
	resign_btn.visible = _my_side() != 0 and not bool(s.get("over", false))
	queue_redraw()


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "?"


func status_text(s: Dictionary, seat: int, n: Array) -> String:
	var rs = int(s.get("red_seat", 0))
	var bs = int(s.get("black_seat", 1))
	var head = "红：%s 黑：%s ｜ " % [_nm_in(n, rs), _nm_in(n, bs)]
	var ev = str(s.get("event", ""))
	if bool(s.get("over", false)):
		if bool(s.get("draw", false)):
			return head + "和棋 ｜ " + ev
		var w = s.get("winners", [])
		var res = "你赢了！" if not w.is_empty() and int(w[0]) == seat else "你输了。"
		if seat != rs and seat != bs:
			res = ""
		return head + res + " ｜ " + ev
	var cur = int(s.get("current_seat", -1))
	var tip = "轮到你走棋" if cur == seat else "等待 %s 走棋…" % _nm_in(n, cur)
	if bool(s.get("check", false)) and cur == seat:
		tip = "你被将军了！" + tip
	return "%s%s ｜ 第%d回合 ｜ %s" % [head, tip, int(s.get("plies", 0)) / 2 + 1, ev]


func _nm_in(n: Array, i: int) -> String:
	if i >= 0 and i < n.size():
		return str(n[i])
	return "?"


func _pt(i: int) -> Vector2:
	var x = i % 9
	var y = i / 9
	if flip:
		x = 8 - x
		y = 9 - y
	return _o + Vector2(x * _c, y * _c)


func _draw() -> void:
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var board_rect = Rect2(_o - Vector2(_c * 0.6, _c * 0.6), Vector2(_c * 9.2, _c * 10.2))
	draw_rect(board_rect, Color("#e3b870"))
	draw_rect(board_rect, Color("#8a5a2b"), false, 4.0)
	var lc = Color(0.3, 0.18, 0.07)
	for y in 10:
		draw_line(_o + Vector2(0, y * _c), _o + Vector2(8 * _c, y * _c), lc, 1.5)
	for x in 9:
		if x == 0 or x == 8:
			draw_line(_o + Vector2(x * _c, 0), _o + Vector2(x * _c, 9 * _c), lc, 1.5)
		else:
			draw_line(_o + Vector2(x * _c, 0), _o + Vector2(x * _c, 4 * _c), lc, 1.5)
			draw_line(_o + Vector2(x * _c, 5 * _c), _o + Vector2(x * _c, 9 * _c), lc, 1.5)
	for py in [0, 7]:
		draw_line(_o + Vector2(3 * _c, py * _c), _o + Vector2(5 * _c, (py + 2) * _c), lc, 1.5)
		draw_line(_o + Vector2(5 * _c, py * _c), _o + Vector2(3 * _c, (py + 2) * _c), lc, 1.5)
	var rf = int(_c * 0.42)
	draw_string(font, _o + Vector2(0.6 * _c, 4.5 * _c + rf * 0.36), "楚 河", HORIZONTAL_ALIGNMENT_CENTER, 3 * _c, rf, lc)
	draw_string(font, _o + Vector2(4.4 * _c, 4.5 * _c + rf * 0.36), "汉 界", HORIZONTAL_ALIGNMENT_CENTER, 3 * _c, rf, lc)
	var last = st.get("last", [])
	for i in last:
		var p = _pt(int(i))
		draw_rect(Rect2(p - Vector2(_c * 0.48, _c * 0.48), Vector2(_c * 0.96, _c * 0.96)), Color(0.1, 0.5, 1.0, 0.8), false, 2.5)
	var b = st.get("board", [])
	var fs = int(_c * 0.52)
	for i in b.size():
		var v = int(b[i])
		if v == 0:
			continue
		var p2 = _pt(i)
		var r = _c * 0.44
		draw_circle(p2 + Vector2(2, 3), r, Color(0, 0, 0, 0.3))
		draw_circle(p2, r, Color("#f7e7c4"))
		var col = Color("#c0392b") if v > 0 else Color(0.12, 0.12, 0.12)
		draw_arc(p2, r * 0.86, 0, TAU, 32, col, 2.0)
		draw_string(font, p2 + Vector2(-r, fs * 0.36), X.piece_name(v), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, col)
		if i == sel:
			draw_arc(p2, r + 3.0, 0, TAU, 32, Color("#2ecc71"), 4.0)
		if absi(v) == 1 and bool(st.get("check", false)) and (v > 0) == (int(st.get("side", 1)) > 0):
			draw_arc(p2, r + 4.0, 0, TAU, 32, Color("#ff3b30"), 4.0)
	for d in dests:
		var p3 = _pt(int(d))
		if int(b[int(d)]) != 0:
			draw_arc(p3, _c * 0.48, 0, TAU, 32, Color("#2ecc71"), 4.0)
		else:
			draw_circle(p3, _c * 0.13, Color("#2ecc71"))
	_draw_captured(font)


func _draw_captured(font: Font) -> void:
	var cap = st.get("captured", {})
	var y = 30.0
	for key in ["1", "-1"]:
		var arr = cap.get(key, [])
		var who = "红方吃掉：" if key == "1" else "黑方吃掉："
		draw_string(font, Vector2(10, y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		var txt = ""
		for p in arr:
			txt += X.piece_name(int(p))
		draw_string(font, Vector2(10, y + 26), txt, HORIZONTAL_ALIGNMENT_LEFT, _o.x - 40.0, 20, Color("#ffe066"))
		y += 70.0


func _cell_at(p: Vector2) -> int:
	var q = (p - _o) / _c
	var x = int(round(q.x))
	var y = int(round(q.y))
	if x < 0 or x > 8 or y < 0 or y > 9:
		return -1
	if flip:
		x = 8 - x
		y = 9 - y
	return y * 9 + x


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if st.is_empty() or bool(st.get("over", false)) or int(st.get("current_seat", -1)) != my_seat:
		return
	var i = _cell_at(mb.position)
	if i < 0:
		return
	var sg = _my_side()
	var b = st.get("board", [])
	if sel >= 0 and dests.has(i):
		Net.send_action({"type": "move", "from": sel, "to": i})
		sel = -1
		dests = []
		queue_redraw()
		return
	var v = int(b[i])
	if v != 0 and (v > 0) == (sg > 0):
		sel = i
		dests = X.legal_from(b.duplicate(), sg, i)
		if dests.is_empty():
			Net.toast.emit("这颗棋子现在走不了")
	else:
		sel = -1
		dests = []
	queue_redraw()

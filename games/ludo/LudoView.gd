extends Control
## 飞行棋界面：15×15 十字棋盘，四色老家，点击发光的飞机移动

const COLORS = [Color("#e74c3c"), Color("#f1c40f"), Color("#3498db"), Color("#2ecc71")]
const CNAMES = ["红", "黄", "蓝", "绿"]
const HOME_START = [Vector2i(1, 7), Vector2i(7, 1), Vector2i(13, 7), Vector2i(7, 13)]
const HOME_DIR = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const BASE_ORIGIN = [Vector2i(0, 0), Vector2i(9, 0), Vector2i(9, 9), Vector2i(0, 9)]
const BASE_SLOTS = [Vector2(2, 2), Vector2(4, 2), Vector2(2, 4), Vector2(4, 4)]
const FINISH_SPOT = [Vector2(6.6, 7.5), Vector2(7.5, 6.6), Vector2(8.4, 7.5), Vector2(7.5, 8.4)]

var st = {}
var my_seat = -1
var names = []
var track = []
var dice_btn: Button
var _hits = []
var _origin = Vector2.ZERO
var _cell = 10.0
var _panel = Vector2.ZERO
var _last_ev = ""
var _roll_ms = -100000
var _pmove = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	track = _build_track()
	dice_btn = Button.new()
	dice_btn.text = "掷骰子"
	dice_btn.custom_minimum_size = Vector2(200, 70)
	dice_btn.add_theme_font_size_override("font_size", 28)
	dice_btn.pressed.connect(_on_roll)
	add_child(dice_btn)
	resized.connect(_layout)
	_layout()


func _build_track() -> Array:
	var t = []
	for x in range(1, 6):
		t.append(Vector2i(x, 6))
	for y in range(5, -1, -1):
		t.append(Vector2i(6, y))
	t.append(Vector2i(7, 0))
	t.append(Vector2i(8, 0))
	for y in range(1, 6):
		t.append(Vector2i(8, y))
	for x in range(9, 15):
		t.append(Vector2i(x, 6))
	t.append(Vector2i(14, 7))
	t.append(Vector2i(14, 8))
	for x in range(13, 8, -1):
		t.append(Vector2i(x, 8))
	for y in range(9, 15):
		t.append(Vector2i(8, y))
	t.append(Vector2i(7, 14))
	t.append(Vector2i(6, 14))
	for y in range(13, 8, -1):
		t.append(Vector2i(6, y))
	for x in range(5, -1, -1):
		t.append(Vector2i(x, 8))
	t.append(Vector2i(0, 7))
	t.append(Vector2i(0, 6))
	return t


func _layout() -> void:
	var side = min(size.y - 10.0, size.x - 300.0)
	if side < 100.0:
		side = max(min(size.x, size.y) - 10.0, 100.0)
	_cell = side / 15.0
	_origin = Vector2(10, max((size.y - side) / 2.0, 0.0))
	_panel = Vector2(_origin.x + side + 30.0, _origin.y)
	if dice_btn != null:
		dice_btn.position = _panel + Vector2(0, 170)
	queue_redraw()


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var now = Time.get_ticks_msec()
	var old_pos = st.get("pos", [])
	var ev = str(s.get("event", ""))
	if ev != _last_ev and ev.find("掷出") >= 0:
		_roll_ms = now
		_kick(450)
	_last_ev = ev
	var np = s.get("pos", [])
	if old_pos.size() == np.size():
		for si in np.size():
			for k in 4:
				var a = int(old_pos[si][k])
				var b = int(np[si][k])
				if a != b and b >= 0:
					_pmove["%d,%d" % [si, k]] = [a, now]
					_kick(320)
	st = s
	my_seat = seat
	names = seat_names
	var mine = int(st.get("current_seat", -1)) == my_seat and str(st.get("phase", "")) == "roll" and not bool(st.get("over", false))
	dice_btn.disabled = not mine
	dice_btn.text = "掷骰子" if mine else "等待中…"
	if bool(st.get("over", false)):
		dice_btn.text = "游戏结束"
	queue_redraw()


func _nm(n: Array, i: int) -> String:
	if i >= 0 and i < n.size():
		return str(n[i])
	return "?"


func status_text(s: Dictionary, seat: int, n: Array) -> String:
	if bool(s.get("over", false)):
		var parts = []
		var w = s.get("winners", [])
		for i in w.size():
			parts.append("%d.%s" % [i + 1, _nm(n, int(w[i]))])
		return "游戏结束！名次：" + "　".join(PackedStringArray(parts))
	var cur = int(s.get("current_seat", -1))
	var me = ""
	if seat >= 0 and seat < 4:
		me = "你是%s方。" % CNAMES[seat]
	var tip = ""
	var rolling = str(s.get("phase", "")) == "roll"
	if cur == seat:
		if rolling:
			tip = "轮到你，点「掷骰子」"
		else:
			tip = "点击发光的飞机，前进 %d 步" % int(s.get("dice", 0))
	else:
		tip = "等待 %s（%s方）%s…" % [_nm(n, cur), CNAMES[clampi(cur, 0, 3)], "掷骰子" if rolling else "走棋"]
	return "%s%s　｜　%s" % [me, tip, str(s.get("event", ""))]


func _cpos(g: Vector2i) -> Vector2:
	return _origin + (Vector2(g) + Vector2(0.5, 0.5)) * _cell


func _plane_point(seat: int, k: int, p: int) -> Vector2:
	if p < 0:
		return _origin + (Vector2(BASE_ORIGIN[seat]) + BASE_SLOTS[k]) * _cell
	if p <= 50:
		return _cpos(track[(seat * 13 + p) % 52])
	if p < 56:
		return _cpos(HOME_START[seat] + HOME_DIR[seat] * (p - 51))
	return _origin + FINISH_SPOT[seat] * _cell


func _draw() -> void:
	_hits = []
	var o = _origin
	var c = _cell
	draw_rect(Rect2(o, Vector2(15 * c, 15 * c)), Color("#fdf6e3"))
	for s in 4:
		var r = Rect2(o + Vector2(BASE_ORIGIN[s]) * c, Vector2(6 * c, 6 * c))
		draw_rect(r, COLORS[s])
		draw_rect(r.grow(-c * 0.5), Color(1, 1, 1, 0.85))
		for k in 4:
			draw_circle(o + (Vector2(BASE_ORIGIN[s]) + BASE_SLOTS[k]) * c, c * 0.5, COLORS[s].lightened(0.55))
	for i in track.size():
		var g: Vector2i = track[i]
		var rr = Rect2(o + Vector2(g) * c, Vector2(c, c)).grow(-1.0)
		var col = COLORS[i % 4].lightened(0.55)
		if i % 13 == 0:
			col = COLORS[i % 4]
		draw_rect(rr, col)
	for s in 4:
		for j in 5:
			var hg: Vector2i = HOME_START[s] + HOME_DIR[s] * j
			draw_rect(Rect2(o + Vector2(hg) * c, Vector2(c, c)).grow(-1.0), COLORS[s].lightened(0.2))
	var a = o + Vector2(6, 6) * c
	var b = o + Vector2(9, 6) * c
	var d = o + Vector2(9, 9) * c
	var e = o + Vector2(6, 9) * c
	var m = o + Vector2(7.5, 7.5) * c
	draw_colored_polygon(PackedVector2Array([a, e, m]), COLORS[0])
	draw_colored_polygon(PackedVector2Array([a, b, m]), COLORS[1])
	draw_colored_polygon(PackedVector2Array([b, d, m]), COLORS[2])
	draw_colored_polygon(PackedVector2Array([e, d, m]), COLORS[3])
	if not st.is_empty():
		_draw_planes()
	_draw_panel()


func _draw_planes() -> void:
	var c = _cell
	var pos = st.get("pos", [])
	var players = st.get("players", [])
	var cur = int(st.get("current_seat", -1))
	var mv = st.get("movable", [])
	var my_move = cur == my_seat and str(st.get("phase", "")) == "move" and not bool(st.get("over", false))
	var groups = {}
	var order = []
	for sv in players:
		var s = int(sv)
		for k in 4:
			var p = int(pos[s][k])
			var pt = _plane_point(s, k, p)
			var pm = _pmove.get("%d,%d" % [s, k], [])
			if not pm.is_empty() and Time.get_ticks_msec() - int(pm[1]) < 320:
				pt = _plane_point(s, k, int(pm[0])).lerp(pt, _ease((Time.get_ticks_msec() - int(pm[1])) / 300.0))
			var key = "%d,%d" % [int(pt.x), int(pt.y)]
			if not groups.has(key):
				groups[key] = []
				order.append(key)
			groups[key].append([s, k, pt])
	var font = get_theme_default_font()
	for key in order:
		var arr = groups[key]
		for j in arr.size():
			var it = arr[j]
			var s = int(it[0])
			var k = int(it[1])
			var pt: Vector2 = it[2]
			var off = Vector2.ZERO
			var r = c * 0.38
			if arr.size() > 1:
				var ang = j * TAU / arr.size()
				off = Vector2(cos(ang), sin(ang)) * c * 0.22
				r = c * 0.3
			var center = pt + off
			if my_move and s == my_seat and mv.has(k):
				draw_circle(center, r + c * 0.14, Color(1, 1, 1))
				draw_arc(center, r + c * 0.14, 0, TAU, 32, Color(0.1, 0.1, 0.1), 2.0)
			draw_circle(center, r, COLORS[s].darkened(0.15))
			draw_arc(center, r, 0, TAU, 24, Color(0, 0, 0, 0.6), 2.0)
			var fs = maxi(int(r * 1.2), 8)
			draw_string(font, center + Vector2(-r, fs * 0.35), str(k + 1), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
			_hits.append([s, k, center, r + c * 0.2])


func _draw_panel() -> void:
	var font = get_theme_default_font()
	var p = _panel
	draw_string(font, p + Vector2(0, 30), "骰子", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var dr = Rect2(p + Vector2(0, 45), Vector2(110, 110))
	draw_rect(dr, Color.WHITE)
	draw_rect(dr, Color(0, 0, 0), false, 3.0)
	var dice = int(st.get("dice", 0))
	if Time.get_ticks_msec() - _roll_ms < 420:
		dice = 1 + (Time.get_ticks_msec() / 70) % 6
	if dice > 0:
		_draw_pips(dr, dice)
	var y = 290.0
	var cur = int(st.get("current_seat", -1))
	var pos = st.get("pos", [])
	for sv in st.get("players", []):
		var s = int(sv)
		var done = 0
		for k in 4:
			if int(pos[s][k]) == 56:
				done += 1
		draw_circle(p + Vector2(12, y - 8), 11, COLORS[s])
		var col = Color("#ffe066") if s == cur else Color.WHITE
		var mark = "（你）" if s == my_seat else ""
		draw_string(font, p + Vector2(32, y), "%s%s  到达 %d/4" % [_nm(names, s), mark, done], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		y += 36.0


func _draw_pips(r: Rect2, n: int) -> void:
	var cx = r.position + r.size / 2.0
	var q = r.size.x * 0.27
	var pts = []
	match n:
		1:
			pts = [Vector2(0, 0)]
		2:
			pts = [Vector2(-1, -1), Vector2(1, 1)]
		3:
			pts = [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)]
		4:
			pts = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5:
			pts = [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)]
		_:
			pts = [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]
	var col = Color("#c0392b") if n == 1 or n == 4 else Color(0.1, 0.1, 0.1)
	for v in pts:
		draw_circle(cx + v * q, r.size.x * 0.09, col)


func _on_roll() -> void:
	Net.send_action({"type": "roll"})


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if st.is_empty() or bool(st.get("over", false)):
		return
	if int(st.get("current_seat", -1)) != my_seat or str(st.get("phase", "")) != "move":
		return
	var mv = st.get("movable", [])
	for h in _hits:
		if int(h[0]) == my_seat and mv.has(int(h[1])) and mb.position.distance_to(h[2]) <= float(h[3]):
			Net.send_action({"type": "move", "plane": int(h[1])})
			return


# ---------------------------------------------------------------- 动画小工具

var _anim_until = 0


func _process(_d: float) -> void:
	if Time.get_ticks_msec() < _anim_until:
		queue_redraw()


func _kick(ms: int) -> void:
	_anim_until = maxi(_anim_until, Time.get_ticks_msec() + ms + 60)


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

extends Control
## 军棋界面（四国 / 两国）：棋盘会旋转，让你的阵地在最下面
## 布阵：先点一个自己的棋子，再点另一个，两个交换位置；摆好后点「布阵完成」
## 走棋：点自己的棋子，能去的地方会出现白点，再点目标；铁路用粗线画出

const B = preload("res://games/junqi/JqBoard.gd")
const COLORS = [Color("#e74c3c"), Color("#f39c12"), Color("#27ae60"), Color("#2980b9")]

var st = {}
var my_seat = -1
var names = []
var board = null
var sel = -1
var dests = {}
var _pts = []
var _cw = 30.0
var _pw = 26.0
var _ph = 18.0
var bar: HBoxContainer
var _bar_sig = ""
var _last_key = ""
var _move_ms = -100000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	resized.connect(_layout)


func _n() -> int:
	return int(st.get("n", 4))


func _me() -> int:
	return my_seat if my_seat >= 0 and my_seat < _n() else 0


func _layout() -> void:
	if board == null:
		return
	var n = _n()
	var me = _me()
	var raw = []
	for p in board.pos:
		var q: Vector2i = p
		if n == 4:
			for k in (4 - me) % 4:
				q = Vector2i(16 - q.y, q.x)
		elif me == 1:
			q = Vector2i(11 - q.x, 4 - q.y)
		raw.append(q)
	var avail = Vector2(size.x - 250.0, size.y - 12.0)
	var off = Vector2(240.0, 6.0)
	if n == 4:
		_cw = minf(avail.x, avail.y) / 17.0
		var o = off + (avail - Vector2(17, 17) * _cw) / 2.0 + Vector2(_cw, _cw) / 2.0
		_pts = []
		for q in raw:
			_pts.append(o + Vector2(q.y, q.x) * _cw)
		_pw = _cw * 0.94
		_ph = _cw * 0.66
	else:
		var gap = 1.2
		_cw = minf(avail.x / 5.0 / 1.6, avail.y / (12.0 + gap))
		var colw = _cw * 1.6
		var total = Vector2(5 * colw, (12.0 + gap) * _cw)
		var o2 = off + (avail - total) / 2.0 + Vector2(colw, _cw) / 2.0
		_pts = []
		for q in raw:
			var y = q.x * _cw + (gap * _cw if q.x >= 6 else 0.0)
			_pts.append(o2 + Vector2(q.y * colw, y))
		_pw = colw * 0.86
		_ph = _cw * 0.72
	bar.position = Vector2(8, size.y - 66)
	bar.size = Vector2(230, 60)
	queue_redraw()


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var rebuild = board == null or int(st.get("n", -1)) != int(s.get("n", 4))
	var lk = str(s.get("last_path", []))
	if lk != _last_key:
		_last_key = lk
		_move_ms = Time.get_ticks_msec()
		_kick(110 * s.get("last_path", []).size())
	st = s
	my_seat = seat
	names = seat_names
	if rebuild:
		board = B.new(_n())
		_layout()
	if sel >= 0 and int(st["occ"][sel]) != my_seat:
		sel = -1
	dests = {}
	if sel >= 0 and str(st.get("phase", "")) == "play" and _my_turn():
		_calc_dests()
	elif str(st.get("phase", "")) == "play":
		sel = -1
	_refresh_buttons()
	queue_redraw()


func _my_turn() -> bool:
	return not st.is_empty() and not bool(st.get("over", false)) and int(st.get("current_seat", -1)) == my_seat and my_seat >= 0


func _is_enemy(o: int) -> bool:
	var alive = st.get("alive", [])
	return o >= 0 and my_seat >= 0 and o % 2 != my_seat % 2 and o < alive.size() and bool(alive[o])


func _calc_dests() -> void:
	dests = board.destinations(st["occ"], sel, int(st["code"][sel]), func(o): return _is_enemy(o))


func _refresh_buttons() -> void:
	var acts = []
	var ph = str(st.get("phase", ""))
	var rd = st.get("ready", [])
	if ph == "deploy" and my_seat >= 0 and my_seat < rd.size() and not bool(rd[my_seat]):
		acts.append(["布阵完成", {"type": "ready"}])
	elif ph == "play" and _my_turn():
		acts.append(["认输", {"type": "resign"}])
	var sig = str(acts)
	if sig == _bar_sig:
		return
	_bar_sig = sig
	for c in bar.get_children():
		bar.remove_child(c)
		c.queue_free()
	for a in acts:
		var b = Button.new()
		b.text = str(a[0])
		b.custom_minimum_size = Vector2(150, 56)
		b.add_theme_font_size_override("font_size", 22)
		var act = a[1]
		b.pressed.connect(func(): Net.send_action.call_deferred(act))
		bar.add_child(b)


# ---------------------------------------------------------------- 文字

func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func _fix(text: String) -> String:
	var out = text
	for i in range(3, -1, -1):
		out = out.replace("座位%d" % (i + 1), _nm(i))
	return out


func status_text(s: Dictionary, seat: int, nn: Array) -> String:
	names = nn
	var ev = _fix(str(s.get("event", "")))
	var ph = str(s.get("phase", ""))
	if bool(s.get("over", false)):
		var w = s.get("winners", [])
		var res = "和棋" if w.is_empty() else ("我方获胜！" if w.has(seat) else "我方输了")
		return "%s ｜ %s" % [res, ev]
	if ph == "deploy":
		var rd = s.get("ready", [])
		var mine = seat >= 0 and seat < rd.size() and bool(rd[seat])
		return "%s ｜ %s" % ["布阵完成，等其他人…" if mine else "布阵：点两个自己的棋子交换位置，摆好点「布阵完成」", ev]
	var cur = int(s.get("current_seat", -1))
	var tip = "轮到你走棋" if cur == seat else "等待 %s 走棋…" % _nm(cur)
	return "%s ｜ 第%d步 ｜ %s" % [tip, int(s.get("plies", 0)) + 1, ev]


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if st.is_empty() or board == null or _pts.is_empty():
		return
	var font = get_theme_default_font()
	draw_rect(Rect2(Vector2(236, 0), Vector2(size.x - 236, size.y)), Color("#d9c39a"))
	var road_col = Color(0.35, 0.25, 0.12)
	for i in board.count():
		for j in board.road[i]:
			if int(j) <= i:
				continue
			var is_rail = board.rail_adj[i].has(int(j))
			draw_line(_pts[i], _pts[int(j)], Color(0.15, 0.15, 0.15) if is_rail else road_col, maxf(_cw * 0.16, 3.0) if is_rail else 1.5)
	for i in board.count():
		var p: Vector2 = _pts[i]
		if board.camp[i]:
			draw_circle(p, _ph * 0.72, Color("#f2e6c9"))
			draw_arc(p, _ph * 0.72, 0, TAU, 24, road_col, 1.5)
		elif board.hq[i]:
			var r = Rect2(p - Vector2(_pw, _ph) * 0.58, Vector2(_pw, _ph) * 1.16)
			draw_rect(r, Color("#f2e6c9"))
			draw_rect(r, road_col, false, 1.5)
		else:
			draw_rect(Rect2(p - Vector2(_pw, _ph) * 0.3, Vector2(_pw, _ph) * 0.6), Color("#f2e6c9"))
	var lp = st.get("last_path", [])
	for k in range(1, lp.size()):
		draw_line(_pts[int(lp[k - 1])], _pts[int(lp[k])], Color(1, 1, 1, 0.85), maxf(_cw * 0.12, 2.0))
	var occ = st.get("occ", [])
	var codes = st.get("code", [])
	var fs = int(_ph * (0.62 if _n() == 4 else 0.56))
	for i in occ.size():
		var o = int(occ[i])
		if o < 0:
			continue
		var p2: Vector2 = _piece_pos(i)
		var r2 = Rect2(p2 - Vector2(_pw, _ph) / 2.0, Vector2(_pw, _ph))
		draw_rect(Rect2(r2.position + Vector2(1.5, 2), r2.size), Color(0, 0, 0, 0.35))
		draw_rect(r2, COLORS[o])
		draw_rect(r2, Color(0, 0, 0, 0.6), false, 1.0)
		var c = int(codes[i])
		if c > 0:
			var txt = B.SHORT[c] if _n() == 4 else B.NAMES[c]
			draw_string(font, Vector2(r2.position.x, p2.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x, fs, Color.WHITE)
		if i == sel:
			draw_rect(r2.grow(2), Color.WHITE, false, 3.0)
	var lf = st.get("last_fight", {})
	if not lf.is_empty():
		var at = int(lf["at"])
		draw_arc(_pts[at], _ph * 0.9, 0, TAU, 24, Color("#ff3b30"), 3.0)
	for d in dests:
		draw_circle(_pts[int(d)], _ph * 0.28, Color.WHITE)
		draw_arc(_pts[int(d)], _ph * 0.34, 0, TAU, 20, Color(0.1, 0.1, 0.1), 1.5)
	_draw_panel(font)


func _draw_panel(font: Font) -> void:
	var n = _n()
	var alive = st.get("alive", [])
	var rd = st.get("ready", [])
	var cur = int(st.get("current_seat", -1))
	draw_rect(Rect2(6, 6, 226, 40 + n * 50), Color(0, 0, 0, 0.35))
	var mode = {"dark": "暗棋", "team": "暗棋（看得到队友）", "open": "明棋"}.get(str(st.get("view", "dark")), "")
	draw_string(font, Vector2(14, 30), ("四国军棋 · " if n == 4 else "两国军棋 · ") + mode, HORIZONTAL_ALIGNMENT_LEFT, 214, 17, Color(1, 1, 1, 0.85))
	var y = 64.0
	for s in n:
		draw_rect(Rect2(14, y - 16, 18, 18), COLORS[s])
		var tag = ""
		if n == 4:
			tag = "我方" if my_seat >= 0 and s % 2 == my_seat % 2 else "对方"
		var stt = ""
		if s < alive.size() and not bool(alive[s]):
			stt = " 出局"
		elif str(st.get("phase", "")) == "deploy":
			stt = " 已布阵" if s < rd.size() and bool(rd[s]) else " 布阵中"
		var col = Color("#ffe066") if s == cur else Color.WHITE
		draw_string(font, Vector2(40, y), "%s%s %s%s" % [_nm(s), "（你）" if s == my_seat else "", tag, stt], HORIZONTAL_ALIGNMENT_LEFT, 190, 17, col)
		y += 50.0
	draw_string(font, Vector2(14, y + 4), "粗线=铁路  圆圈=行营  方框=大本营", HORIZONTAL_ALIGNMENT_LEFT, 220, 14, Color(1, 1, 1, 0.7))


func _node_at(p: Vector2) -> int:
	var best = -1
	var bd = maxf(_pw, _ph) * 0.6
	for i in _pts.size():
		var d = p.distance_to(_pts[i])
		if d < bd:
			bd = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if st.is_empty() or bool(st.get("over", false)) or my_seat < 0:
		return
	var i = _node_at(mb.position)
	if i < 0:
		return
	var occ = st.get("occ", [])
	var ph = str(st.get("phase", ""))
	if ph == "deploy":
		var rd = st.get("ready", [])
		if my_seat >= rd.size() or bool(rd[my_seat]):
			return
		if int(occ[i]) != my_seat:
			sel = -1
		elif sel >= 0 and sel != i:
			Net.send_action({"type": "swap", "a": sel, "b": i})
			sel = -1
		else:
			sel = i
		queue_redraw()
		return
	if not _my_turn():
		return
	if sel >= 0 and dests.has(i):
		Net.send_action({"type": "move", "from": sel, "to": i})
		sel = -1
		dests = {}
		queue_redraw()
		return
	if int(occ[i]) == my_seat:
		sel = i
		_calc_dests()
		if dests.is_empty():
			var c = int(st["code"][i])
			if c == B.MINE or c == B.FLAG:
				Net.toast.emit("地雷和军旗不能移动")
			elif board.hq[i]:
				Net.toast.emit("大本营里的棋子不能再动")
			else:
				Net.toast.emit("这个棋子现在走不了")
	else:
		sel = -1
		dests = {}
	queue_redraw()


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


## 刚走的棋子沿着路线移动（每一段 110 毫秒）
func _piece_pos(i: int) -> Vector2:
	var lp = st.get("last_path", [])
	var base: Vector2 = _pts[i]
	if lp.size() < 2 or int(lp[lp.size() - 1]) != i:
		return base
	var seg = 110.0
	var t = (Time.get_ticks_msec() - _move_ms) / seg
	if t >= lp.size() - 1:
		return base
	var k = int(t)
	var a: Vector2 = _pts[int(lp[k])]
	var b: Vector2 = _pts[int(lp[k + 1])]
	return a.lerp(b, _ease(t - k))

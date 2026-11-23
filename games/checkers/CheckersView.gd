extends Control
## 中国跳棋界面：棋盘会自动旋转，让你的老家在最下面
## 点自己的棋子选中，能走到的孔会亮出来，再点一下目标孔就走过去；上一步的路线会画出来

const C = preload("res://games/checkers/CcRules.gd")
const COLORS = [Color("#e74c3c"), Color("#f1c40f"), Color("#2ecc71"), Color("#3498db"), Color("#9b59b6"), Color("#e67e22")]
const CNAMES = ["红方", "黄方", "绿方", "蓝方", "紫方", "橙方"]

var st = {}
var my_seat = -1
var names = []
var sel = -1
var dests = {}
var _pos = []
var _r = 10.0
var _rot = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)


func _home_of(s: int) -> int:
	return int(st.get("home", {}).get(str(s), -1))


func _layout() -> void:
	if st.is_empty():
		return
	var mine = _home_of(my_seat)
	if mine < 0:
		var order = st.get("order", [])
		mine = _home_of(int(order[0])) if not order.is_empty() else 0
	var raw = []
	for c in C.cells():
		raw.append(Vector2(sqrt(3.0) * (c.x + c.z / 2.0), 1.5 * c.z))
	var tip = C.zone(mine, 10)
	var tv = Vector2.ZERO
	for i in tip:
		tv += raw[i]
	_rot = PI / 2.0 - tv.angle()
	var area = Rect2(240, 4, size.x - 250, size.y - 8)
	var lo = Vector2(1e9, 1e9)
	var hi = Vector2(-1e9, -1e9)
	var rot = []
	for v in raw:
		var w = v.rotated(_rot)
		rot.append(w)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.y))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.y))
	var span = hi - lo
	var sc = minf((area.size.x - 30.0) / span.x, (area.size.y - 30.0) / span.y)
	var center = area.position + area.size / 2.0
	var mid = (lo + hi) / 2.0
	_pos = []
	for w in rot:
		_pos.append(center + (w - mid) * sc)
	_r = sc * 0.42
	queue_redraw()


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var first = st.is_empty()
	st = s
	my_seat = seat
	names = seat_names
	if sel >= 0 and (int(st["occ"][sel]) != my_seat or not _my_turn()):
		sel = -1
		dests = {}
	if first or _pos.is_empty():
		_layout()
	queue_redraw()


func _my_turn() -> bool:
	return not st.is_empty() and not bool(st.get("over", false)) and my_seat >= 0 and int(st.get("current_seat", -1)) == my_seat


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func _cn(s: int) -> String:
	var h = _home_of(s)
	return CNAMES[h] if h >= 0 else "?"


func _fix(text: String) -> String:
	var out = text
	for i in range(5, -1, -1):
		out = out.replace("座位%d" % (i + 1), _nm(i))
	return out


func status_text(s: Dictionary, seat: int, nn: Array) -> String:
	names = nn
	var st_bak = st
	st = s
	var ev = _fix(str(s.get("event", "")))
	var out = ""
	if bool(s.get("over", false)):
		var rk = s.get("ranking", [])
		var parts = []
		for i in rk.size():
			parts.append("%d.%s" % [i + 1, _nm(int(rk[i]))])
		out = "游戏结束！名次：%s ｜ %s" % [" ".join(PackedStringArray(parts)), ev]
	else:
		var cur = int(s.get("current_seat", -1))
		var me = "你是%s。" % _cn(seat) if _home_of(seat) >= 0 else ""
		var tip = "轮到你：点自己的棋子，再点要去的位置" if cur == seat else "等待 %s（%s）走棋…" % [_nm(cur), _cn(cur)]
		out = "%s%s ｜ 第%d轮 ｜ %s" % [me, tip, int(s.get("rounds", 0)) + 1, ev]
	st = st_bak
	return out


func _draw() -> void:
	if st.is_empty() or _pos.is_empty():
		return
	var font = get_theme_default_font()
	var occ = st.get("occ", [])
	var pieces = int(st.get("pieces", 10))
	var md = C.min_depth(pieces)
	var order = st.get("order", [])
	var used_pts = {}
	for s in order:
		used_pts[_home_of(int(s))] = int(s)
	# 六个角的底色
	for p in 6:
		var zone = C.zone(p, 10)
		var col = COLORS[p]
		col.a = 0.22 if used_pts.has(p) or used_pts.has((p + 3) % 6) else 0.08
		for i in zone:
			draw_circle(_pos[i], _r * 1.25, col)
	# 孔
	for i in _pos.size():
		draw_circle(_pos[i], _r * 0.55, Color(0, 0, 0, 0.35))
	# 上一步路线
	var lp = st.get("last_path", [])
	if lp.size() >= 2:
		var lc = COLORS[_home_of(int(st.get("last_seat", 0)))]
		for k in range(1, lp.size()):
			draw_line(_pos[int(lp[k - 1])], _pos[int(lp[k])], Color(lc, 0.85), maxf(_r * 0.25, 2.0))
		draw_arc(_pos[int(lp[0])], _r * 0.75, 0, TAU, 24, Color(lc, 0.9), 2.0)
	# 棋子
	for i in occ.size():
		var v = int(occ[i])
		if v < 0:
			continue
		var h = _home_of(v)
		var col2 = COLORS[h] if h >= 0 else Color.GRAY
		draw_circle(_pos[i] + Vector2(1.5, 2), _r * 0.9, Color(0, 0, 0, 0.35))
		draw_circle(_pos[i], _r * 0.9, col2)
		draw_circle(_pos[i] + Vector2(-_r * 0.28, -_r * 0.28), _r * 0.3, Color(1, 1, 1, 0.45))
		if i == sel:
			draw_arc(_pos[i], _r * 1.05, 0, TAU, 32, Color.WHITE, 3.0)
	# 能走的位置
	for d in dests:
		draw_circle(_pos[int(d)], _r * 0.45, Color(1, 1, 1, 0.9))
		draw_arc(_pos[int(d)], _r * 0.6, 0, TAU, 24, Color(0.1, 0.1, 0.1), 2.0)
	_draw_panel(font)


func _draw_panel(font: Font) -> void:
	var order = st.get("order", [])
	var prog = st.get("progress", {})
	var cur = int(st.get("current_seat", -1))
	var fin = st.get("finished", [])
	var pieces = int(st.get("pieces", 10))
	var y = 20.0
	draw_rect(Rect2(6, 6, 226, 46 + order.size() * 44), Color(0, 0, 0, 0.35))
	draw_string(font, Vector2(16, 34), "%s · %d颗棋子" % ["隔空跳" if bool(st.get("far", false)) else "相邻跳", pieces], HORIZONTAL_ALIGNMENT_LEFT, 210, 18, Color(1, 1, 1, 0.8))
	y = 74.0
	for sv in order:
		var s = int(sv)
		var h = _home_of(s)
		draw_circle(Vector2(26, y - 7), 11, COLORS[h])
		var mark = "（你）" if s == my_seat else ""
		var col = Color("#ffe066") if s == cur else Color.WHITE
		var txt = "%s%s %d/%d" % [_nm(s), mark, int(prog.get(str(s), 0)), pieces]
		if fin.has(s):
			txt += " 第%d名" % (fin.find(s) + 1)
		draw_string(font, Vector2(44, y), txt, HORIZONTAL_ALIGNMENT_LEFT, 185, 18, col)
		y += 44.0


func _cell_at(p: Vector2) -> int:
	var best = -1
	var bd = _r * 1.1
	for i in _pos.size():
		var d = p.distance_to(_pos[i])
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
	if not _my_turn():
		return
	var i = _cell_at(mb.position)
	if i < 0:
		return
	var occ = st.get("occ", [])
	if sel >= 0 and dests.has(i):
		Net.send_action({"type": "move", "from": sel, "to": i})
		sel = -1
		dests = {}
		queue_redraw()
		return
	if int(occ[i]) == my_seat:
		sel = i
		dests = C.reachable(occ, i, bool(st.get("far", false)))
		var tp = (_home_of(my_seat) + 3) % 6
		var md = C.min_depth(int(st.get("pieces", 10)))
		if C.depth(i, tp) >= md:
			for d in dests.keys():
				if C.depth(int(d), tp) < md:
					dests.erase(d)
		if dests.is_empty():
			Net.toast.emit("这颗棋子现在走不了")
	else:
		sel = -1
		dests = {}
	queue_redraw()

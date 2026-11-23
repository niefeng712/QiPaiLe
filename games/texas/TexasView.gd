extends Control
## 德州扑克界面：椭圆牌桌，你坐在最下面；中间是公共牌和底池
## 轮到你时下面出现按钮：弃牌 / 过牌或跟注 / 最小加注 / 加注到底池大小 / 全下

const T = preload("res://games/texas/TexasLogic.gd")

var st = {}
var my_seat = -1
var names = []
var bar: HBoxContainer
var _sig = ""
var _board_ms = {}
var _deal_ms = -100000
var _round_seen = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bar = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	resized.connect(_layout)


func _layout() -> void:
	bar.position = Vector2(0, size.y - 64)
	bar.size = Vector2(size.x, 60)
	queue_redraw()


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var now = Time.get_ticks_msec()
	var ob = st.get("board", []).size()
	var nb = s.get("board", []).size()
	if nb < ob:
		ob = 0
	for i in range(ob, nb):
		_board_ms[i] = now + (i - ob) * 120
		_kick(260 + (nb - ob) * 120)
	var rd = int(s.get("round", 0))
	if rd != _round_seen:
		_round_seen = rd
		_deal_ms = now
		_kick(900)
	st = s
	my_seat = seat
	names = seat_names
	_refresh()
	queue_redraw()


func _refresh() -> void:
	var acts = []
	var me = st.get("me", {})
	if not me.is_empty() and not bool(st.get("over", false)) and int(st.get("current_seat", -1)) == my_seat:
		var tc = int(me["to_call"])
		var mx = int(me["max_to"])
		var mn = int(me["min_to"])
		acts.append(["弃牌", {"type": "fold"}])
		if tc == 0:
			acts.append(["过牌", {"type": "check"}])
		else:
			acts.append(["跟注 %d" % mini(tc, mx - int(me["bet"])), {"type": "call"}])
		if mn < mx:
			acts.append(["加注到 %d" % mn, {"type": "raise", "to": mn}])
			var pot_to = int(st.get("cur_bet", 0)) + int(st.get("pot", 0)) + tc
			if pot_to > mn and pot_to < mx:
				acts.append(["加到底池 %d" % pot_to, {"type": "raise", "to": pot_to}])
		acts.append(["全下 %d" % mx, {"type": "allin"}])
	var sig = str(acts)
	if sig == _sig:
		return
	_sig = sig
	for c in bar.get_children():
		bar.remove_child(c)
		c.queue_free()
	for a in acts:
		var b = Button.new()
		b.text = str(a[0])
		b.custom_minimum_size = Vector2(130, 56)
		b.add_theme_font_size_override("font_size", 21)
		var act = a[1]
		b.pressed.connect(func(): Net.send_action.call_deferred(act))
		bar.add_child(b)


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func status_text(s: Dictionary, seat: int, nn: Array) -> String:
	names = nn
	var ev = str(s.get("event", ""))
	for i in range(5, -1, -1):
		ev = ev.replace("座位%d" % (i + 1), _nm(i))
	var street = ["翻牌前", "翻牌", "转牌", "河牌", "比牌"][clampi(int(s.get("street", 0)), 0, 4)]
	var bl = s.get("blinds", [10, 20])
	var head = "%s ｜ 盲注 %d/%d ｜ 底池 %d" % [street, int(bl[0]), int(bl[1]), int(s.get("pot", 0))]
	if bool(s.get("over", false)):
		return "%s ｜ %s" % [head, ev]
	var cur = int(s.get("current_seat", -1))
	var tip = "轮到你" if cur == seat else "等待 %s…" % _nm(cur)
	var mh = str(s.get("my_hand", ""))
	if mh != "":
		tip += "（你现在是%s）" % mh
	return "%s ｜ %s ｜ %s" % [head, tip, ev]


func _card(font: Font, r: Rect2, c: int, hl: bool = false) -> void:
	draw_rect(r, Color("#fffdf5"))
	draw_rect(r, Color("#ffcc00") if hl else Color(0.2, 0.2, 0.2), false, 3.0 if hl else 1.5)
	var su = T.suit(c)
	var col = Color("#c0392b") if su == 1 or su == 3 else Color(0.1, 0.1, 0.1)
	var fs = maxi(int(r.size.x * 0.4), 9)
	draw_string(font, r.position + Vector2(4, fs + 2), T.RANK_TXT[T.rank(c)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, r.position + Vector2(4, fs * 2 + 6), T.SUITS[su], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _back(r: Rect2) -> void:
	draw_rect(r, Color("#2c5aa0"))
	draw_rect(r.grow(-3), Color("#3d7bd9"), false, 2.0)


func _draw() -> void:
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var c = Vector2(size.x / 2.0, (size.y - 70.0) / 2.0)
	var rx = size.x * 0.40
	var ry = (size.y - 70.0) * 0.38
	var pts = PackedVector2Array()
	for i in 48:
		var a = TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color("#1b7a46"))
	pts.append(pts[0])
	draw_polyline(pts, Color("#8a5a2b"), 10.0)
	var cw = clampf(size.x / 18.0, 38.0, 70.0)
	var ch = cw * 1.4
	var board = st.get("board", [])
	var best = []
	for r0 in st.get("results", []):
		if int(r0["seat"]) == my_seat:
			best = r0.get("best", [])
	var bx = c.x - (5 * cw + 4 * 8) / 2.0
	for i in 5:
		var r = Rect2(bx + i * (cw + 8), c.y - ch / 2.0 - 10, cw, ch)
		if i < board.size():
			_flip_begin(r, int(_board_ms.get(i, -100000)))
			_card(font, r, int(board[i]), best.has(board[i]))
			draw_set_transform(Vector2.ZERO)
		else:
			draw_rect(r, Color(1, 1, 1, 0.12))
	draw_string(font, Vector2(c.x - 150, c.y + ch / 2.0 + 22), "底池 %d" % int(st.get("pot", 0)), HORIZONTAL_ALIGNMENT_CENTER, 300, 24, Color("#ffe066"))
	var ps = st.get("players", [])
	var n = ps.size()
	var mi = 0
	for k in n:
		if int(ps[k]["seat"]) == my_seat:
			mi = k
	var cur = int(st.get("current_seat", -1))
	var dealer = int(st.get("dealer", -1))
	var winners = st.get("winners", [])
	for k in n:
		var p = ps[(mi + k) % n]
		var s = int(p["seat"])
		var a = PI / 2.0 + TAU * k / n
		var pos = c + Vector2(cos(a) * (rx + 10), sin(a) * (ry + 10))
		var box = Rect2(pos - Vector2(95, 46), Vector2(190, 92))
		var bg = Color(0, 0, 0, 0.55)
		if s == cur:
			bg = Color(0.85, 0.65, 0.1, 0.8)
		elif winners.has(s) and bool(st.get("over", false)):
			bg = Color(0.1, 0.6, 0.2, 0.85)
		draw_rect(box, bg)
		var nm = _nm(s) + ("（你）" if s == my_seat else "")
		draw_string(font, box.position + Vector2(8, 22), nm, HORIZONTAL_ALIGNMENT_LEFT, 150, 17, Color.WHITE)
		if s == dealer:
			draw_circle(box.position + Vector2(176, 15), 11, Color.WHITE)
			draw_string(font, box.position + Vector2(166, 21), "庄", HORIZONTAL_ALIGNMENT_CENTER, 20, 14, Color.BLACK)
		draw_string(font, box.position + Vector2(8, 46), "筹码 %d" % int(p["chips"]), HORIZONTAL_ALIGNMENT_LEFT, 180, 17, Color("#ffe066"))
		var act = str(p["act"])
		if bool(p["folded"]):
			act = "弃牌"
		draw_string(font, box.position + Vector2(8, 70), act, HORIZONTAL_ALIGNMENT_LEFT, 180, 16, Color(1, 1, 1, 0.85))
		if int(p["bet"]) > 0:
			var bp = pos.lerp(c, 0.42)
			draw_circle(bp, 14, Color("#e74c3c"))
			draw_string(font, bp + Vector2(18, 6), str(int(p["bet"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		var cards = p.get("cards", [])
		var sw = cw * (0.9 if s == my_seat else 0.6)
		var sh = sw * 1.4
		var cy = box.position.y - sh - 4 if k == 0 else box.position.y + box.size.y + 4
		if k == 0:
			cy = box.position.y - sh - 6
		for j in 2:
			var r2 = Rect2(pos.x - sw - 3 + j * (sw + 6), cy, sw, sh)
			if bool(p["folded"]):
				continue
			_flip_begin(r2, _deal_ms + k * 60 + j * 120)
			if j < cards.size():
				_card(font, r2, int(cards[j]), best.has(cards[j]) and s == my_seat)
			else:
				_back(r2)
			draw_set_transform(Vector2.ZERO)
	if bool(st.get("over", false)):
		var lines = []
		for r3 in st.get("results", []):
			if str(r3.get("hand", "")) != "":
				lines.append("%s：%s%s" % [_nm(int(r3["seat"])), str(r3["hand"]), "，赢 %d" % int(r3["won"]) if int(r3["won"]) > 0 else ""])
		var y = c.y + ch / 2.0 + 50
		for l in lines:
			draw_string(font, Vector2(c.x - 220, y), l, HORIZONTAL_ALIGNMENT_CENTER, 440, 18, Color.WHITE)
			y += 24


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


## 翻牌：从中间横向展开（start 是开始的时间，可以是将来的时间，用来错开）
func _flip_begin(r: Rect2, start: int) -> void:
	var e = _ease((Time.get_ticks_msec() - start) / 220.0)
	var sx = maxf(e, 0.02)
	var cx = r.get_center().x
	draw_set_transform(Vector2(cx * (1.0 - sx), 0), 0.0, Vector2(sx, 1.0))

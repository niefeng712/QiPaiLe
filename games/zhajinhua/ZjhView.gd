extends Control
## 炸金花界面：圆桌，你坐在最下面。没看牌时你的牌是背面，点「看牌」翻开
## 轮到你：跟注 / 加注 / 比牌（再点要比的人）/ 弃牌；筹码不够时出现「孤注一掷」

const Z = preload("res://games/zhajinhua/ZjhLogic.gd")

var st = {}
var my_seat = -1
var names = []
var bar: HBoxContainer
var _sig = ""
var picking = false
var _deal_ms = -100000
var _round_seen = -1
var _reveal = {}


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
	var rd = int(s.get("round", 0))
	if rd != _round_seen:
		_round_seen = rd
		_deal_ms = now
		_reveal = {}
		_kick(1200)
	for p in s.get("players", []):
		var key = int(p["seat"])
		var has = not p.get("cards", []).is_empty()
		if has and not _reveal.has(key):
			_reveal[key] = now
			_kick(500)
	st = s
	my_seat = seat
	names = seat_names
	if int(s.get("current_seat", -1)) != my_seat:
		picking = false
	_refresh()
	queue_redraw()


func _refresh() -> void:
	var acts = []
	var me = st.get("me", {})
	if not me.is_empty() and not bool(me.get("folded", false)) and not bool(st.get("over", false)):
		var mine = int(st.get("current_seat", -1)) == my_seat
		if picking and mine:
			for t in me.get("targets", []):
				acts.append(["和 %s 比" % _nm(int(t)), {"type": "compare", "target": int(t)}])
			acts.append(["取消", "cancel"])
		else:
			if not bool(me.get("seen", false)):
				acts.append(["看牌", {"type": "look"}])
			if mine:
				if bool(me.get("need_allin", false)):
					acts.append(["孤注一掷", {"type": "allin"}])
				else:
					acts.append(["跟注 %d" % int(me["cost"]), {"type": "call"}])
					if bool(me.get("can_raise", false)):
						acts.append(["加注 %d" % int(me["raise_cost"]), {"type": "raise"}])
					if bool(me.get("can_compare", false)):
						acts.append(["比牌", "pick"])
			acts.append(["弃牌", {"type": "fold"}])
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
		b.custom_minimum_size = Vector2(124, 56)
		b.add_theme_font_size_override("font_size", 21)
		var act = a[1]
		b.pressed.connect(func(): _on_act.call_deferred(act))
		bar.add_child(b)


func _on_act(act) -> void:
	if typeof(act) == TYPE_DICTIONARY:
		picking = false
		Net.send_action(act)
		return
	picking = str(act) == "pick"
	_refresh()


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func status_text(s: Dictionary, seat: int, nn: Array) -> String:
	names = nn
	var ev = str(s.get("event", ""))
	for i in range(5, -1, -1):
		ev = ev.replace("座位%d" % (i + 1), _nm(i))
	var head = "底注 %d ｜ 当前注 %d ｜ 底池 %d" % [int(s.get("base", 10)), int(s.get("stake", 10)), int(s.get("pot", 0))]
	if bool(s.get("over", false)):
		return "%s ｜ %s" % [head, ev]
	var cur = int(s.get("current_seat", -1))
	var tip = "轮到你" if cur == seat else "等待 %s…" % _nm(cur)
	return "%s ｜ 第%d/%d轮 ｜ %s ｜ %s" % [head, int(s.get("round", 1)), int(s.get("max_rounds", 10)), tip, ev]


func _card(font: Font, r: Rect2, c: int) -> void:
	draw_rect(r, Color("#fffdf5"))
	draw_rect(r, Color(0.2, 0.2, 0.2), false, 1.5)
	var su = Z.suit(c)
	var col = Color("#c0392b") if su == 1 or su == 3 else Color(0.1, 0.1, 0.1)
	var fs = maxi(int(r.size.x * 0.4), 9)
	draw_string(font, r.position + Vector2(4, fs + 2), Z.RANK_TXT[Z.rank(c)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, r.position + Vector2(4, fs * 2 + 6), Z.SUITS[su], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _back(r: Rect2) -> void:
	draw_rect(r, Color("#8e2b2b"))
	draw_rect(r.grow(-3), Color("#e0b44c"), false, 2.0)


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
	draw_colored_polygon(pts, Color("#7a1f2b"))
	pts.append(pts[0])
	draw_polyline(pts, Color("#d4a640"), 8.0)
	draw_string(font, Vector2(c.x - 160, c.y - 10), "底池 %d" % int(st.get("pot", 0)), HORIZONTAL_ALIGNMENT_CENTER, 320, 30, Color("#ffe066"))
	draw_string(font, Vector2(c.x - 160, c.y + 24), "当前注 %d（看牌后翻倍）" % int(st.get("stake", 10)), HORIZONTAL_ALIGNMENT_CENTER, 320, 18, Color(1, 1, 1, 0.85))
	var ps = st.get("players", [])
	var n = ps.size()
	var mi = 0
	for k in n:
		if int(ps[k]["seat"]) == my_seat:
			mi = k
	var cur = int(st.get("current_seat", -1))
	var winners = st.get("winners", [])
	var over = bool(st.get("over", false))
	var cw = clampf(size.x / 18.0, 38.0, 66.0)
	for k in n:
		var p = ps[(mi + k) % n]
		var s = int(p["seat"])
		var a = PI / 2.0 + TAU * k / n
		var pos = c + Vector2(cos(a) * (rx + 10), sin(a) * (ry + 10))
		var box = Rect2(pos - Vector2(95, 46), Vector2(190, 92))
		var bg = Color(0, 0, 0, 0.55)
		if s == cur:
			bg = Color(0.85, 0.65, 0.1, 0.8)
		elif over and winners.has(s):
			bg = Color(0.1, 0.6, 0.2, 0.85)
		elif bool(p["folded"]):
			bg = Color(0.2, 0.2, 0.2, 0.75)
		draw_rect(box, bg)
		draw_string(font, box.position + Vector2(8, 22), _nm(s) + ("（你）" if s == my_seat else ""), HORIZONTAL_ALIGNMENT_LEFT, 150, 17, Color.WHITE)
		if s == int(st.get("dealer", -1)):
			draw_circle(box.position + Vector2(176, 15), 11, Color.WHITE)
			draw_string(font, box.position + Vector2(166, 21), "庄", HORIZONTAL_ALIGNMENT_CENTER, 20, 14, Color.BLACK)
		draw_string(font, box.position + Vector2(8, 46), "筹码 %d  已下 %d" % [int(p["chips"]), int(p["paid"])], HORIZONTAL_ALIGNMENT_LEFT, 180, 16, Color("#ffe066"))
		var tag = str(p["act"])
		if not bool(p["folded"]) and not over:
			tag = ("已看牌 " if bool(p["seen"]) else "闷牌 ") + tag
		draw_string(font, box.position + Vector2(8, 70), tag, HORIZONTAL_ALIGNMENT_LEFT, 180, 15, Color(1, 1, 1, 0.85))
		var cards = p.get("cards", [])
		var sw = cw * (1.0 if s == my_seat else 0.62)
		var sh = sw * 1.4
		var cy = box.position.y - sh - 6 if k == 0 else box.position.y + box.size.y + 4
		var x0 = pos.x - (3 * sw + 8) / 2.0
		for j in 3:
			var r = Rect2(x0 + j * (sw + 4), cy, sw, sh)
			var de = _ease((Time.get_ticks_msec() - _deal_ms - (j * n + k) * 45) / 260.0)
			if de < 1.0:
				draw_set_transform((c - r.get_center()) * (1.0 - de))
			elif j < cards.size():
				_flip_begin(r, int(_reveal.get(s, -100000)) + j * 90)
			if j < cards.size():
				_card(font, r, int(cards[j]))
			else:
				_back(r)
			draw_set_transform(Vector2.ZERO)
		var hn = str(p.get("hand", ""))
		if hn != "":
			var hy = cy - 6 if k == 0 else cy + sh + 18
			draw_string(font, Vector2(pos.x - 90, hy), hn, HORIZONTAL_ALIGNMENT_CENTER, 180, 18, Color("#ffe066"))


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

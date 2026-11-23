extends Control
## 21点界面：庄家在上面，玩家在下面一排；轮到你时出现 要牌 / 停牌 / 加倍 / 分牌

const J = preload("res://games/blackjack/BjLogic.gd")

var st = {}
var my_seat = -1
var names = []
var bar: HBoxContainer
var _sig = ""
var _seen = {}
var _card_ms = {}


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
	var order = 0
	var d = s.get("dealer", [])
	for i in d.size():
		var key = "d:%d" % i
		if int(_seen.get(key, -99)) != int(d[i]):
			_seen[key] = int(d[i])
			_card_ms[key] = now + order * 110
			order += 1
	for p in s.get("players", []):
		var hs = p.get("hands", [])
		for hk in hs.size():
			var cards = hs[hk]["cards"]
			for i in cards.size():
				var key2 = "%d:%d:%d" % [int(p["seat"]), hk, i]
				if int(_seen.get(key2, -99)) != int(cards[i]):
					_seen[key2] = int(cards[i])
					_card_ms[key2] = now + order * 110
					order += 1
	if order > 0:
		_kick(260 + order * 110)
	st = s
	my_seat = seat
	names = seat_names
	_refresh()
	queue_redraw()


func _refresh() -> void:
	var acts = []
	var me = st.get("me", {})
	if me.has("bet_opts"):
		for b in me["bet_opts"]:
			acts.append(["下注 %d" % int(b), {"type": "bet", "amount": int(b)}])
	elif not me.is_empty():
		if bool(me.get("can_hit", true)):
			acts.append(["要牌", {"type": "hit"}])
		acts.append(["停牌", {"type": "stand"}])
		if bool(me.get("can_double", false)):
			acts.append(["加倍", {"type": "double"}])
		if bool(me.get("can_split", false)):
			acts.append(["分牌", {"type": "split"}])
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
		b.add_theme_font_size_override("font_size", 22)
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
	if bool(s.get("over", false)):
		return ev
	var ph = str(s.get("phase", ""))
	var cur = int(s.get("current_seat", -1))
	if ph == "bet":
		var me = s.get("me", {})
		return "%s ｜ %s" % ["请选择下注金额" if me.has("bet_opts") else "等其他人下注…", ev]
	var tip = "轮到你：要牌还是停牌？" if cur == seat else "等待 %s…" % _nm(cur)
	return "%s ｜ %s" % [tip, ev]


func _card(font: Font, r: Rect2, c: int) -> void:
	if c < 0:
		draw_rect(r, Color("#2c5aa0"))
		draw_rect(r.grow(-3), Color("#3d7bd9"), false, 2.0)
		return
	draw_rect(r, Color("#fffdf5"))
	draw_rect(r, Color(0.2, 0.2, 0.2), false, 1.5)
	var su = J.suit(c)
	var col = Color("#c0392b") if su == 1 or su == 3 else Color(0.1, 0.1, 0.1)
	var fs = maxi(int(r.size.x * 0.4), 9)
	draw_string(font, r.position + Vector2(4, fs + 2), J.RANK_TXT[J.rank(c)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, r.position + Vector2(4, fs * 2 + 6), J.SUITS[su], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	if st.is_empty():
		return
	var font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#155e3a"))
	var arc_c = Vector2(size.x / 2.0, -size.y * 0.6)
	draw_arc(arc_c, size.y * 1.25, 0.25 * PI, 0.75 * PI, 64, Color("#d4a640"), 4.0)
	draw_string(font, Vector2(0, size.y * 0.42), "黑杰克 1赔1.5 ｜ 庄家补到17点", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(1, 1, 1, 0.45))
	var cw = clampf(size.x / 16.0, 40.0, 70.0)
	var ch = cw * 1.4
	var d = st.get("dealer", [])
	var dx = size.x / 2.0 - (d.size() * (cw * 0.7) + cw * 0.3) / 2.0
	draw_string(font, Vector2(0, 30), "庄家", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)
	for i in d.size():
		var dr = Rect2(dx + i * cw * 0.7, 42, cw, ch)
		_flip_begin(dr, int(_card_ms.get("d:%d" % i, -100000)))
		_card(font, dr, int(d[i]))
		draw_set_transform(Vector2.ZERO)
	if not d.is_empty():
		var dt = int(st.get("dealer_total", 0))
		var txt = "%d 点" % dt if bool(st.get("over", false)) else "明牌 %d 点" % dt
		if dt > 21:
			txt = "%d 点 爆了" % dt
		draw_string(font, Vector2(0, 42 + ch + 28), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color("#ffe066"))
	var ps = st.get("players", [])
	var n = maxi(ps.size(), 1)
	var bw = minf(size.x / n - 12.0, 300.0)
	var x0 = (size.x - (bw + 12.0) * n) / 2.0 + 6.0
	var y0 = size.y * 0.5
	var cur = int(st.get("current_seat", -1))
	for k in ps.size():
		var p = ps[k]
		var s = int(p["seat"])
		var box = Rect2(x0 + k * (bw + 12.0), y0, bw, size.y - y0 - 74.0)
		var bg = Color(0, 0, 0, 0.35)
		if s == cur:
			bg = Color(0.85, 0.65, 0.1, 0.45)
		draw_rect(box, bg)
		draw_string(font, box.position + Vector2(8, 22), _nm(s) + ("（你）" if s == my_seat else ""), HORIZONTAL_ALIGNMENT_LEFT, bw - 16, 17, Color.WHITE)
		draw_string(font, box.position + Vector2(8, 44), "筹码 %d" % int(p["chips"]), HORIZONTAL_ALIGNMENT_LEFT, bw - 16, 16, Color("#ffe066"))
		var hs = p.get("hands", [])
		if hs.is_empty():
			var t2 = "已下注 %d" % int(p["bet"]) if bool(p["has_bet"]) else "下注中…"
			draw_string(font, box.position + Vector2(8, 70), t2, HORIZONTAL_ALIGNMENT_LEFT, bw - 16, 16, Color.WHITE)
			continue
		var hy = box.position.y + 54.0
		var scw = minf(cw * 0.8, (box.size.y - 60.0) / maxf(hs.size(), 1.0) / 1.4 - 22.0)
		scw = maxf(scw, 24.0)
		var hk = -1
		for h in hs:
			hk += 1
			var cards = h["cards"]
			for i in cards.size():
				var cr = Rect2(box.position.x + 8 + i * scw * 0.62, hy, scw, scw * 1.4)
				_flip_begin(cr, int(_card_ms.get("%d:%d:%d" % [s, hk, i], -100000)))
				_card(font, cr, int(cards[i]))
				draw_set_transform(Vector2.ZERO)
			var tt = "%s%d 点  注 %d" % ["软" if bool(h["soft"]) and int(h["total"]) < 21 else "", int(h["total"]), int(h["bet"])]
			if bool(h["doubled"]):
				tt += " 加倍"
			var res = str(h["result"])
			if res != "":
				tt += "  " + res
			var col = Color.WHITE
			if res == "赢" or res == "黑杰克":
				col = Color("#7CFC9A")
			elif res == "输" or res == "爆牌":
				col = Color("#ff8a80")
			if bool(h["active"]):
				draw_rect(Rect2(box.position.x + 4, hy - 4, bw - 8, scw * 1.4 + 26), Color.WHITE, false, 2.0)
			draw_string(font, Vector2(box.position.x + 8, hy + scw * 1.4 + 18), tt, HORIZONTAL_ALIGNMENT_LEFT, bw - 16, 15, col)
			hy += scw * 1.4 + 28.0


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

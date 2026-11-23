extends Control
## 跑得快界面：自己在下，下家在右，上家在左；点牌选中，再点「出牌」

const R = preload("res://games/paodekuai/PdkRules.gd")

var st = {}
var my_seat = -1
var names = []
var hand = []
var selected = {}
var _rects = []
var bar: HBoxContainer
var _sig = ""
var _hint_i = 0
var _hint_key = ""
var _cw = 60.0
var _ch = 84.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bar = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_cw = clampf(size.x / 14.0, 46.0, 92.0)
	_ch = _cw * 1.4
	bar.position = Vector2(0, size.y - _ch - 96)
	bar.size = Vector2(size.x, 60)
	queue_redraw()


func _me() -> int:
	return my_seat if my_seat >= 0 else 0


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var old = hand.size()
	st = s
	my_seat = seat
	names = seat_names
	hand = s.get("my_hand", [])
	if hand.size() != old:
		selected.clear()
	_refresh()
	queue_redraw()


func _mine() -> bool:
	return not st.is_empty() and not bool(st.get("over", false)) and my_seat >= 0 and int(st.get("current_seat", -1)) == my_seat


func _refresh() -> void:
	var acts = []
	if _mine():
		acts = [["要不起", "pass", bool(st.get("lead", true))], ["重选", "reset", false], ["提示", "hint", false], ["出牌", "play", false]]
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
		b.custom_minimum_size = Vector2(118, 58)
		b.add_theme_font_size_override("font_size", 24)
		b.disabled = bool(a[2])
		var k = str(a[1])
		b.pressed.connect(func(): _on_btn.call_deferred(k))
		bar.add_child(b)


func _prev() -> Dictionary:
	if bool(st.get("lead", true)):
		return {}
	return st.get("last_pattern", {})


func _on_btn(k: String) -> void:
	if k == "pass":
		selected.clear()
		Net.send_action({"type": "pass"})
	elif k == "reset":
		selected.clear()
		queue_redraw()
	elif k == "hint":
		var key = str(st.get("table", [])) + str(hand.size())
		var list = R.candidates(hand, _prev())
		var fc = int(st.get("first_card", -1))
		if fc >= 0:
			var keep = []
			for it in list:
				if it[0].has(fc):
					keep.append(it)
			list = keep
		if list.is_empty():
			Net.toast.emit("没有能管上的牌，点「要不起」")
			return
		_hint_i = 0 if key != _hint_key else _hint_i + 1
		_hint_key = key
		selected.clear()
		for c in list[_hint_i % list.size()][0]:
			selected[int(c)] = true
		queue_redraw()
	elif k == "play":
		var cards = []
		for c in hand:
			if selected.has(int(c)):
				cards.append(int(c))
		if cards.is_empty():
			Net.toast.emit("请先点选要出的牌")
			return
		var p = R.classify(cards, cards.size() == hand.size())
		if p.is_empty():
			Net.toast.emit("这不是有效的牌型")
			return
		if not R.can_beat(p, _prev()):
			Net.toast.emit("管不上上家的牌")
			return
		Net.send_action({"type": "play", "cards": cards})


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func _score(i: int) -> int:
	return int(Net.room.get("scores", {}).get(str(i), 0))


func status_text(s: Dictionary, seat: int, nn: Array) -> String:
	names = nn
	var ev = str(s.get("event", ""))
	for i in range(2, -1, -1):
		ev = ev.replace("座位%d" % (i + 1), _nm(i))
	if bool(s.get("over", false)):
		var sc = s.get("scores", [0, 0, 0])
		var d = int(sc[seat]) if seat >= 0 and seat < sc.size() else 0
		return "%s 本局 %+d 分 ｜ %s" % ["你赢了！" if s.get("winners", []).has(seat) else "你输了。", d, ev]
	var cur = int(s.get("current_seat", -1))
	var tip = ""
	if cur == seat:
		tip = "轮到你出牌" if bool(s.get("lead", false)) else ("轮到你：管上或要不起" if not bool(s.get("must", true)) else "轮到你：能管上就必须管")
	else:
		tip = "等待 %s 出牌…" % _nm(cur)
	return "%s ｜ %s" % [tip, ev]


func _draw() -> void:
	_rects = []
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var me = _me()
	var right = (me + 1) % 3
	var left = (me + 2) % 3
	var counts = st.get("counts", [0, 0, 0])
	var table = st.get("table", [{}, {}, {}])
	var reveal = st.get("reveal", [])
	var cur = int(st.get("current_seat", -1))
	var sw = _cw * 0.7
	var sh = _ch * 0.7
	_box(font, left, Vector2(12, 12), cur, counts)
	_box(font, right, Vector2(size.x - 232, 12), cur, counts)
	_tcards(font, table[left], Vector2(24, 166), false, sw, sh)
	_tcards(font, table[right], Vector2(size.x - 24, 166), true, sw, sh)
	if reveal.size() == 3:
		_row(font, reveal[left], Vector2(24, 180 + sh), sw * 0.8, sh * 0.8, false)
		_row(font, reveal[right], Vector2(size.x - 24, 180 + sh), sw * 0.8, sh * 0.8, true)
	var my_y = size.y - _ch - 96 - sh - 26
	var mt = table[me]
	if str(mt.get("kind", "")) == "play":
		var w = sw * 0.62 * (mt["cards"].size() - 1) + sw
		_tcards(font, mt, Vector2((size.x - w) / 2.0, my_y), false, sw, sh)
	elif str(mt.get("kind", "")) == "pass":
		draw_string(font, Vector2(0, my_y + sh * 0.6), "要不起", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color("#ffe066"))
	draw_string(font, Vector2(16, size.y - _ch - 30), "%s  %d张  总分%d" % [_nm(me), hand.size(), _score(me)], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#ffe066") if cur == me else Color.WHITE)
	var n = hand.size()
	if n == 0:
		return
	var sp = minf(_cw * 0.62, (size.x - 40.0 - _cw) / float(maxi(n - 1, 1)))
	var x0 = (size.x - (sp * (n - 1) + _cw)) / 2.0
	for i in n:
		var c = int(hand[i])
		var r = Rect2(x0 + i * sp, size.y - _ch - 8 - (22.0 if selected.has(c) else 0.0), _cw, _ch)
		_card(font, r, c)
		_rects.append([c, r])


func _box(font: Font, s: int, p: Vector2, cur: int, counts: Array) -> void:
	draw_rect(Rect2(p, Vector2(220, 136)), Color(1, 0.85, 0.2, 0.35) if s == cur else Color(0, 0, 0, 0.35))
	draw_string(font, p + Vector2(10, 30), _nm(s), HORIZONTAL_ALIGNMENT_LEFT, 205, 20, Color.WHITE)
	var cnt = int(counts[s])
	draw_rect(Rect2(p + Vector2(10, 44), Vector2(40, 56)), Color("#2c5aa0"))
	draw_string(font, p + Vector2(60, 84), "%d 张%s" % [cnt, " 报单！" if cnt == 1 else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#ff6b6b") if cnt <= 2 else Color.WHITE)
	draw_string(font, p + Vector2(10, 126), "总分 %d" % _score(s), HORIZONTAL_ALIGNMENT_LEFT, 205, 18, Color(1, 1, 1, 0.9))


func _row(font: Font, cards: Array, a: Vector2, w: float, h: float, from_right: bool) -> void:
	if cards.is_empty():
		return
	var step = w * 0.62
	var maxw = size.x * 0.42
	if cards.size() > 1 and step * (cards.size() - 1) + w > maxw:
		step = (maxw - w) / float(cards.size() - 1)
	var tw = step * (cards.size() - 1) + w
	var x = a.x - tw if from_right else a.x
	for i in cards.size():
		_card(font, Rect2(x + i * step, a.y, w, h), int(cards[i]))


func _tcards(font: Font, e: Dictionary, a: Vector2, from_right: bool, w: float, h: float) -> void:
	var k = str(e.get("kind", ""))
	if k == "pass":
		draw_string(font, Vector2(a.x - 130 if from_right else a.x, a.y + h * 0.6), "要不起", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#ffe066"))
		return
	if k != "play":
		return
	_row(font, e["cards"], a, w, h, from_right)
	var tw = minf(w * 0.62 * (e["cards"].size() - 1) + w, size.x * 0.42)
	draw_string(font, Vector2(a.x - tw if from_right else a.x, a.y - 6), str(e.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffe066"))


func _card(font: Font, r: Rect2, c: int) -> void:
	draw_rect(r, Color("#fffdf5"))
	draw_rect(r, Color(0.2, 0.2, 0.2), false, 1.5)
	var fs = maxi(int(r.size.x * 0.36), 8)
	var su = R.suit(c)
	var col = Color("#c0392b") if su == 1 or su == 3 else Color(0.1, 0.1, 0.1)
	draw_string(font, r.position + Vector2(3, fs + 2), R.rank_text(R.rank(c)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, r.position + Vector2(4, fs * 2 + 4), R.SUITS[su], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.9), col)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in range(_rects.size() - 1, -1, -1):
		var r: Rect2 = _rects[i][1]
		if r.has_point(mb.position):
			var c = int(_rects[i][0])
			if selected.has(c):
				selected.erase(c)
			else:
				selected[c] = true
			queue_redraw()
			return

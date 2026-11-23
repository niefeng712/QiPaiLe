extends Control
## 斗地主界面：自己在下方，下家在右，上家在左。点牌选中，再点「出牌」。

const R = preload("res://games/doudizhu/DdzRules.gd")
const SUITS = ["♠", "♥", "♣", "♦"]

var st = {}
var my_seat = -1
var names = []
var hand = []
var selected = {}
var _card_rects = []
var bar: HBoxContainer
var btns = {}
var _hint_list = []
var _hint_idx = 0
var _hint_key = ""
var _cw = 60.0
var _ch = 84.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bar = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)
	var specs = [["bid0", "不叫"], ["bid1", "1分"], ["bid2", "2分"], ["bid3", "3分"], ["pass", "不出"], ["reset", "重选"], ["hint", "提示"], ["play", "出牌"]]
	for spec in specs:
		var b = Button.new()
		b.text = str(spec[1])
		b.custom_minimum_size = Vector2(118, 58)
		b.add_theme_font_size_override("font_size", 24)
		var key = str(spec[0])
		b.pressed.connect(func(): _on_btn(key))
		bar.add_child(b)
		btns[key] = b
	resized.connect(_layout)
	_layout()
	_refresh_buttons()


func _layout() -> void:
	_cw = clampf(size.x / 14.0, 46.0, 92.0)
	_ch = _cw * 1.4
	if bar != null:
		bar.position = Vector2(0, size.y - _ch - 96)
		bar.size = Vector2(size.x, 60)
	queue_redraw()


func _me() -> int:
	return my_seat if my_seat >= 0 else 0


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var old_n = hand.size()
	st = s
	my_seat = seat
	names = seat_names
	hand = s.get("my_hand", [])
	if hand.size() != old_n:
		selected.clear()
	for k in selected.keys():
		if not hand.has(k):
			selected.erase(k)
	_refresh_buttons()
	queue_redraw()


func _refresh_buttons() -> void:
	for k in btns:
		btns[k].visible = false
	if st.is_empty() or bool(st.get("over", false)):
		return
	if int(st.get("current_seat", -1)) != my_seat or my_seat < 0:
		return
	if str(st.get("phase", "")) == "bid":
		var best = int(st.get("bid_best", 0))
		for i in 4:
			var b = btns["bid%d" % i]
			b.visible = true
			b.disabled = i != 0 and i <= best
	else:
		for k in ["pass", "reset", "hint", "play"]:
			btns[k].visible = true
		btns["pass"].disabled = bool(st.get("lead", true))


func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func _score_of(i: int) -> int:
	var sc = Net.room.get("scores", {})
	return int(sc.get(str(i), 0))


func status_text(s: Dictionary, seat: int, n: Array) -> String:
	names = n
	var ev = str(s.get("event", ""))
	for i in 3:
		ev = ev.replace("座位%d" % (i + 1), _nm(i))
	var cur = int(s.get("current_seat", -1))
	var phase = str(s.get("phase", ""))
	if bool(s.get("over", false)):
		var mine = 0
		var scs = s.get("scores", [0, 0, 0])
		if seat >= 0 and seat < scs.size():
			mine = int(scs[seat])
		var res = "你赢了！" if mine > 0 else "你输了。"
		return "%s 本局 %+d 分 ｜ %s" % [res, mine, ev]
	if phase == "bid":
		var who = "轮到你叫地主" if cur == seat else "等待 %s 叫地主…" % _nm(cur)
		return "%s ｜ 当前最高：%d分 ｜ %s" % [who, int(s.get("bid_best", 0)), ev]
	var lz = ""
	if int(s.get("laizi", 0)) > 0:
		lz = " 癞子:%s" % R.rank_text(int(s["laizi"]))
	var tip = ""
	if cur == seat:
		tip = "轮到你出牌" if bool(s.get("lead", false)) else "轮到你：管上或不出"
	else:
		tip = "等待 %s 出牌…" % _nm(cur)
	return "地主:%s 底分%d ×%d%s ｜ %s ｜ %s" % [_nm(int(s.get("landlord", -1))), int(s.get("bid_best", 0)), int(s.get("mult", 1)), lz, tip, ev]


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_card_rects = []
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

	# 底牌和癞子
	var bottom = st.get("bottom", [])
	var bx = size.x / 2.0 - (sw * 3 + 16) / 2.0
	for i in 3:
		var r = Rect2(bx + i * (sw + 8), 8, sw, sh)
		if i < bottom.size():
			_draw_card(font, r, int(bottom[i]))
		else:
			_draw_back(r)
	var lz = int(st.get("laizi", 0))
	if lz > 0:
		var lr = Rect2(bx + 3 * (sw + 8) + 20, 8, sw * 1.6, sh)
		draw_rect(lr, Color("#ffcc33"))
		draw_string(font, lr.position + Vector2(0, sh * 0.38), "癞子", HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, int(sw * 0.34), Color(0.4, 0.2, 0))
		draw_string(font, lr.position + Vector2(0, sh * 0.85), R.rank_text(lz), HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, int(sw * 0.5), Color(0.6, 0, 0))

	# 左右两家
	_draw_player_box(font, left, Vector2(12, 12), cur, counts)
	_draw_player_box(font, right, Vector2(size.x - 232, 12), cur, counts)
	var mid_y = 12 + 150.0
	_draw_table_cards(font, table[left], Vector2(24, mid_y), false, sw, sh)
	_draw_table_cards(font, table[right], Vector2(size.x - 24, mid_y), true, sw, sh)
	if reveal.size() == 3:
		_draw_table_cards(font, {"kind": "play", "cards": reveal[left]}, Vector2(24, mid_y + sh + 14), false, sw * 0.8, sh * 0.8)
		_draw_table_cards(font, {"kind": "play", "cards": reveal[right]}, Vector2(size.x - 24, mid_y + sh + 14), true, sw * 0.8, sh * 0.8)

	# 自己打出的牌
	var my_table = table[me] if me < table.size() else {}
	var my_y = size.y - _ch - 96 - sh - 26
	if str(my_table.get("kind", "")) == "play":
		var cards = my_table["cards"]
		var step = sw * 0.62
		var tw = step * (cards.size() - 1) + sw
		_draw_table_cards(font, my_table, Vector2((size.x - tw) / 2.0, my_y), false, sw, sh)
	elif str(my_table.get("kind", "")) == "pass":
		draw_string(font, Vector2(0, my_y + sh * 0.6), "不出", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color("#ffe066"))
	var me_role = _role(me)
	var info = "%s%s  %d张  总分%d" % [_nm(me), me_role, hand.size(), _score_of(me)]
	if str(st.get("phase", "")) == "bid" and int(st.get("bids", [-1, -1, -1])[me]) >= 0:
		info += "  " + _bid_text(int(st["bids"][me]))
	var info_col = Color("#ffe066") if cur == me else Color.WHITE
	draw_string(font, Vector2(16, size.y - _ch - 30), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, info_col)

	# 手牌
	var n = hand.size()
	if n == 0:
		return
	var spacing = minf(_cw * 0.62, (size.x - 40.0 - _cw) / float(maxi(n - 1, 1)))
	var total = spacing * (n - 1) + _cw
	var x0 = (size.x - total) / 2.0
	var y0 = size.y - _ch - 8
	for i in n:
		var c = int(hand[i])
		var y = y0 - (22.0 if selected.has(c) else 0.0)
		var rr = Rect2(x0 + i * spacing, y, _cw, _ch)
		_draw_card(font, rr, c)
		_card_rects.append([c, rr])


func _role(s: int) -> String:
	var ll = int(st.get("landlord", -1))
	if ll < 0:
		return ""
	return "【地主】" if s == ll else "【农民】"


func _bid_text(b: int) -> String:
	return "不叫" if b == 0 else "叫%d分" % b


func _draw_player_box(font: Font, s: int, p: Vector2, cur: int, counts: Array) -> void:
	var r = Rect2(p, Vector2(220, 136))
	var bg = Color(0, 0, 0, 0.35)
	if s == cur:
		bg = Color(1, 0.85, 0.2, 0.35)
	draw_rect(r, bg)
	draw_string(font, p + Vector2(10, 30), _nm(s) + _role(s), HORIZONTAL_ALIGNMENT_LEFT, 205, 20, Color.WHITE)
	var cnt = int(counts[s]) if s < counts.size() else 0
	_draw_back(Rect2(p + Vector2(10, 44), Vector2(40, 56)))
	var cc = Color("#ff6b6b") if cnt <= 2 else Color.WHITE
	draw_string(font, p + Vector2(60, 84), "%d 张" % cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, cc)
	var extra = "总分 %d" % _score_of(s)
	if str(st.get("phase", "")) == "bid":
		var bv = int(st.get("bids", [-1, -1, -1])[s])
		if bv >= 0:
			extra += "  " + _bid_text(bv)
	draw_string(font, p + Vector2(10, 126), extra, HORIZONTAL_ALIGNMENT_LEFT, 205, 18, Color(1, 1, 1, 0.85))


func _draw_table_cards(font: Font, entry: Dictionary, anchor: Vector2, from_right: bool, w: float, h: float) -> void:
	var kind = str(entry.get("kind", ""))
	if kind == "pass":
		var tx = anchor.x - 120 if from_right else anchor.x
		draw_string(font, Vector2(tx, anchor.y + h * 0.6), "不出", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#ffe066"))
		return
	if kind != "play":
		return
	var cards = entry.get("cards", [])
	if cards.is_empty():
		return
	var step = w * 0.62
	var maxw = size.x * 0.42
	if step * (cards.size() - 1) + w > maxw and cards.size() > 1:
		step = (maxw - w) / float(cards.size() - 1)
	var tw = step * (cards.size() - 1) + w
	var x = anchor.x - tw if from_right else anchor.x
	for i in cards.size():
		_draw_card(font, Rect2(x + i * step, anchor.y, w, h), int(cards[i]))
	if entry.has("desc"):
		draw_string(font, Vector2(x, anchor.y - 6), str(entry["desc"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffe066"))


func _draw_card(font: Font, r: Rect2, c: int) -> void:
	var lz = int(st.get("laizi", 0))
	var rank = R.card_rank(c)
	var bg = Color("#fffdf5")
	if lz > 0 and rank == lz:
		bg = Color("#ffe28a")
	draw_rect(r, bg)
	draw_rect(r, Color(0.2, 0.2, 0.2), false, 1.5)
	var fs = int(r.size.x * 0.36)
	var suit = R.card_suit(c)
	var red = suit == 1 or suit == 3 or c == 53
	var col = Color("#c0392b") if red else Color(0.1, 0.1, 0.1)
	if c >= 52:
		var t1 = "大" if c == 53 else "小"
		draw_string(font, r.position + Vector2(4, fs + 2), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_string(font, r.position + Vector2(4, fs * 2 + 4), "王", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	else:
		draw_string(font, r.position + Vector2(3, fs + 2), R.rank_text(rank), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_string(font, r.position + Vector2(4, fs * 2 + 4), SUITS[suit], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.9), col)
	if lz > 0 and rank == lz:
		draw_string(font, r.position + Vector2(0, r.size.y - 6), "癞", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4, int(fs * 0.7), Color("#d35400"))


func _draw_back(r: Rect2) -> void:
	draw_rect(r, Color("#2c5aa0"))
	draw_rect(r.grow(-4), Color("#3d7bd9"), false, 2.0)
	draw_rect(r, Color(0.1, 0.1, 0.2), false, 1.5)


# ---------------------------------------------------------------- 操作

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in range(_card_rects.size() - 1, -1, -1):
		var it = _card_rects[i]
		var rr: Rect2 = it[1]
		if rr.has_point(mb.position):
			var c = int(it[0])
			if selected.has(c):
				selected.erase(c)
			else:
				selected[c] = true
			queue_redraw()
			return


func _prev_pattern() -> Dictionary:
	if bool(st.get("lead", true)):
		return {}
	return st.get("last_pattern", {})


func _on_btn(key: String) -> void:
	if key.begins_with("bid"):
		Net.send_action({"type": "bid", "score": int(key.substr(3))})
		return
	var lz = int(st.get("laizi", 0))
	if key == "pass":
		selected.clear()
		Net.send_action({"type": "pass"})
	elif key == "reset":
		selected.clear()
		queue_redraw()
	elif key == "hint":
		var prev = _prev_pattern()
		var hk = str(st.get("table", [])) + str(hand.size())
		if hk != _hint_key:
			_hint_key = hk
			_hint_idx = 0
			if prev.is_empty():
				_hint_list = R.lead_options(hand, lz)
			else:
				_hint_list = R.follow_candidates(hand, lz, prev)
		else:
			_hint_idx += 1
		if _hint_list.is_empty():
			Net.toast.emit("没有能管上的牌，可以点「不出」")
			return
		selected.clear()
		for c in _hint_list[_hint_idx % _hint_list.size()]:
			selected[int(c)] = true
		queue_redraw()
	elif key == "play":
		var cards = []
		for c in hand:
			if selected.has(int(c)):
				cards.append(int(c))
		if cards.is_empty():
			Net.toast.emit("请先点选要出的牌")
			return
		if R.choose_pattern(cards, lz, _prev_pattern()).is_empty():
			if R.evaluate(cards, lz).is_empty():
				Net.toast.emit("这不是有效的牌型")
			else:
				Net.toast.emit("管不上上家的牌")
			return
		Net.send_action({"type": "play", "cards": cards})

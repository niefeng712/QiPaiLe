extends Control
## 斗地主界面（三人 / 四人）
## 三人：自己在下方，下家在右，上家在左；四人：再加一个对家在上方
## 点牌选中，再点「出牌」；右下角是记牌器（显示每个点数还剩几张没出、不在你手里）

const R = preload("res://games/doudizhu/DdzRules.gd")
const SUITS = ["♠", "♥", "♣", "♦"]

var st = {}
var my_seat = -1
var names = []
var hand = []
var selected = {}
var _card_rects = []
var bar: HBoxContainer
var _bar_sig = ""
var _hint_list = []
var _hint_idx = 0
var _hint_key = ""
var _cw = 60.0
var _ch = 84.0
var _tsig = []


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
	if bar != null:
		bar.position = Vector2(0, size.y - _ch - 96)
		bar.size = Vector2(size.x, 60)
	queue_redraw()


func _me() -> int:
	return my_seat if my_seat >= 0 else 0


func _n() -> int:
	return int(st.get("n", 3))


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	R.set_two_decks(int(s.get("decks", 1)) == 2)
	var old_n = hand.size()
	st = s
	my_seat = seat
	names = seat_names
	hand = s.get("my_hand", [])
	if hand.size() != old_n:
		selected.clear()
	var now = Time.get_ticks_msec()
	var tb = s.get("table", [])
	for i in tb.size():
		var sig = str(tb[i])
		while _tsig.size() <= i:
			_tsig.append("")
		if sig != _tsig[i]:
			_tsig[i] = sig
			if str(tb[i].get("kind", "")) == "play":
				_tfly[i] = now
				_kick(320)
	var rd = int(s.get("round", 0))
	if rd != _round_seen or hand.size() > old_n + 2:
		_round_seen = rd
		_deal_ms = now
		_kick(260 + hand.size() * 22)
	for k in selected.keys():
		if not hand.has(k):
			selected.erase(k)
	_refresh_buttons()
	queue_redraw()


# ---------------------------------------------------------------- 按钮

func _actions() -> Array:
	var out = []
	if st.is_empty() or bool(st.get("over", false)):
		return out
	if my_seat < 0 or int(st.get("current_seat", -1)) != my_seat:
		return out
	var ph = str(st.get("phase", ""))
	if ph == "ming":
		out.append(["明牌开始 ×5", {"type": "ming", "yes": true}, false])
		out.append(["不明牌", {"type": "ming", "yes": false}, false])
	elif ph == "lming":
		out.append(["明牌 ×2", {"type": "ming", "yes": true}, false])
		out.append(["不明牌", {"type": "ming", "yes": false}, false])
	elif ph == "bid":
		if str(st.get("bid_mode", "score")) == "rob":
			if int(st.get("rob_caller", -1)) == -1:
				out.append(["叫地主", {"type": "rob", "yes": true}, false])
				out.append(["不叫", {"type": "rob", "yes": false}, false])
			else:
				out.append(["抢地主 ×2", {"type": "rob", "yes": true}, false])
				out.append(["不抢", {"type": "rob", "yes": false}, false])
		else:
			var best = int(st.get("bid_best", 0))
			out.append(["不叫", {"type": "bid", "score": 0}, false])
			for i in range(1, 4):
				out.append(["%d分" % i, {"type": "bid", "score": i}, i <= best])
	elif ph == "double":
		out.append(["不加倍", {"type": "double", "x": 1}, false])
		out.append(["加倍 ×2", {"type": "double", "x": 2}, false])
		if my_seat == int(st.get("landlord", -1)):
			out.append(["超级加倍 ×4", {"type": "double", "x": 4}, false])
	elif ph == "play":
		out.append(["不出", "pass", bool(st.get("lead", true))])
		out.append(["重选", "reset", false])
		out.append(["提示", "hint", false])
		out.append(["出牌", "play", false])
	return out


func _refresh_buttons() -> void:
	var acts = _actions()
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
		b.custom_minimum_size = Vector2(128, 58)
		b.add_theme_font_size_override("font_size", 24)
		b.disabled = bool(a[2])
		var act = a[1]
		b.pressed.connect(func(): _on_act.call_deferred(act))
		bar.add_child(b)


func _on_act(act) -> void:
	if typeof(act) == TYPE_DICTIONARY:
		Net.send_action(act)
		return
	_on_btn(str(act))


# ---------------------------------------------------------------- 文字

func _nm(i: int) -> String:
	if i >= 0 and i < names.size():
		return str(names[i])
	return "座位%d" % (i + 1)


func _score_of(i: int) -> int:
	var sc = Net.room.get("scores", {})
	return int(sc.get(str(i), 0))


func _role(s: int) -> String:
	var ll = int(st.get("landlord", -1))
	if ll < 0:
		return ""
	return "【地主】" if s == ll else "【农民】"


func _badges(s: int) -> String:
	var parts = []
	var sh = st.get("shown", [])
	if s < sh.size() and bool(sh[s]):
		parts.append("明牌")
	var d = st.get("doubles", [])
	if s < d.size():
		if int(d[s]) == 2:
			parts.append("加倍")
		elif int(d[s]) == 4:
			parts.append("超级加倍")
	var says = st.get("says", [])
	if s < says.size() and str(says[s]) != "" and not parts.has(str(says[s])):
		parts.append(str(says[s]))
	return " ".join(PackedStringArray(parts))


func status_text(s: Dictionary, seat: int, nn: Array) -> String:
	names = nn
	var n = int(s.get("n", 3))
	var ev = str(s.get("event", ""))
	for i in n:
		ev = ev.replace("座位%d" % (i + 1), _nm(i))
	var cur = int(s.get("current_seat", -1))
	var ph = str(s.get("phase", ""))
	var mine = cur == seat
	if bool(s.get("over", false)):
		var my = 0
		var scs = s.get("scores", [])
		if seat >= 0 and seat < scs.size():
			my = int(scs[seat])
		var res = "你赢了！" if my > 0 else "你输了。"
		return "%s 本局 %+d 分 ｜ %s" % [res, my, ev]
	if ph == "ming":
		var w1 = "要不要明牌开始？明牌后大家都能看到你的牌，倍数×5" if mine else "等待 %s 选择是否明牌…" % _nm(cur)
		return "%s ｜ %s" % [w1, ev]
	if ph == "bid":
		if str(s.get("bid_mode", "score")) == "rob":
			var w2 = ""
			if mine:
				w2 = "轮到你：叫地主？" if int(s.get("rob_caller", -1)) == -1 else "轮到你：抢地主？"
			else:
				w2 = "等待 %s…" % _nm(cur)
			return "%s ｜ 当前倍数 ×%d ｜ %s" % [w2, int(s.get("mult", 1)), ev]
		var w3 = "轮到你叫地主" if mine else "等待 %s 叫地主…" % _nm(cur)
		return "%s ｜ 当前最高：%d分 ｜ %s" % [w3, int(s.get("bid_best", 0)), ev]
	if ph == "lming":
		var w4 = "你当地主了，要不要明牌？倍数×2" if mine else "等待地主选择是否明牌…"
		return "%s ｜ %s" % [w4, ev]
	if ph == "double":
		var w5 = "选择是否加倍" if mine else "等待 %s 选择加倍…" % _nm(cur)
		return "%s ｜ 你的倍数 ×%d ｜ %s" % [w5, int(s.get("my_mult", 1)), ev]
	var lz = ""
	if int(s.get("laizi", 0)) > 0:
		lz = " 癞子:%s" % R.rank_text(int(s["laizi"]))
	var tip = ""
	if mine:
		tip = "轮到你出牌" if bool(s.get("lead", false)) else "轮到你：管上或不出"
	else:
		tip = "等待 %s 出牌…" % _nm(cur)
	return "地主:%s 底分%d 你的倍数×%d%s ｜ %s ｜ %s" % [_nm(int(s.get("landlord", -1))), int(s.get("bid_best", 0)), int(s.get("my_mult", 1)), lz, tip, ev]


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_card_rects = []
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var n = _n()
	var me = _me()
	var counts = st.get("counts", [])
	var table = st.get("table", [])
	var cur = int(st.get("current_seat", -1))
	var sw = _cw * 0.7
	var sh = _ch * 0.7

	# 底牌（三人3张 / 四人8张）
	var bottom = st.get("bottom", [])
	var bc = int(st.get("bottom_count", 3))
	var bstep = sw + 8.0 if bc <= 3 else sw * 0.62
	var bw = bstep * (bc - 1) + sw
	var bx = size.x / 2.0 - bw / 2.0
	if n == 4:
		bx = size.x / 2.0 - bw - 10.0
	for i in bc:
		var r = Rect2(bx + i * bstep, 8, sw, sh)
		if i < bottom.size():
			_draw_card(font, r, int(bottom[i]))
		else:
			_draw_back(r)
	var lz = int(st.get("laizi", 0))
	if lz > 0:
		var lr = Rect2(bx + bw + 20, 8, sw * 1.6, sh)
		draw_rect(lr, Color("#ffcc33"))
		draw_string(font, lr.position + Vector2(0, sh * 0.38), "癞子", HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, int(sw * 0.34), Color(0.4, 0.2, 0))
		draw_string(font, lr.position + Vector2(0, sh * 0.85), R.rank_text(lz), HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, int(sw * 0.5), Color(0.6, 0, 0))

	# 左右两家
	var right = (me + 1) % n
	var left = (me + n - 1) % n
	_draw_player_box(font, left, Vector2(12, 12), cur, counts)
	_draw_player_box(font, right, Vector2(size.x - 232, 12), cur, counts)
	var mid_y = 162.0
	if left < table.size():
		_fly_on(left, Vector2(-1, 0))
		_draw_table_cards(font, table[left], Vector2(24, mid_y), false, sw, sh)
		draw_set_transform(Vector2.ZERO)
	if right < table.size():
		_fly_on(right, Vector2(1, 0))
		_draw_table_cards(font, table[right], Vector2(size.x - 24, mid_y), true, sw, sh)
		draw_set_transform(Vector2.ZERO)
	var lh = _visible_hand(left)
	if not lh.is_empty():
		_draw_row(font, lh, 24, mid_y + sh + 14, sw * 0.8, sh * 0.8, size.x * 0.42, false)
	var rh = _visible_hand(right)
	if not rh.is_empty():
		_draw_row(font, rh, size.x - 24, mid_y + sh + 14, sw * 0.8, sh * 0.8, size.x * 0.42, true)

	# 四人：对家
	if n == 4:
		var top = (me + 2) % 4
		var tp = Vector2(size.x / 2.0 + 10.0, 8)
		_draw_top_box(font, top, tp, cur, counts)
		var th = _visible_hand(top)
		if not th.is_empty():
			_draw_row(font, th, bx, sh + 16, sw * 0.6, sh * 0.6, tp.x + 320.0 - bx, false)
		if top < table.size():
			var entry = table[top]
			var cards = entry.get("cards", [])
			var tw = sw * 0.62 * maxi(cards.size() - 1, 0) + sw
			_fly_on(top, Vector2(0, -1))
			_draw_table_cards(font, entry, Vector2((size.x - tw) / 2.0, sh + 16 + sh * 0.6 + 30), false, sw, sh)
			draw_set_transform(Vector2.ZERO)

	# 自己打出的牌
	var my_table = table[me] if me < table.size() else {}
	var my_y = size.y - _ch - 96 - sh - 26
	if str(my_table.get("kind", "")) == "play":
		var mc = my_table["cards"]
		var mw = sw * 0.62 * (mc.size() - 1) + sw
		_fly_on(me, Vector2(0, 1))
		_draw_table_cards(font, my_table, Vector2((size.x - mw) / 2.0, my_y), false, sw, sh)
		draw_set_transform(Vector2.ZERO)
	elif str(my_table.get("kind", "")) == "pass":
		draw_string(font, Vector2(0, my_y + sh * 0.6), "不出", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color("#ffe066"))
	var my_count = int(counts[me]) if me < counts.size() else hand.size()
	var info = "%s%s  %d张  总分%d  %s" % [_nm(me), _role(me), my_count, _score_of(me), _badges(me)]
	var info_col = Color("#ffe066") if cur == me else Color.WHITE
	draw_string(font, Vector2(16, size.y - _ch - 30), info, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.45, 20, info_col)

	_draw_counter(font)

	# 手牌
	if bool(st.get("hand_hidden", false)):
		var hn = my_count
		var hs = minf(_cw * 0.62, (size.x - 40.0 - _cw) / float(maxi(hn - 1, 1)))
		var hx = (size.x - (hs * (hn - 1) + _cw)) / 2.0
		for i in hn:
			_draw_back(Rect2(hx + i * hs, size.y - _ch - 8, _cw, _ch))
		return
	var cnt = hand.size()
	if cnt == 0:
		return
	var spacing = minf(_cw * 0.62, (size.x - 40.0 - _cw) / float(maxi(cnt - 1, 1)))
	var total = spacing * (cnt - 1) + _cw
	var x0 = (size.x - total) / 2.0
	var y0 = size.y - _ch - 8
	for i in cnt:
		var c = int(hand[i])
		var y = y0 - (22.0 if selected.has(c) else 0.0)
		var rr = Rect2(x0 + i * spacing, y, _cw, _ch)
		draw_set_transform(Vector2(0, _deal_off(i)))
		_draw_card(font, rr, c)
		draw_set_transform(Vector2.ZERO)
		_card_rects.append([c, rr])


func _visible_hand(s: int) -> Array:
	var reveal = st.get("reveal", [])
	if s < reveal.size() and not reveal[s].is_empty():
		return reveal[s]
	var op = st.get("open", [])
	if s < op.size():
		return op[s]
	return []


func _draw_counter(font: Font) -> void:
	if not bool(st.get("counter_on", false)):
		return
	var played = st.get("played", [])
	if played.size() < 18 or int(st.get("landlord", -1)) < 0:
		return
	var decks = int(st.get("decks", 1))
	var mine = {}
	for c in hand:
		var r = R.card_rank(int(c))
		mine[r] = int(mine.get(r, 0)) + 1
	var ranks = [17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3]
	var cw2 = clampf((size.x * 0.27) / 15.0, 18.0, 26.0)
	var h2 = 50.0
	var x0 = size.x - 12.0 - cw2 * 15.0
	var y0 = size.y - _ch - 96.0
	draw_rect(Rect2(x0 - 4, y0 - 22, cw2 * 15 + 8, h2 + 26), Color(0, 0, 0, 0.4))
	draw_string(font, Vector2(x0, y0 - 5), "记牌器（未出且不在你手里）", HORIZONTAL_ALIGNMENT_LEFT, cw2 * 15, 13, Color(1, 1, 1, 0.75))
	for i in 15:
		var r = int(ranks[i])
		var tot = decks if r >= 16 else 4 * decks
		var rest = tot - int(played[r]) - int(mine.get(r, 0))
		var lab = "大" if r == 17 else ("小" if r == 16 else R.rank_text(r))
		var x = x0 + i * cw2
		draw_string(font, Vector2(x, y0 + 16), lab, HORIZONTAL_ALIGNMENT_CENTER, cw2, 14, Color(1, 1, 1, 0.85))
		var col = Color("#ffe066") if rest > 0 else Color(1, 1, 1, 0.3)
		draw_string(font, Vector2(x, y0 + 42), str(rest), HORIZONTAL_ALIGNMENT_CENTER, cw2, 19, col)


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
	draw_string(font, p + Vector2(10, 126), "总分 %d  %s" % [_score_of(s), _badges(s)], HORIZONTAL_ALIGNMENT_LEFT, 205, 18, Color(1, 1, 1, 0.9))


func _draw_top_box(font: Font, s: int, p: Vector2, cur: int, counts: Array) -> void:
	var r = Rect2(p, Vector2(320, 62))
	var bg = Color(0, 0, 0, 0.35)
	if s == cur:
		bg = Color(1, 0.85, 0.2, 0.35)
	draw_rect(r, bg)
	draw_string(font, p + Vector2(10, 26), _nm(s) + _role(s), HORIZONTAL_ALIGNMENT_LEFT, 300, 20, Color.WHITE)
	var cnt = int(counts[s]) if s < counts.size() else 0
	var cc = Color("#ff6b6b") if cnt <= 2 else Color.WHITE
	draw_string(font, p + Vector2(10, 52), "%d张  总分%d  %s" % [cnt, _score_of(s), _badges(s)], HORIZONTAL_ALIGNMENT_LEFT, 300, 18, cc)


func _draw_row(font: Font, cards: Array, ax: float, ay: float, w: float, h: float, maxw: float, from_right: bool) -> void:
	if cards.is_empty():
		return
	var step = w * 0.62
	if cards.size() > 1 and step * (cards.size() - 1) + w > maxw:
		step = maxf((maxw - w) / float(cards.size() - 1), 4.0)
	var tw = step * (cards.size() - 1) + w
	var x = ax - tw if from_right else ax
	for i in cards.size():
		_draw_card(font, Rect2(x + i * step, ay, w, h), int(cards[i]))


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
	var maxw = size.x * 0.42
	var step = w * 0.62
	if cards.size() > 1 and step * (cards.size() - 1) + w > maxw:
		step = (maxw - w) / float(cards.size() - 1)
	var tw = step * (cards.size() - 1) + w
	var x = anchor.x - tw if from_right else anchor.x
	_draw_row(font, cards, anchor.x, anchor.y, w, h, maxw, from_right)
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
	var fs = maxi(int(r.size.x * 0.36), 8)
	var suit = R.card_suit(c)
	var red = suit == 1 or suit == 3 or rank == 17
	var col = Color("#c0392b") if red else Color(0.1, 0.1, 0.1)
	if rank >= 16:
		var t1 = "大" if rank == 17 else "小"
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


var _tfly = {}
var _deal_ms = -100000
var _round_seen = -1


## 出牌飞入：从出牌人那一边飞到桌上
func _fly_on(seat: int, dir: Vector2) -> void:
	var e = _ease((Time.get_ticks_msec() - int(_tfly.get(seat, -100000))) / 280.0)
	draw_set_transform(dir * 170.0 * (1.0 - e))


## 发牌：手牌一张一张从下面升上来
func _deal_off(i: int) -> float:
	var e = _ease((Time.get_ticks_msec() - _deal_ms - i * 22) / 240.0)
	return (1.0 - e) * 260.0

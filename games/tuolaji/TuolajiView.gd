extends Control
## 升级拖拉机界面：自己在下，下家在右，对家（队友）在上，上家在左
## 主牌在手牌最左边并用浅黄色底标出；点牌选中，再点「出牌」

const T = preload("res://games/tuolaji/TljRules.gd")

var st = {}
var my_seat = -1
var names = []
var hand = []
var selected = {}
var ctx = {"level": 2, "trump": -2}
var _card_rects = []
var bar: HBoxContainer
var _bar_sig = ""
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
	_cw = clampf(size.x / 15.0, 44.0, 86.0)
	_ch = _cw * 1.4
	if bar != null:
		bar.position = Vector2(0, size.y - _ch - 92)
		bar.size = Vector2(size.x, 60)
	queue_redraw()


func _me() -> int:
	return my_seat if my_seat >= 0 else 0


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	var old_n = hand.size()
	st = s
	my_seat = seat
	names = seat_names
	ctx = T.make_ctx(int(s.get("level", 2)), int(s.get("trump", -2)))
	hand = s.get("my_hand", [])
	if hand.size() != old_n:
		selected.clear()
	for k in selected.keys():
		if not hand.has(k):
			selected.erase(k)
	_refresh_buttons()
	queue_redraw()


# ---------------------------------------------------------------- 按钮

func _my_turn() -> bool:
	return not st.is_empty() and not bool(st.get("over", false)) and my_seat >= 0 and int(st.get("current_seat", -1)) == my_seat


func _actions() -> Array:
	var out = []
	if not _my_turn():
		return out
	var ph = str(st.get("phase", ""))
	if ph == "declare":
		for o in st.get("declare_opts", []):
			out.append([str(o["label"]), {"type": "declare", "suit": int(o["suit"]), "str": int(o["str"])}, false])
		out.append(["不亮", {"type": "declare", "pass": true}, false])
	elif ph == "bury":
		out.append(["重选", "reset", false])
		out.append(["提示", "hint", false])
		out.append(["扣底（已选%d/8）" % selected.size(), "bury", selected.size() != 8])
	elif ph == "play":
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
		b.add_theme_font_size_override("font_size", 22)
		b.disabled = bool(a[2])
		var act = a[1]
		b.pressed.connect(func(): _on_act.call_deferred(act))
		bar.add_child(b)


func _on_act(act) -> void:
	if typeof(act) == TYPE_DICTIONARY:
		Net.send_action(act)
		return
	_on_btn(str(act))


func _selected_cards() -> Array:
	var out = []
	for c in hand:
		if selected.has(int(c)):
			out.append(int(c))
	return out


func _select(cards: Array) -> void:
	selected.clear()
	for c in cards:
		selected[int(c)] = true
	_refresh_buttons()
	queue_redraw()


func _on_btn(key: String) -> void:
	var ph = str(st.get("phase", ""))
	var lead = st.get("lead_cards", [])
	if key == "reset":
		_select([])
	elif key == "hint":
		if ph == "bury":
			_select(T.bury_suggest(hand, ctx))
		elif lead.is_empty():
			_select(T.lead_suggest(hand, ctx))
		else:
			_select(T.follow_play(hand, lead, ctx, "low"))
	elif key == "bury":
		var cards = _selected_cards()
		if cards.size() != 8:
			Net.toast.emit("请选择8张牌扣底")
			return
		Net.send_action({"type": "bury", "cards": cards})
	elif key == "play":
		var cards2 = _selected_cards()
		if cards2.is_empty():
			Net.toast.emit("请先点选要出的牌")
			return
		if lead.is_empty():
			if not T.same_suit(cards2, ctx):
				Net.toast.emit("首家出的牌必须是同一花色（或都是主牌）")
				return
		else:
			var err = T.check_follow(hand, cards2, lead, ctx)
			if err != "":
				Net.toast.emit(err)
				return
		Net.send_action({"type": "play", "cards": cards2})


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
	var cur = int(s.get("current_seat", -1))
	var ph = str(s.get("phase", ""))
	var mine = cur == seat and seat >= 0
	if bool(s.get("over", false)):
		var won = seat >= 0 and s.get("winners", []).has(seat)
		return "%s ｜ %s" % ["我方赢了这一局！" if won else "我方输了这一局。", ev]
	if ph == "declare":
		var w1 = "轮到你：要亮主吗？" if mine else "等待 %s 亮主…" % _nm(cur)
		return "亮主（打%s）｜ %s ｜ %s" % [T.rank_text(int(s.get("level", 2))), w1, ev]
	if ph == "bury":
		var w2 = "你是庄家：选8张牌扣到底下（可点「提示」）" if mine else "等待庄家扣底…"
		return "%s ｜ %s" % [w2, ev]
	var lead = s.get("lead_cards", [])
	var w3 = ""
	if mine:
		w3 = "轮到你出牌" if lead.is_empty() else "轮到你跟牌（出%d张）" % lead.size()
	else:
		w3 = "等待 %s 出牌…" % _nm(cur)
	return "%s ｜ %s" % [w3, ev]


# ---------------------------------------------------------------- 绘制

func _team_tag(s: int) -> String:
	var me = _me()
	var t = "我方" if s % 2 == me % 2 else "对方"
	if s == int(st.get("dealer", -1)):
		t += "·庄"
	return t


func _draw() -> void:
	_card_rects = []
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var me = _me()
	var cur = int(st.get("current_seat", -1))
	var counts = st.get("counts", [0, 0, 0, 0])
	var sw = _cw * 0.66
	var sh = _ch * 0.66
	_draw_info(font)
	var right = (me + 1) % 4
	var top = (me + 2) % 4
	var left = (me + 3) % 4
	_draw_box(font, top, Vector2(size.x / 2.0 - 130.0, 6), cur, counts)
	_draw_box(font, left, Vector2(12, 150), cur, counts)
	_draw_box(font, right, Vector2(size.x - 272.0, 150), cur, counts)

	# 桌上的牌（这一轮还没出牌时显示上一轮）
	var trick = st.get("trick", [])
	var best = int(st.get("best_seat", -1))
	var faded = false
	if trick.is_empty() and not st.get("last_trick", []).is_empty() and not bool(st.get("over", false)):
		trick = st["last_trick"]
		best = int(st.get("last_winner", -1))
		faded = true
	var me_y = size.y - _ch - 100.0 - sh - 34.0
	var mid_y = (150.0 + me_y) / 2.0
	for p in trick:
		var s = int(p[0])
		var cards = p[1]
		var rel = (s - me + 4) % 4
		var tw = _row_width(cards.size(), sw)
		var pos = Vector2.ZERO
		if rel == 0:
			pos = Vector2((size.x - tw) / 2.0, me_y)
		elif rel == 1:
			pos = Vector2(size.x - 290.0 - tw, mid_y - sh / 2.0)
		elif rel == 2:
			pos = Vector2((size.x - tw) / 2.0, 145.0)
		else:
			pos = Vector2(290.0, mid_y - sh / 2.0)
		_draw_row(font, cards, pos, sw, sh)
		if faded:
			draw_rect(Rect2(pos, Vector2(tw, sh)), Color(0.12, 0.37, 0.23, 0.45))
		if s == best:
			draw_string(font, pos + Vector2(0, -6), "最大", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffe066"))
	if faded:
		draw_string(font, Vector2(0, mid_y + sh / 2.0 + 26.0), "（上一轮）", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(1, 1, 1, 0.7))

	# 庄家能看到自己扣的底牌
	var bottom = st.get("bottom", [])
	if not bottom.is_empty() and not bool(st.get("over", false)):
		draw_string(font, Vector2(12, 312), "我扣的底牌：", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
		_draw_row(font, bottom, Vector2(12, 320), sw * 0.6, sh * 0.6)

	# 一局结束
	if bool(st.get("over", false)):
		var r = Rect2(size.x / 2.0 - 340.0, 140.0, 680.0, 210.0)
		draw_rect(r, Color(0, 0, 0, 0.72))
		var won = my_seat >= 0 and st.get("winners", []).has(my_seat)
		var head = "我方赢了这一局！" if won else "我方输了这一局"
		if bool(st.get("match_over", false)):
			head = "我方赢得整场比赛！" if won else "对方赢得整场比赛"
		draw_string(font, r.position + Vector2(0, 40), head, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 30, Color("#ffe066"))
		_draw_wrapped(font, _fix(str(st.get("event", ""))), r.position + Vector2(20, 76), r.size.x - 40.0, 18)
		draw_string(font, r.position + Vector2(20, 150), "底牌：", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		_draw_row(font, bottom, r.position + Vector2(80, 128), sw * 0.6, sh * 0.6)

	# 自己的信息
	var info = "%s（%s）  %d张" % [_nm(me), _team_tag(me), hand.size()]
	var info_col = Color("#ffe066") if cur == me else Color.WHITE
	draw_string(font, Vector2(16, size.y - _ch - 26), info, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.5, 20, info_col)

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


func _draw_wrapped(font: Font, text: String, pos: Vector2, width: float, fs: int) -> void:
	var line = ""
	var y = pos.y
	for ch in text:
		if font.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			draw_string(font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
			line = ""
			y += fs + 6
		line += ch
	if line != "":
		draw_string(font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_info(font: Font) -> void:
	var me = _me()
	var lv = st.get("levels", [2, 2])
	var mine = int(lv[me % 2])
	var theirs = int(lv[1 - me % 2])
	var dl = int(st.get("dealer", -1))
	var r = Rect2(12, 6, 300, 136)
	draw_rect(r, Color(0, 0, 0, 0.35))
	var tr = int(st.get("trump", -2))
	var tcol = Color("#ff8a80") if tr == 1 or tr == 3 else Color.WHITE
	var tt = T.trump_text(tr)
	if str(st.get("phase", "")) == "declare" and tr != -2:
		tt += "（亮主中）"
	draw_string(font, Vector2(22, 32), "主牌：" + tt, HORIZONTAL_ALIGNMENT_LEFT, 285, 20, tcol)
	var dn = _nm(dl) if dl >= 0 else "待定"
	draw_string(font, Vector2(22, 60), "打%s ｜ 庄家：%s" % [T.rank_text(int(st.get("level", 2))), dn], HORIZONTAL_ALIGNMENT_LEFT, 285, 19, Color.WHITE)
	draw_string(font, Vector2(22, 88), "我方打%s ｜ 对方打%s" % [T.level_text(mine), T.level_text(theirs)], HORIZONTAL_ALIGNMENT_LEFT, 285, 19, Color.WHITE)
	var att = int(st.get("attackers", -1))
	var who = ""
	if att >= 0:
		who = "（我方）" if att == me % 2 else "（对方）"
	draw_string(font, Vector2(22, 116), "闲家%s得分：%d ｜ 第%d/25轮" % [who, int(st.get("points", 0)), mini(int(st.get("tricks_done", 0)) + 1, 25)], HORIZONTAL_ALIGNMENT_LEFT, 285, 19, Color("#ffe066"))


func _draw_box(font: Font, s: int, p: Vector2, cur: int, counts: Array) -> void:
	var r = Rect2(p, Vector2(260, 130))
	var bg = Color(0, 0, 0, 0.35)
	if s == cur:
		bg = Color(1, 0.85, 0.2, 0.35)
	draw_rect(r, bg)
	draw_string(font, p + Vector2(10, 30), _nm(s), HORIZONTAL_ALIGNMENT_LEFT, 240, 20, Color.WHITE)
	var tag = _team_tag(s)
	var tc = Color("#8fd3ff") if s % 2 == _me() % 2 else Color("#ffb3a7")
	draw_string(font, p + Vector2(10, 58), tag, HORIZONTAL_ALIGNMENT_LEFT, 240, 18, tc)
	var cnt = int(counts[s]) if s < counts.size() else 0
	_draw_back(Rect2(p + Vector2(10, 70), Vector2(36, 50)))
	draw_string(font, p + Vector2(56, 106), "%d 张" % cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var d = st.get("decl", {})
	if not d.is_empty() and int(d.get("seat", -1)) == s:
		draw_string(font, p + Vector2(140, 106), "亮主", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#ffe066"))


func _row_width(n: int, w: float) -> float:
	if n <= 0:
		return 0.0
	var step = w * 0.55
	var maxw = size.x * 0.36
	if n > 1 and step * (n - 1) + w > maxw:
		step = (maxw - w) / float(n - 1)
	return step * (n - 1) + w


func _draw_row(font: Font, cards: Array, pos: Vector2, w: float, h: float) -> void:
	var n = cards.size()
	if n == 0:
		return
	var step = w * 0.55
	var maxw = size.x * 0.36
	if n > 1 and step * (n - 1) + w > maxw:
		step = (maxw - w) / float(n - 1)
	for i in n:
		_draw_card(font, Rect2(pos.x + i * step, pos.y, w, h), int(cards[i]))


func _draw_card(font: Font, r: Rect2, c: int) -> void:
	var is_trump = T.eff(c, ctx) == T.TRUMP
	draw_rect(r, Color("#fff1bd") if is_trump else Color("#fffdf5"))
	draw_rect(r, Color(0.2, 0.2, 0.2), false, 1.5)
	var fs = maxi(int(r.size.x * 0.36), 8)
	var rk = T.rank(c)
	var su = T.suit(c)
	var red = su == 1 or su == 3 or rk == 16
	var col = Color("#c0392b") if red else Color(0.1, 0.1, 0.1)
	if rk >= 15:
		draw_string(font, r.position + Vector2(4, fs + 2), "大" if rk == 16 else "小", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_string(font, r.position + Vector2(4, fs * 2 + 4), "王", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	else:
		draw_string(font, r.position + Vector2(3, fs + 2), T.rank_text(rk), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_string(font, r.position + Vector2(4, fs * 2 + 4), T.SUITS[su], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.9), col)
	if T.points_of(c) > 0 and r.size.x >= 40.0:
		draw_string(font, r.position + Vector2(0, r.size.y - 6), "%d分" % T.points_of(c), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4, maxi(int(fs * 0.55), 8), Color("#d35400"))


func _draw_back(r: Rect2) -> void:
	draw_rect(r, Color("#2c5aa0"))
	draw_rect(r.grow(-4), Color("#3d7bd9"), false, 2.0)
	draw_rect(r, Color(0.1, 0.1, 0.2), false, 1.5)


# ---------------------------------------------------------------- 点牌

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
			_refresh_buttons()
			queue_redraw()
			return

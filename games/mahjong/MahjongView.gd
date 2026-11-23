extends Control
## 麻将界面：自己在下，下家在右，对家在上，上家在左；中间是四家的牌河
## 点一张牌选中，再点一次（或点「打出」）就打出去

const M = preload("res://games/mahjong/MjRules.gd")
const SUIT_COL = [Color("#c0392b"), Color("#1e8449"), Color("#1f4e9c")]

var st = {}
var my_seat = -1
var names = []
var hand = []
var drawn = -1
var selected = {}
var _tile_rects = []
var bar: HBoxContainer
var _bar_sig = ""
var _tw = 48.0
var _th = 66.0
var _drawn_ms = -100000
var _disc_ms = -100000
var _last_disc = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bar = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	resized.connect(_layout)
	_layout()


func _me() -> int:
	return my_seat if my_seat >= 0 else 0


func _layout() -> void:
	var nh = hand.size() + (1 if drawn >= 0 else 0)
	var nm = 0
	var ng = 0
	if not st.is_empty():
		for m in st.get("melds", [[], [], [], []])[_me()]:
			nm += m["tiles"].size()
			ng += 1
	_tw = clampf((size.x - 60.0) / (maxf(nh, 13.0) + 0.6 + nm * 0.72 + ng * 0.25), 28.0, 60.0)
	_th = _tw * 1.36
	if bar != null:
		bar.position = Vector2(0, size.y - _th - 84)
		bar.size = Vector2(size.x, 58)
	queue_redraw()


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	st = s
	my_seat = seat
	names = seat_names
	hand = s.get("my_hand", [])
	var nd = int(s.get("drawn", -1))
	var now = Time.get_ticks_msec()
	if nd >= 0 and nd != drawn:
		_drawn_ms = now
		_kick(260)
	drawn = nd
	var lt = int(s.get("last_discard", {}).get("tile", -1))
	if lt != _last_disc:
		_last_disc = lt
		_disc_ms = now
		_kick(300)
	var all = hand.duplicate()
	if drawn >= 0:
		all.append(drawn)
	for k in selected.keys():
		if not all.has(k):
			selected.erase(k)
	if str(s.get("phase", "")) != "exchange" and selected.size() > 1:
		selected.clear()
	_layout()
	_refresh_buttons()


func _all_hand() -> Array:
	var a = hand.duplicate()
	if drawn >= 0:
		a.append(drawn)
	return a


# ---------------------------------------------------------------- 按钮

func _my_turn() -> bool:
	return not st.is_empty() and not bool(st.get("over", false)) and my_seat >= 0 and int(st.get("current_seat", -1)) == my_seat


func _my_que() -> int:
	var q = st.get("que", [])
	if my_seat >= 0 and my_seat < q.size() and str(st.get("mode", "")) == "xuezhan":
		return int(q[my_seat])
	return -1


func _actions() -> Array:
	var out = []
	if not _my_turn():
		return out
	var ph = str(st.get("phase", ""))
	if ph == "exchange":
		out.append(["提示", "hint", false])
		out.append(["换出这3张（已选%d/3）" % selected.size(), "exchange", selected.size() != 3])
	elif ph == "dingque":
		var sug = M.suggest_que(_all_hand())
		for s in 3:
			out.append(["缺%s%s" % [M.SUIT_CH[s], "（推荐）" if s == sug else ""], {"type": "que", "suit": s}, false])
	elif ph == "turn":
		var o = st.get("opts", {})
		if bool(o.get("hu", false)):
			out.append(["胡！", {"type": "hu"}, false])
		for g in o.get("gangs", []):
			out.append(["杠 %s" % M.tname(int(g)), {"type": "gang", "t": int(g)}, false])
		out.append(["提示", "hint", false])
		out.append(["打出", "discard", selected.size() != 1])
	elif ph == "claim":
		var t = int(st.get("claim_tile", -1))
		for o in st.get("claim", []):
			var act = str(o["act"])
			if act == "hu":
				out.append(["胡！", {"type": "claim", "act": "hu"}, false])
			elif act == "peng":
				out.append(["碰 %s" % M.tname(t), {"type": "claim", "act": "peng"}, false])
			elif act == "gang":
				out.append(["杠 %s" % M.tname(t), {"type": "claim", "act": "gang"}, false])
			elif act == "chi":
				var u = o["use"]
				var seq = [int(u[0]), int(u[1]), t]
				seq.sort()
				var txt = ""
				for x in seq:
					txt += M.NUMS[x % 9]
				out.append(["吃 %s%s" % [txt, M.SUIT_CH[t / 9]], {"type": "claim", "act": "chi", "use": [int(u[0]), int(u[1])]}, false])
		out.append(["过", {"type": "claim", "act": "pass"}, false])
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
		b.custom_minimum_size = Vector2(118, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.disabled = bool(a[2])
		var act = a[1]
		b.pressed.connect(func(): _on_act.call_deferred(act))
		bar.add_child(b)


func _on_act(act) -> void:
	if typeof(act) == TYPE_DICTIONARY:
		selected.clear()
		Net.send_action(act)
		return
	var key = str(act)
	var ph = str(st.get("phase", ""))
	if key == "hint":
		selected.clear()
		if ph == "exchange":
			for i in M.suggest_exchange(_all_hand()):
				selected[int(i)] = true
		else:
			var ex = st.get("melds", [[], [], [], []])[_me()].size()
			var id = M.suggest_discard(_all_hand(), ex, _my_que(), 27 if str(st.get("mode", "")) == "xuezhan" else 34)
			if id >= 0:
				selected[id] = true
		_refresh_buttons()
		queue_redraw()
	elif key == "exchange":
		Net.send_action({"type": "exchange", "tiles": selected.keys()})
		selected.clear()
	elif key == "discard":
		if selected.size() == 1:
			_try_discard(int(selected.keys()[0]))


func _try_discard(id: int) -> void:
	var q = _my_que()
	if q >= 0 and M.tsuit(id / 4) != q:
		for i in _all_hand():
			if M.tsuit(int(i) / 4) == q:
				Net.toast.emit("要先把缺的那门（%s）打完" % M.SUIT_CH[q])
				return
	selected.clear()
	Net.send_action({"type": "discard", "tile": id})


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
	var head = str(s.get("mode_name", "麻将"))
	if bool(s.get("over", false)):
		var sc = s.get("scores", [0, 0, 0, 0])
		var d = int(sc[seat]) if seat >= 0 and seat < sc.size() else 0
		return "%s ｜ 本局你 %+d 分 ｜ %s" % [head, d, ev]
	var tip = ""
	if ph == "exchange":
		tip = "换三张：选3张同一花色的牌换出去" if mine else "等待 %s 选换三张…" % _nm(cur)
	elif ph == "dingque":
		tip = "定缺：选一门不要的花色（这门牌要全部打掉才能胡）" if mine else "等待 %s 定缺…" % _nm(cur)
	elif ph == "turn":
		if mine:
			tip = "轮到你出牌"
			if bool(s.get("opts", {}).get("hu", false)):
				tip = "可以胡了！点「胡！」"
		else:
			tip = "等待 %s 出牌…" % _nm(cur)
	elif ph == "claim":
		if mine:
			var kind = str(s.get("claim_kind", ""))
			var what = "补杠" if kind == "rob" else "打出"
			tip = "%s %s了 %s，你要吗？" % [_nm(int(s.get("claim_from", -1))), what, M.tname(int(s.get("claim_tile", -1)))]
		else:
			tip = "等待其他玩家操作…"
	var ting = s.get("ting", [])
	if not ting.is_empty():
		var tn = []
		for t in ting:
			tn.append(M.tname(int(t)))
		tip += " ｜ 听：" + "、".join(PackedStringArray(tn))
	return "%s ｜ %s ｜ %s" % [head, tip, ev]


# ---------------------------------------------------------------- 绘制

func _draw_tile(font: Font, r: Rect2, t: int, hl: bool = false) -> void:
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.06), r.size), Color("#2f6b45"))
	draw_rect(r, Color("#fbf6e9"))
	draw_rect(r, Color("#ffd54f") if hl else Color(0.35, 0.35, 0.3), false, 3.0 if hl else 1.2)
	if t < 0:
		return
	var w = r.size.x
	if t >= 27:
		var ch = M.HONORS[t - 27]
		var col = Color(0.1, 0.1, 0.1)
		if t == 31:
			col = Color("#c0392b")
		elif t == 32:
			col = Color("#1e8449")
		var fs = maxi(int(w * 0.62), 8)
		if t == 33:
			var ir = r.grow(-w * 0.2)
			draw_rect(ir, Color("#1f4e9c"), false, maxf(w * 0.06, 1.5))
		else:
			draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), ch, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
		return
	var su = t / 9
	var fs1 = maxi(int(w * 0.5), 8)
	var fs2 = maxi(int(w * 0.44), 7)
	draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.42), M.NUMS[t % 9], HORIZONTAL_ALIGNMENT_CENTER, w, fs1, SUIT_COL[su] if su == 0 else Color(0.12, 0.12, 0.12))
	draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.86), M.SUIT_CH[su], HORIZONTAL_ALIGNMENT_CENTER, w, fs2, SUIT_COL[su])


func _draw_back(r: Rect2) -> void:
	draw_rect(r, Color("#2e7d4f"))
	draw_rect(r.grow(-2), Color("#43a96b"), false, 1.5)


func _draw_tiles_row(font: Font, ids: Array, pos: Vector2, w: float, maxw: float = 0.0) -> float:
	var h = w * 1.36
	var step = w
	if maxw > 0.0 and ids.size() > 1 and step * ids.size() > maxw:
		step = maxw / float(ids.size())
	for i in ids.size():
		_draw_tile(font, Rect2(pos + Vector2(i * step, 0), Vector2(w - 1, h)), int(ids[i]) / 4)
	return step * ids.size()


func _draw_melds(font: Font, ms: Array, pos: Vector2, w: float) -> float:
	var x = pos.x
	var h = w * 1.36
	for m in ms:
		var tiles = m["tiles"]
		var k = str(m["k"])
		for i in tiles.size():
			var r = Rect2(Vector2(x + i * w, pos.y), Vector2(w - 1, h))
			if k == "agang" and (i == 0 or i == 3):
				_draw_back(r)
			else:
				_draw_tile(font, r, int(tiles[i]) / 4)
		x += tiles.size() * w + w * 0.3
	return x - pos.x


func _que_text(s: int) -> String:
	var q = st.get("que", [])
	if str(st.get("mode", "")) != "xuezhan" or s >= q.size():
		return ""
	var v = int(q[s])
	if v == -2:
		return "已定缺"
	if v < 0:
		return ""
	return "缺" + M.SUIT_CH[v]


func _score_of(i: int) -> int:
	var sc = Net.room.get("scores", {})
	return int(sc.get(str(i), 0))


func _win_of(s: int) -> Dictionary:
	for w in st.get("wins", []):
		if int(w["seat"]) == s:
			return w
	return {}


func _draw_box(font: Font, s: int, p: Vector2, wbox: float) -> void:
	var cur = int(st.get("current_seat", -1))
	var r = Rect2(p, Vector2(wbox, 92))
	draw_rect(r, Color(1, 0.85, 0.2, 0.35) if s == cur else Color(0, 0, 0, 0.35))
	var tag = "庄 " if s == int(st.get("dealer", -1)) else ""
	draw_string(font, p + Vector2(10, 26), tag + _nm(s), HORIZONTAL_ALIGNMENT_LEFT, wbox - 20, 20, Color.WHITE)
	var cnt = int(st.get("counts", [0, 0, 0, 0])[s])
	var line2 = "%d张  %s" % [cnt, _que_text(s)]
	draw_string(font, p + Vector2(10, 54), line2, HORIZONTAL_ALIGNMENT_LEFT, wbox - 20, 18, Color.WHITE)
	var w = _win_of(s)
	var line3 = "总分 %d" % _score_of(s)
	if not w.is_empty():
		line3 += "  已胡%s（第%d个）" % [M.tname(int(w["tile"])), int(w["order"])]
	draw_string(font, p + Vector2(10, 82), line3, HORIZONTAL_ALIGNMENT_LEFT, wbox - 20, 17, Color("#ffe066") if not w.is_empty() else Color(1, 1, 1, 0.85))


func _draw_river(font: Font, ids: Array, pos: Vector2, cols: int, w: float, last_id: int) -> void:
	var h = w * 1.36
	for i in ids.size():
		var r = Rect2(pos + Vector2((i % cols) * w, (i / cols) * h), Vector2(w - 1, h - 1))
		if int(ids[i]) == last_id:
			var sc = 1.0 + 0.9 * (1.0 - _ease((Time.get_ticks_msec() - _disc_ms) / 280.0))
			var cc = r.get_center()
			draw_set_transform(cc * (1.0 - sc), 0.0, Vector2(sc, sc))
		_draw_tile(font, r, int(ids[i]) / 4, int(ids[i]) == last_id)
		draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	_tile_rects = []
	if st.is_empty():
		return
	var font = get_theme_default_font()
	var me = _me()
	var right = (me + 1) % 4
	var top = (me + 2) % 4
	var left = (me + 3) % 4
	var melds = st.get("melds", [[], [], [], []])
	var discs = st.get("discards", [[], [], [], []])
	var reveal = st.get("reveal", [[], [], [], []])
	var ld = st.get("last_discard", {})
	var last_id = int(ld.get("tile", -1))
	var sw = clampf(_tw * 0.6, 18.0, 30.0)
	var rw = clampf(size.x / 50.0, 17.0, 28.0)
	var rh = rw * 1.36
	var cx = size.x / 2.0
	var cy = (size.y - _th - 90.0) / 2.0 + 16.0

	# 三家对手
	_draw_box(font, top, Vector2(cx - 120.0, 4), 240.0)
	var tx = cx + 130.0
	tx += _draw_melds(font, melds[top], Vector2(tx, 8), sw)
	if not reveal[top].is_empty():
		_draw_tiles_row(font, reveal[top], Vector2(cx + 130.0, 8 + sw * 1.36 + 6), sw * 0.85, size.x - cx - 140.0)
	_draw_box(font, left, Vector2(10, 104), 230.0)
	var lm_y = 204.0
	_draw_melds(font, melds[left], Vector2(10, lm_y), sw * 0.9)
	if not reveal[left].is_empty():
		_draw_tiles_row(font, reveal[left], Vector2(10, lm_y + sw * 1.3 + 6), sw * 0.75, 230.0)
	_draw_box(font, right, Vector2(size.x - 240.0, 104), 230.0)
	_draw_melds(font, melds[right], Vector2(size.x - 240.0, lm_y), sw * 0.9)
	if not reveal[right].is_empty():
		_draw_tiles_row(font, reveal[right], Vector2(size.x - 240.0, lm_y + sw * 1.3 + 6), sw * 0.75, 230.0)

	# 中间：剩余牌数 + 四家牌河
	var cr = Rect2(cx - 70.0, cy - 26.0, 140.0, 52.0)
	draw_rect(cr, Color(0, 0, 0, 0.4))
	draw_string(font, Vector2(cr.position.x, cy - 4), "剩余 %d 张" % int(st.get("wall", 0)), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 18, Color.WHITE)
	draw_string(font, Vector2(cr.position.x, cy + 20), str(st.get("mode_name", "")), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 15, Color(1, 1, 1, 0.75))
	_draw_river(font, discs[me], Vector2(cx - 4.0 * rw, cy + 32.0), 8, rw, last_id)
	var trows = int(ceil(discs[top].size() / 8.0))
	_draw_river(font, discs[top], Vector2(cx - 4.0 * rw, cy - 32.0 - trows * rh), 8, rw, last_id)
	_draw_river(font, discs[left], Vector2(cx - 4.0 * rw - 14.0 - 6.0 * rw, cy - 1.5 * rh), 6, rw, last_id)
	_draw_river(font, discs[right], Vector2(cx + 4.0 * rw + 14.0, cy - 1.5 * rh), 6, rw, last_id)

	# 自己
	var cur = int(st.get("current_seat", -1))
	var info = "%s%s  %s  总分%d" % ["庄 " if me == int(st.get("dealer", -1)) else "", _nm(me), _que_text(me), _score_of(me)]
	var mw = _win_of(me)
	if not mw.is_empty():
		info += "  已胡%s，等其他人打完" % M.tname(int(mw["tile"]))
	draw_string(font, Vector2(14, size.y - _th - 22), info, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, 19, Color("#ffe066") if cur == me else Color.WHITE)
	var x0 = 20.0
	var y0 = size.y - _th - 6.0
	var q = _my_que()
	var can_pick = _my_turn() and (str(st.get("phase", "")) == "turn" or str(st.get("phase", "")) == "exchange")
	var shown = hand
	if not reveal[me].is_empty() and hand.is_empty():
		shown = reveal[me]
	for i in shown.size():
		var id = int(shown[i])
		var y = y0 - (18.0 if selected.has(id) else 0.0)
		var r = Rect2(Vector2(x0 + i * _tw, y), Vector2(_tw - 2, _th))
		_draw_tile(font, r, id / 4)
		if q >= 0 and M.tsuit(id / 4) == q:
			draw_rect(r, Color(0, 0, 0, 0.18))
		if can_pick:
			_tile_rects.append([id, r])
	var xe = x0 + shown.size() * _tw
	if drawn >= 0:
		xe += _tw * 0.4
		var y2 = y0 - (18.0 if selected.has(drawn) else 0.0)
		var r2 = Rect2(Vector2(xe, y2), Vector2(_tw - 2, _th))
		draw_set_transform(Vector2(0, -(1.0 - _ease((Time.get_ticks_msec() - _drawn_ms) / 240.0)) * 90.0))
		_draw_tile(font, r2, drawn / 4)
		draw_set_transform(Vector2.ZERO)
		if q >= 0 and M.tsuit(drawn / 4) == q:
			draw_rect(r2, Color(0, 0, 0, 0.18))
		if can_pick:
			_tile_rects.append([drawn, r2])
		xe += _tw
	_draw_melds(font, melds[me], Vector2(xe + _tw * 0.5, y0 + _th * 0.28), _tw * 0.72)

	if bool(st.get("over", false)):
		_draw_result(font)


func _draw_result(font: Font) -> void:
	var r = Rect2(size.x / 2.0 - 380.0, 70.0, 760.0, 330.0)
	draw_rect(r, Color(0, 0, 0, 0.8))
	var sc = st.get("scores", [0, 0, 0, 0])
	draw_string(font, r.position + Vector2(0, 34), "本局结算", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, Color("#ffe066"))
	var y = r.position.y + 70.0
	var reveal = st.get("reveal", [[], [], [], []])
	for s in 4:
		var w = _win_of(s)
		var line = "%s  %+d分" % [_nm(s), int(sc[s])]
		if not w.is_empty():
			var fn = []
			for x in w["fans"]:
				fn.append(str(x[0]))
			line += "  %s胡%s：%s（%d番）" % ["自摸" if bool(w["zimo"]) else "", M.tname(int(w["tile"])), "、".join(PackedStringArray(fn)), int(w["fan"])]
			if int(w.get("hits", 0)) > 0:
				line += " 中马%d" % int(w["hits"])
		draw_string(font, Vector2(r.position.x + 20, y), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40, 18, Color.WHITE)
		_draw_tiles_row(font, reveal[s], Vector2(r.position.x + 20, y + 6), 22.0, r.size.x - 40.0)
		y += 62.0
	var ch = st.get("checks", [])
	if not ch.is_empty():
		draw_string(font, Vector2(r.position.x + 20, y), _fix("；".join(PackedStringArray(ch))), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40, 16, Color("#ffcc80"))


# ---------------------------------------------------------------- 点牌

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var ph = str(st.get("phase", ""))
	for it in _tile_rects:
		var rr: Rect2 = it[1]
		if not rr.has_point(mb.position):
			continue
		var id = int(it[0])
		if ph == "exchange":
			if selected.has(id):
				selected.erase(id)
			elif selected.size() < 3:
				selected[id] = true
		elif ph == "turn":
			if selected.has(id):
				_try_discard(id)
				return
			selected.clear()
			selected[id] = true
		_refresh_buttons()
		queue_redraw()
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

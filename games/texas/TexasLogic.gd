extends RefCounted
## 德州扑克（只在房主端运行），2~6人；筹码只用来计分
## 每人起始筹码 stack，盲注 小/大；庄家按钮每局轮转；筹码输光的人下一局自动补满（记分照算）
## 流程：翻牌前 → 翻牌（3张）→ 转牌 → 河牌 → 比牌；可以弃牌、过牌、跟注、加注、全下；有人全下时按边池分

const RANK_TXT = ["", "", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const SUITS = ["♠", "♥", "♣", "♦"]
const CAT_NAMES = ["高牌", "一对", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺"]

var rules = {}
var order = []
var chips = {}
var start_chips = {}
var stack = 1000
var sb_amt = 10
var bb_amt = 20
var dealer = 0
var deck = []
var hole = {}
var board = []
var street = 0
var bet = {}
var total = {}
var folded = {}
var allin = {}
var acted = {}
var last_act = {}
var cur_bet = 0
var min_raise = 20
var turn_i = 0
var over = false
var results = []
var shown = {}
var winners_list = []
var event = ""
var rebuys = {}


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


static func rank(c: int) -> int:
	return c / 4 + 2


static func suit(c: int) -> int:
	return c % 4


static func card_text(c: int) -> String:
	return SUITS[suit(c)] + RANK_TXT[rank(c)]


func setup(seat_list: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	var st = str(rules.get("stack", "1000"))
	stack = int(st) if st.is_valid_int() else 1000
	var bl = str(rules.get("blinds", "10")).split("/")
	sb_amt = int(bl[0]) if str(bl[0]).is_valid_int() else 10
	bb_amt = sb_amt * 2
	order = []
	for s in seat_list:
		order.append(int(s))
	order.sort()
	var carry = rules.get("_carry", {})
	if typeof(carry) != TYPE_DICTIONARY:
		carry = {}
	var cc = carry.get("chips", {})
	chips = {}
	rebuys = {}
	for s in order:
		var v = int(cc.get(str(s), stack))
		rebuys[s] = int(carry.get("rebuys", {}).get(str(s), 0))
		if v <= 0:
			v = stack
			rebuys[s] = int(rebuys[s]) + 1
		chips[s] = v
	start_chips = chips.duplicate()
	var prev_d = int(carry.get("dealer", -1))
	dealer = 0
	if prev_d >= 0:
		for k in order.size():
			if int(order[k]) > prev_d:
				dealer = k
				break
	else:
		dealer = (rn - 1) % order.size()
	deck = []
	for i in 52:
		deck.append(i)
	deck.shuffle()
	hole = {}
	bet = {}
	total = {}
	folded = {}
	allin = {}
	acted = {}
	last_act = {}
	shown = {}
	for s in order:
		hole[s] = [deck.pop_back(), deck.pop_back()]
		bet[s] = 0
		total[s] = 0
		folded[s] = false
		allin[s] = false
		last_act[s] = ""
	board = []
	street = 0
	over = false
	results = []
	winners_list = []
	var n = order.size()
	var sb_i = dealer if n == 2 else (dealer + 1) % n
	var bb_i = (sb_i + 1) % n
	_post(int(order[sb_i]), sb_amt, "小盲")
	_post(int(order[bb_i]), bb_amt, "大盲")
	cur_bet = bb_amt
	min_raise = bb_amt
	turn_i = (bb_i + 1) % n
	event = "新的一局：%s 是庄家，%s 下小盲 %d，%s 下大盲 %d" % [_lbl(int(order[dealer])), _lbl(int(order[sb_i])), sb_amt, _lbl(int(order[bb_i])), bb_amt]
	_seek(true)


func _post(s: int, amt: int, txt: String) -> void:
	var a = mini(amt, int(chips[s]))
	chips[s] = int(chips[s]) - a
	bet[s] = int(bet[s]) + a
	total[s] = int(total[s]) + a
	last_act[s] = "%s %d" % [txt, a]
	if int(chips[s]) == 0:
		allin[s] = true


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	return int(order[turn_i])


func bot_delay() -> float:
	return 0.9


func _can_act(s: int) -> bool:
	return not bool(folded[s]) and not bool(allin[s])


func _live() -> Array:
	var out = []
	for s in order:
		if not bool(folded[s]):
			out.append(int(s))
	return out


func pot() -> int:
	var p = 0
	for s in order:
		p += int(total[s])
	return p


func to_call(s: int) -> int:
	return maxi(0, cur_bet - int(bet[s]))


# ---------------------------------------------------------------- 操作

func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if seat != current_seat():
		return "还没轮到你"
	var t = str(a.get("type", ""))
	var tc = to_call(seat)
	if t == "fold":
		folded[seat] = true
		last_act[seat] = "弃牌"
		event = "%s 弃牌" % _lbl(seat)
	elif t == "check":
		if tc > 0:
			return "要跟 %d 才能继续，不能过牌" % tc
		last_act[seat] = "过牌"
		event = "%s 过牌" % _lbl(seat)
	elif t == "call":
		if tc <= 0:
			return "不用跟注，可以直接过牌"
		var amt = mini(tc, int(chips[seat]))
		_put(seat, amt)
		last_act[seat] = "跟注 %d" % amt if not bool(allin[seat]) else "全下 %d" % int(bet[seat])
		event = "%s %s" % [_lbl(seat), last_act[seat]]
	elif t == "raise" or t == "allin":
		var maxto = int(bet[seat]) + int(chips[seat])
		if t == "allin" and maxto <= cur_bet:
			_put(seat, int(chips[seat]))
			last_act[seat] = "全下 %d" % int(bet[seat])
			event = "%s %s" % [_lbl(seat), last_act[seat]]
			acted[seat] = true
			_advance()
			return ""
		var to = maxto if t == "allin" else int(a.get("to", 0))
		if to > maxto:
			return "筹码不够"
		if to <= cur_bet:
			return "加注必须比现在的下注 %d 多" % cur_bet
		if to < cur_bet + min_raise and to != maxto:
			return "最少要加到 %d" % (cur_bet + min_raise)
		var raise_by = to - cur_bet
		_put(seat, to - int(bet[seat]))
		if raise_by >= min_raise:
			min_raise = raise_by
			for s in order:
				acted[s] = false
		cur_bet = maxi(cur_bet, to)
		last_act[seat] = ("全下 %d" % to) if bool(allin[seat]) else ("加注到 %d" % to)
		event = "%s %s" % [_lbl(seat), last_act[seat]]
	else:
		return "无效操作"
	acted[seat] = true
	_advance()
	return ""


func _put(s: int, amt: int) -> void:
	var a = mini(amt, int(chips[s]))
	chips[s] = int(chips[s]) - a
	bet[s] = int(bet[s]) + a
	total[s] = int(total[s]) + a
	if int(chips[s]) == 0:
		allin[s] = true


func _round_done() -> bool:
	for s in order:
		if _can_act(int(s)):
			if not bool(acted.get(s, false)) or int(bet[s]) < cur_bet:
				return false
	return true


func _advance() -> void:
	var live = _live()
	if live.size() == 1:
		_award_single(int(live[0]))
		return
	if _round_done():
		_next_street()
		return
	_seek(false)


func _seek(include_current: bool) -> void:
	var n = order.size()
	for k in range(0 if include_current else 1, n + 1):
		var i = (turn_i + k) % n
		var s = int(order[i])
		if _can_act(s) and (not bool(acted.get(s, false)) or int(bet[s]) < cur_bet):
			turn_i = i
			return
	_next_street()


func _next_street() -> void:
	for s in order:
		bet[s] = 0
		acted[s] = false
		if not bool(folded[s]) and not bool(allin[s]):
			last_act[s] = ""
	cur_bet = 0
	min_raise = bb_amt
	street += 1
	if street == 1:
		deck.pop_back()
		board += [deck.pop_back(), deck.pop_back(), deck.pop_back()]
		event = "翻牌：%s" % _cards_text(board)
	elif street == 2 or street == 3:
		deck.pop_back()
		board.append(deck.pop_back())
		event = "%s：%s" % ["转牌" if street == 2 else "河牌", card_text(int(board[board.size() - 1]))]
	else:
		_showdown()
		return
	var can = 0
	for s in order:
		if _can_act(int(s)):
			can += 1
	if can <= 1:
		_next_street()
		return
	var n = order.size()
	turn_i = (dealer + 1) % n
	_seek(true)


func _cards_text(cs: Array) -> String:
	var parts = []
	for c in cs:
		parts.append(card_text(int(c)))
	return " ".join(PackedStringArray(parts))


func _award_single(w: int) -> void:
	var p = pot()
	chips[w] = int(chips[w]) + p
	results = [{"seat": w, "won": p, "hand": ""}]
	winners_list = [w]
	event = "其他人都弃牌了，%s 赢得底池 %d" % [_lbl(w), p]
	over = true


func _showdown() -> void:
	street = 4
	var live = _live()
	var keys = {}
	for s in live:
		keys[s] = best7(hole[s] + board)
		shown[s] = true
	var levels = []
	for s in order:
		var t = int(total[s])
		if t > 0 and not levels.has(t):
			levels.append(t)
	levels.sort()
	var won = {}
	var prev = 0
	var n = order.size()
	for lv in levels:
		var amt = 0
		for s in order:
			amt += mini(int(total[s]), lv) - mini(int(total[s]), prev)
		var elig = []
		for s in live:
			if int(total[s]) >= lv:
				elig.append(int(s))
		prev = lv
		if elig.is_empty() or amt <= 0:
			continue
		var best = -1
		var ws = []
		for s in elig:
			var k = int(keys[s][0])
			if k > best:
				best = k
				ws = [s]
			elif k == best:
				ws.append(s)
		var share = amt / ws.size()
		var rem = amt - share * ws.size()
		for k2 in n:
			var s2 = int(order[(dealer + 1 + k2) % n])
			if ws.has(s2):
				won[s2] = int(won.get(s2, 0)) + share + (rem if rem > 0 else 0)
				rem = 0
	results = []
	winners_list = []
	var parts = []
	for s in won:
		chips[s] = int(chips[s]) + int(won[s])
		winners_list.append(int(s))
		parts.append("%s 赢 %d（%s）" % [_lbl(int(s)), int(won[s]), hand_name(int(keys[s][0]))])
	for s in live:
		results.append({"seat": int(s), "won": int(won.get(s, 0)), "hand": hand_name(int(keys[s][0])), "best": keys[s][1]})
	event = "比牌：" + "，".join(PackedStringArray(parts))
	over = true


func winners() -> Array:
	return winners_list.duplicate()


func round_scores() -> Array:
	var out = []
	var mx = 0
	for s in order:
		mx = maxi(mx, int(s))
	for i in mx + 1:
		out.append(0)
	for s in order:
		out[int(s)] = int(chips[s]) - int(start_chips[s])
	return out


func carry_out() -> Dictionary:
	var cc = {}
	var rb = {}
	for s in order:
		cc[str(s)] = int(chips[s])
		rb[str(s)] = int(rebuys[s])
	return {"chips": cc, "dealer": int(order[dealer]), "rebuys": rb}


# ---------------------------------------------------------------- 牌力

## 5张牌的大小：返回一个整数，越大越好
static func eval5(cs: Array) -> int:
	var rs = []
	var cnt = {}
	var flush = true
	var s0 = suit(int(cs[0]))
	for c in cs:
		var r = rank(int(c))
		rs.append(r)
		cnt[r] = int(cnt.get(r, 0)) + 1
		if suit(int(c)) != s0:
			flush = false
	rs.sort()
	var straight_hi = 0
	if cnt.size() == 5:
		if int(rs[4]) - int(rs[0]) == 4:
			straight_hi = int(rs[4])
		elif rs == [2, 3, 4, 5, 14]:
			straight_hi = 5
	var groups = []
	for r in cnt:
		groups.append([int(cnt[r]), int(r)])
	groups.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var cat = 0
	var ranks = []
	if straight_hi > 0 and flush:
		cat = 8
		ranks = [straight_hi]
	elif int(groups[0][0]) == 4:
		cat = 7
	elif int(groups[0][0]) == 3 and groups.size() == 2:
		cat = 6
	elif flush:
		cat = 5
	elif straight_hi > 0:
		cat = 4
		ranks = [straight_hi]
	elif int(groups[0][0]) == 3:
		cat = 3
	elif int(groups[0][0]) == 2 and int(groups[1][0]) == 2:
		cat = 2
	elif int(groups[0][0]) == 2:
		cat = 1
	if ranks.is_empty():
		for g in groups:
			ranks.append(int(g[1]))
	var key = cat
	for i in 5:
		key = key * 16 + (int(ranks[i]) if i < ranks.size() else 0)
	return key


## 7张里挑最好的5张：返回 [大小, 5张牌]
static func best7(cs: Array) -> Array:
	var n = cs.size()
	if n <= 5:
		return [eval5(cs), cs.duplicate()]
	var best = -1
	var bc = []
	for a in n:
		for b in range(a + 1 if n == 7 else a, n):
			if n == 6 and b != a:
				continue
			var five = []
			for i in n:
				if i != a and i != b:
					five.append(cs[i])
			var k = eval5(five)
			if k > best:
				best = k
				bc = five
	return [best, bc]


static func hand_name(key: int) -> String:
	var cat = key >> 20
	if cat == 8 and ((key >> 16) & 15) == 14:
		return "皇家同花顺"
	return CAT_NAMES[clampi(cat, 0, 8)]


# ---------------------------------------------------------------- 状态

func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(v: int) -> Dictionary:
	var ps = []
	for s in order:
		var show = s == v or bool(shown.get(s, false))
		ps.append({"seat": int(s), "chips": int(chips[s]), "bet": int(bet[s]), "total": int(total[s]), "folded": bool(folded[s]), "allin": bool(allin[s]), "act": str(last_act[s]), "cards": hole[s].duplicate() if show else [], "rebuys": int(rebuys[s])})
	var me = {}
	if hole.has(v) and not over and current_seat() == v:
		me = {"to_call": to_call(v), "min_to": cur_bet + min_raise, "max_to": int(bet[v]) + int(chips[v]), "bet": int(bet[v])}
	var my_hand = ""
	if hole.has(v) and board.size() >= 3:
		my_hand = hand_name(int(best7(hole[v] + board)[0]))
	return {
		"players": ps,
		"dealer": int(order[dealer]),
		"board": board.duplicate(),
		"street": street,
		"pot": pot(),
		"cur_bet": cur_bet,
		"me": me,
		"my_hand": my_hand,
		"blinds": [sb_amt, bb_amt],
		"current_seat": current_seat(),
		"results": results.duplicate(true),
		"over": over,
		"winners": winners_list.duplicate(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func _strength(s: int) -> float:
	var h = hole[s]
	var r1 = rank(int(h[0]))
	var r2 = rank(int(h[1]))
	if board.is_empty():
		var hi = maxi(r1, r2)
		var lo = mini(r1, r2)
		var v = (hi + lo) / 28.0 * 0.6
		if r1 == r2:
			v = 0.5 + r1 / 28.0
		if suit(int(h[0])) == suit(int(h[1])):
			v += 0.05
		if hi - lo == 1:
			v += 0.04
		return clampf(v, 0.0, 1.0)
	var key = int(best7(h + board)[0])
	var cat = key >> 20
	var base = [0.12, 0.42, 0.66, 0.76, 0.83, 0.87, 0.93, 0.98, 0.99][cat]
	if cat == 1:
		var pr = (key >> 16) & 15
		base += (pr - 8) * 0.015
		var on_board = 0
		for c in board:
			if rank(int(c)) == pr:
				on_board += 1
		if on_board >= 2:
			base -= 0.25
	if street < 3:
		var sc = {}
		for c in h + board:
			sc[suit(int(c))] = int(sc.get(suit(int(c)), 0)) + 1
		for k in sc:
			if int(sc[k]) == 4:
				base += 0.12
	return clampf(base, 0.0, 1.0)


func bot_action(s: int) -> Dictionary:
	if over:
		return {}
	var tc = to_call(s)
	var p = pot()
	var str_v = _strength(s) + randf_range(-0.06, 0.06)
	var need = float(tc) / float(maxi(p + tc, 1))
	var maxto = int(bet[s]) + int(chips[s])
	if str_v > 0.8 and randf() < 0.6 or (randf() < 0.05 and tc == 0):
		var to = cur_bet + maxi(min_raise, p / 2)
		if to >= maxto:
			return {"type": "allin"}
		return {"type": "raise", "to": to}
	if tc == 0:
		return {"type": "check"}
	if str_v > need + 0.12 or (tc <= bb_amt and str_v > 0.3):
		return {"type": "call"}
	return {"type": "fold"}

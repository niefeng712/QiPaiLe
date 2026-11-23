extends RefCounted
## 炸金花（只在房主端运行），2~6人；筹码只用来计分
## 每人先下底注，发3张牌。可以闷着打（不看牌），也可以看牌；看过牌的人跟注、加注都要付双倍
## 轮到你时：跟注 / 加注（注额翻倍，有上限）/ 比牌（付一次跟注的钱，和一个人比，输的出局；牌一样大时主动比牌的人输）/ 弃牌
## 筹码不够跟注时可以「孤注一掷」：押上全部筹码和所有人比，全赢才算赢
## 只剩一个人就赢走全部底池；比满规定轮数后所有人开牌比大小
## 牌型从大到小：豹子 > 顺金 > 金花 > 顺子 > 对子 > 单张；A23 是最小的顺子；可选「235 吃豹子」

const RANK_TXT = ["", "", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const SUITS = ["♠", "♥", "♣", "♦"]
const CAT_NAMES = ["单张", "对子", "顺子", "金花", "顺金", "豹子"]

var rules = {}
var order = []
var chips = {}
var start_chips = {}
var rebuys = {}
var stack = 1000
var base = 10
var cap_mult = 10
var max_rounds = 10
var special235 = true
var first_no_compare = true
var dealer_i = 0
var hands = {}
var seen = {}
var folded = {}
var paid = {}
var turns = {}
var last_act = {}
var stake = 10
var turn_i = 0
var compares = []
var over = false
var winners_list = []
var event = ""


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


static func rank(c: int) -> int:
	return c / 4 + 2


static func suit(c: int) -> int:
	return c % 4


static func card_text(c: int) -> String:
	return SUITS[suit(c)] + RANK_TXT[rank(c)]


# ---------------------------------------------------------------- 牌力

static func key(h: Array) -> int:
	var rs = [rank(int(h[0])), rank(int(h[1])), rank(int(h[2]))]
	rs.sort()
	rs.reverse()
	var flush = suit(int(h[0])) == suit(int(h[1])) and suit(int(h[1])) == suit(int(h[2]))
	var a = int(rs[0])
	var b = int(rs[1])
	var c = int(rs[2])
	var straight_hi = 0
	if a == b + 1 and b == c + 1:
		straight_hi = a
	elif a == 14 and b == 3 and c == 2:
		straight_hi = 3
	var cat = 0
	var k = [a, b, c]
	if a == b and b == c:
		cat = 5
		k = [a, 0, 0]
	elif straight_hi > 0 and flush:
		cat = 4
		k = [straight_hi, 0, 0]
	elif flush:
		cat = 3
	elif straight_hi > 0:
		cat = 2
		k = [straight_hi, 0, 0]
	elif a == b or b == c:
		cat = 1
		var pr = b
		var kick = c if a == b else a
		k = [pr, kick, 0]
	return cat * 4096 + int(k[0]) * 256 + int(k[1]) * 16 + int(k[2])


static func category(k: int) -> int:
	return k / 4096


static func hand_name(h: Array) -> String:
	if h.size() != 3:
		return ""
	return CAT_NAMES[category(key(h))]


static func is235(h: Array) -> bool:
	var rs = [rank(int(h[0])), rank(int(h[1])), rank(int(h[2]))]
	rs.sort()
	return rs == [2, 3, 5] and category(key(h)) == 0


## a 比 b：1 = a 大，-1 = b 大，0 = 一样大
static func compare(a: Array, b: Array, sp: bool) -> int:
	var ka = key(a)
	var kb = key(b)
	if sp:
		if is235(a) and category(kb) == 5:
			return 1
		if is235(b) and category(ka) == 5:
			return -1
	if ka > kb:
		return 1
	if ka < kb:
		return -1
	return 0


# ---------------------------------------------------------------- 流程

func setup(seat_list: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	var sv = str(rules.get("stack", "1000"))
	stack = int(sv) if sv.is_valid_int() else 1000
	var bv = str(rules.get("base", "10"))
	base = int(bv) if bv.is_valid_int() else 10
	var mr = str(rules.get("rounds", "10"))
	max_rounds = int(mr) if mr.is_valid_int() else 10
	special235 = str(rules.get("s235", "on")) == "on"
	first_no_compare = str(rules.get("first", "on")) == "on"
	order = []
	for s in seat_list:
		order.append(int(s))
	order.sort()
	var carry = rules.get("_carry", {})
	if typeof(carry) != TYPE_DICTIONARY:
		carry = {}
	var cc = carry.get("chips", {})
	var rb = carry.get("rebuys", {})
	chips = {}
	rebuys = {}
	for s in order:
		var v = int(cc.get(str(s), stack))
		rebuys[s] = int(rb.get(str(s), 0))
		if v < base:
			v = stack
			rebuys[s] = int(rebuys[s]) + 1
		chips[s] = v
	start_chips = chips.duplicate()
	var prev_d = int(carry.get("dealer", -1))
	dealer_i = (rn - 1) % order.size()
	if prev_d >= 0:
		dealer_i = 0
		for k in order.size():
			if int(order[k]) > prev_d:
				dealer_i = k
				break
	var deck = []
	for i in 52:
		deck.append(i)
	deck.shuffle()
	hands = {}
	seen = {}
	folded = {}
	paid = {}
	turns = {}
	last_act = {}
	for s in order:
		hands[s] = [deck.pop_back(), deck.pop_back(), deck.pop_back()]
		seen[s] = false
		folded[s] = false
		paid[s] = 0
		turns[s] = 0
		_pay(s, base)
		last_act[s] = "底注 %d" % base
	stake = base
	compares = []
	over = false
	winners_list = []
	turn_i = (dealer_i + 1) % order.size()
	event = "每人下底注 %d，%s 先说话" % [base, _lbl(int(order[turn_i]))]


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	return int(order[turn_i])


func bot_delay() -> float:
	return 1.0


func pot() -> int:
	var p = 0
	for s in order:
		p += int(paid[s])
	return p


func _pay(s: int, amt: int) -> void:
	var a = mini(amt, int(chips[s]))
	chips[s] = int(chips[s]) - a
	paid[s] = int(paid[s]) + a


func cost(s: int) -> int:
	return stake * (2 if bool(seen[s]) else 1)


func _active() -> Array:
	var out = []
	for s in order:
		if not bool(folded[s]):
			out.append(int(s))
	return out


func can_compare(s: int) -> bool:
	return not first_no_compare or int(turns[s]) >= 1


func max_stake() -> int:
	return base * 10


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if not hands.has(seat):
		return "你不在这局里"
	var t = str(a.get("type", ""))
	if t == "look":
		if bool(seen[seat]):
			return "已经看过牌了"
		if bool(folded[seat]):
			return "你已经出局了"
		seen[seat] = true
		last_act[seat] = "看牌"
		event = "%s 看了牌" % _lbl(seat)
		return ""
	if t == "fold":
		if bool(folded[seat]):
			return "你已经出局了"
		var was_turn = seat == current_seat()
		folded[seat] = true
		last_act[seat] = "弃牌"
		event = "%s 弃牌" % _lbl(seat)
		if was_turn:
			_advance()
		else:
			_check_single()
		return ""
	if seat != current_seat():
		return "还没轮到你"
	var c = cost(seat)
	if t == "call":
		if int(chips[seat]) < c:
			return "筹码不够跟注，只能弃牌或孤注一掷"
		_pay(seat, c)
		last_act[seat] = "跟注 %d" % c
		event = "%s 跟注 %d" % [_lbl(seat), c]
	elif t == "raise":
		if stake >= max_stake():
			return "已经是最高注了"
		var ns = mini(stake * 2, max_stake())
		var c2 = ns * (2 if bool(seen[seat]) else 1)
		if int(chips[seat]) < c2:
			return "筹码不够加注"
		stake = ns
		_pay(seat, c2)
		last_act[seat] = "加注 %d" % c2
		event = "%s 加注到 %d" % [_lbl(seat), c2]
	elif t == "compare":
		if not can_compare(seat):
			return "第一轮不能比牌"
		var tg = int(a.get("target", -1))
		if tg == seat or not hands.has(tg) or bool(folded[tg]):
			return "请选一个还在牌局里的玩家比牌"
		if int(chips[seat]) < c:
			return "筹码不够比牌，只能孤注一掷"
		_pay(seat, c)
		var r = compare(hands[seat], hands[tg], special235)
		var loser = seat if r <= 0 else tg
		folded[loser] = true
		last_act[seat] = "比牌"
		last_act[loser] = "比牌输了"
		compares.append([seat, tg, loser])
		event = "%s 和 %s 比牌，%s 输了" % [_lbl(seat), _lbl(tg), _lbl(loser)]
	elif t == "allin":
		if int(chips[seat]) >= c:
			return "筹码够跟注，不需要孤注一掷"
		_pay(seat, int(chips[seat]))
		var lose = false
		for o in _active():
			if o != seat and compare(hands[seat], hands[o], special235) <= 0:
				lose = true
		if lose:
			folded[seat] = true
			last_act[seat] = "孤注一掷失败"
			event = "%s 孤注一掷，没有赢过所有人，出局" % _lbl(seat)
		else:
			for o in _active():
				if o != seat:
					folded[o] = true
					last_act[o] = "被孤注一掷击败"
			last_act[seat] = "孤注一掷成功"
			event = "%s 孤注一掷，赢过了所有人！" % _lbl(seat)
	else:
		return "无效操作"
	turns[seat] = int(turns[seat]) + 1
	_advance()
	return ""


func _check_single() -> bool:
	var act = _active()
	if act.size() <= 1:
		_win([int(act[0])] if act.size() == 1 else [current_seat()], "")
		return true
	return false


func _advance() -> void:
	if _check_single():
		return
	var n = order.size()
	for k in range(1, n + 1):
		var i = (turn_i + k) % n
		var s = int(order[i])
		if not bool(folded[s]):
			turn_i = i
			break
	if int(turns[current_seat()]) >= max_rounds:
		_showdown()


func _showdown() -> void:
	var act = _active()
	var best = [int(act[0])]
	for k in range(1, act.size()):
		var s = int(act[k])
		var r = compare(hands[s], hands[best[0]], special235)
		if r > 0:
			best = [s]
		elif r == 0:
			best.append(s)
	for s in act:
		if not best.has(int(s)):
			last_act[s] = "开牌输了"
	_win(best, "已经比满%d轮，所有人开牌：" % max_rounds)


func _win(ws: Array, prefix: String) -> void:
	var p = pot()
	var share = p / ws.size()
	var rem = p - share * ws.size()
	for k in ws.size():
		var s = int(ws[k])
		chips[s] = int(chips[s]) + share + (rem if k == 0 else 0)
	winners_list = ws.duplicate()
	over = true
	var names = []
	for s in ws:
		names.append(_lbl(int(s)))
	event = "%s%s 赢得底池 %d（%s）" % [prefix, "、".join(PackedStringArray(names)), p, hand_name(hands[ws[0]])]


func winners() -> Array:
	return winners_list.duplicate()


func round_scores() -> Array:
	var mx = 0
	for s in order:
		mx = maxi(mx, int(s))
	var out = []
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
	return {"chips": cc, "dealer": int(order[dealer_i]), "rebuys": rb}


# ---------------------------------------------------------------- 状态

func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(v: int) -> Dictionary:
	var ps = []
	for s in order:
		var show = over or (s == v and bool(seen[s]))
		ps.append({
			"seat": int(s),
			"chips": int(chips[s]),
			"paid": int(paid[s]),
			"seen": bool(seen[s]),
			"folded": bool(folded[s]),
			"act": str(last_act[s]),
			"cards": hands[s].duplicate() if show else [],
			"hand": hand_name(hands[s]) if show else "",
			"rebuys": int(rebuys[s]),
		})
	var me = {}
	if hands.has(v) and not over:
		me = {"seen": bool(seen[v]), "folded": bool(folded[v]), "chips": int(chips[v])}
		if v == current_seat():
			var c = cost(v)
			var ns = mini(stake * 2, max_stake())
			me["cost"] = c
			me["can_call"] = int(chips[v]) >= c
			me["raise_cost"] = ns * (2 if bool(seen[v]) else 1)
			me["can_raise"] = stake < max_stake() and int(chips[v]) >= int(me["raise_cost"])
			me["can_compare"] = can_compare(v) and int(chips[v]) >= c
			me["need_allin"] = int(chips[v]) < c
			var tg = []
			for o in _active():
				if o != v:
					tg.append(o)
			me["targets"] = tg
	var cur = current_seat()
	return {
		"players": ps,
		"dealer": int(order[dealer_i]),
		"pot": pot(),
		"stake": stake,
		"base": base,
		"round": (int(turns[cur]) + 1) if cur >= 0 else 0,
		"max_rounds": max_rounds,
		"me": me,
		"current_seat": cur,
		"compares": compares.duplicate(true),
		"over": over,
		"winners": winners_list.duplicate(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func _strength(s: int) -> float:
	var k = key(hands[s])
	var cat = category(k)
	if cat == 0:
		var hi = (k / 256) % 16
		if special235 and is235(hands[s]):
			return 0.05
		return clampf((hi - 8) * 0.07, 0.02, 0.45)
	if cat == 1:
		return 0.55 + ((k / 256) % 16) * 0.012
	return [0.0, 0.0, 0.8, 0.86, 0.95, 0.99][cat]


func _rand_target(s: int) -> int:
	var tg = []
	for o in _active():
		if o != s:
			tg.append(o)
	return int(tg[randi() % tg.size()])


func timeout_action(_s: int) -> Dictionary:
	return {"type": "fold"}


func bot_action(s: int) -> Dictionary:
	if over or s != current_seat():
		return {}
	if not bool(seen[s]) and (int(turns[s]) >= 2 or stake >= base * 4 or randf() < 0.35):
		return {"type": "look"}
	var c = cost(s)
	var st = _strength(s) if bool(seen[s]) else 0.5
	if int(chips[s]) < c:
		return {"type": "allin"} if st >= 0.6 or (not bool(seen[s]) and randf() < 0.4) else {"type": "fold"}
	var cmp = can_compare(s)
	var t = int(turns[s])
	if bool(seen[s]):
		if st < 0.2:
			if cmp and randf() < 0.25:
				return {"type": "compare", "target": _rand_target(s)}
			return {"type": "fold"}
		if st < 0.45:
			if cmp and (t >= 3 or stake >= base * 4):
				return {"type": "compare", "target": _rand_target(s)}
			if stake >= base * 8 and randf() < 0.5:
				return {"type": "fold"}
			return {"type": "call"}
		if st < 0.75:
			if cmp and t >= 4 and randf() < 0.5:
				return {"type": "compare", "target": _rand_target(s)}
			return {"type": "call"}
		if stake < max_stake() and int(chips[s]) >= mini(stake * 2, max_stake()) * 2 and randf() < 0.6:
			return {"type": "raise"}
		if cmp and t >= 5:
			return {"type": "compare", "target": _rand_target(s)}
		return {"type": "call"}
	if stake < max_stake() and randf() < 0.12 and int(chips[s]) >= stake * 2:
		return {"type": "raise"}
	if cmp and t >= 4 and randf() < 0.3:
		return {"type": "compare", "target": _rand_target(s)}
	return {"type": "call"}

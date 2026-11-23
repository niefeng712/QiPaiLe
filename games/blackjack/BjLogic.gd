extends RefCounted
## 21点（只在房主端运行）：1~5个玩家，一起对电脑庄家；筹码只用来计分
## 流程：每人下注 → 发牌（每人两张明牌，庄家一明一暗）→ 每人轮流 要牌/停牌/加倍/分牌 → 庄家补牌到17点以上 → 结算
## 庄家明牌是A或10点时先看暗牌，庄家是黑杰克就直接结算
## 赔率：赢了1赔1；黑杰克（头两张就是21点）1赔1.5；平局退回；爆牌（超过21点）直接输
## 分牌：头两张点数一样可以分成两手（只能分一次）；分开的A每手只能再拿一张

const RANK_TXT = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUITS = ["♠", "♥", "♣", "♦"]
const BETS = [10, 20, 50, 100, 200]
const DECKS = 4

var rules = {}
var order = []
var chips = {}
var start_chips = {}
var rebuys = {}
var stack = 1000
var h17 = false
var shoe = []
var phase = "bet"
var bets = {}
var hands = {}
var dealer = []
var seat_i = 0
var hand_i = 0
var over = false
var dealer_bj = false
var winners_list = []
var event = ""


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


static func rank(c: int) -> int:
	return (c % 52) / 4 + 1


static func suit(c: int) -> int:
	return c % 4


static func card_text(c: int) -> String:
	return SUITS[suit(c)] + RANK_TXT[rank(c)]


static func value(c: int) -> int:
	var r = rank(c)
	if r == 1:
		return 11
	return mini(r, 10)


## [点数, 是否软牌（A当11点算）]
static func total(cards: Array) -> Array:
	var t = 0
	var aces = 0
	for c in cards:
		var r = rank(int(c))
		if r == 1:
			aces += 1
			t += 1
		else:
			t += mini(r, 10)
	var soft = false
	if aces > 0 and t + 10 <= 21:
		t += 10
		soft = true
	return [t, soft]


static func is_bj(cards: Array) -> bool:
	return cards.size() == 2 and int(total(cards)[0]) == 21


func setup(seat_list: Array, game_rules: Dictionary, _rn: int) -> void:
	rules = game_rules.duplicate(true)
	var sv = str(rules.get("stack", "1000"))
	stack = int(sv) if sv.is_valid_int() else 1000
	h17 = str(rules.get("dealer", "s17")) == "h17"
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
		if v < BETS[0]:
			v = stack
			rebuys[s] = int(rebuys[s]) + 1
		chips[s] = v
	start_chips = chips.duplicate()
	shoe = []
	for d in DECKS:
		for i in 52:
			shoe.append(d * 52 + i)
	shoe.shuffle()
	phase = "bet"
	bets = {}
	hands = {}
	dealer = []
	seat_i = 0
	hand_i = 0
	over = false
	dealer_bj = false
	winners_list = []
	event = "请下注"


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	if phase == "bet":
		for s in order:
			if not bets.has(s):
				return int(s)
		return -1
	if phase == "play":
		return int(order[seat_i])
	return -1


func bot_delay() -> float:
	return 0.8


func _draw_card() -> int:
	return int(shoe.pop_back())


func _new_hand(cards: Array, bet: int, from_split: bool) -> Dictionary:
	return {"cards": cards, "bet": bet, "done": false, "doubled": false, "split": from_split, "split_aces": false, "result": "", "payout": 0}


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if not chips.has(seat):
		return "你不在这局里"
	var t = str(a.get("type", ""))
	if phase == "bet":
		if t != "bet":
			return "请先下注"
		if bets.has(seat):
			return "你已经下过注了"
		var amt = int(a.get("amount", 0))
		if not BETS.has(amt):
			return "下注金额不对"
		if amt > int(chips[seat]):
			return "筹码不够"
		bets[seat] = amt
		chips[seat] = int(chips[seat]) - amt
		event = "%s 下注 %d" % [_lbl(seat), amt]
		if bets.size() >= order.size():
			_deal()
		return ""
	if phase != "play":
		return "无效操作"
	if seat != current_seat():
		return "还没轮到你"
	var h = hands[seat][hand_i]
	var tt = int(total(h["cards"])[0])
	if t == "hit":
		if bool(h["split_aces"]):
			return "分开的A只能拿一张牌"
		h["cards"].append(_draw_card())
		tt = int(total(h["cards"])[0])
		event = "%s 要牌，现在 %d 点" % [_lbl(seat), tt]
		if tt > 21:
			h["done"] = true
			h["result"] = "爆牌"
			event = "%s 要牌，%d 点爆了" % [_lbl(seat), tt]
		elif tt == 21:
			h["done"] = true
	elif t == "stand":
		h["done"] = true
		event = "%s 停牌（%d 点）" % [_lbl(seat), tt]
	elif t == "double":
		if h["cards"].size() != 2 or bool(h["split_aces"]):
			return "只有头两张牌时才能加倍"
		if int(chips[seat]) < int(h["bet"]):
			return "筹码不够加倍"
		chips[seat] = int(chips[seat]) - int(h["bet"])
		h["bet"] = int(h["bet"]) * 2
		h["doubled"] = true
		h["cards"].append(_draw_card())
		h["done"] = true
		tt = int(total(h["cards"])[0])
		if tt > 21:
			h["result"] = "爆牌"
		event = "%s 加倍，拿到第三张牌，%d 点" % [_lbl(seat), tt]
	elif t == "split":
		if not can_split(seat):
			return "这手牌不能分"
		var b = int(h["bet"])
		chips[seat] = int(chips[seat]) - b
		var c1 = int(h["cards"][0])
		var c2 = int(h["cards"][1])
		var aces = rank(c1) == 1
		var h1 = _new_hand([c1, _draw_card()], b, true)
		var h2 = _new_hand([c2, _draw_card()], b, true)
		if aces:
			h1["split_aces"] = true
			h2["split_aces"] = true
			h1["done"] = true
			h2["done"] = true
		hands[seat] = [h1, h2]
		event = "%s 分牌" % _lbl(seat)
	else:
		return "无效操作"
	_seek()
	return ""


func can_split(seat: int) -> bool:
	if phase != "play" or seat != current_seat() or hands[seat].size() != 1:
		return false
	var h = hands[seat][0]
	if h["cards"].size() != 2 or bool(h["done"]):
		return false
	return value(int(h["cards"][0])) == value(int(h["cards"][1])) and int(chips[seat]) >= int(h["bet"])


func _deal() -> void:
	hands = {}
	for s in order:
		hands[s] = [_new_hand([_draw_card(), _draw_card()], int(bets[s]), false)]
	dealer = [_draw_card(), _draw_card()]
	phase = "play"
	var up = value(int(dealer[0]))
	if (up == 11 or up == 10) and is_bj(dealer):
		dealer_bj = true
		event = "庄家是黑杰克！"
		_settle()
		return
	var bjs = []
	for s in order:
		var h = hands[s][0]
		if is_bj(h["cards"]):
			h["done"] = true
			bjs.append(_lbl(int(s)))
	event = "发牌完成" + ("，%s 拿到黑杰克！" % "、".join(PackedStringArray(bjs)) if not bjs.is_empty() else "")
	seat_i = 0
	hand_i = 0
	_seek()


func _seek() -> void:
	while seat_i < order.size():
		var hs = hands[order[seat_i]]
		while hand_i < hs.size():
			if not bool(hs[hand_i]["done"]):
				return
			hand_i += 1
		seat_i += 1
		hand_i = 0
	_dealer_play()


func _dealer_play() -> void:
	var need = false
	for s in order:
		for h in hands[s]:
			if str(h["result"]) != "爆牌" and not (is_bj(h["cards"]) and not bool(h["split"])):
				need = true
	while need:
		var tt = total(dealer)
		var t = int(tt[0])
		if t < 17 or (h17 and t == 17 and bool(tt[1])):
			dealer.append(_draw_card())
		else:
			break
	_settle()


func _settle() -> void:
	phase = "done"
	over = true
	var dt = int(total(dealer)[0])
	var dbust = dt > 21
	var parts = []
	for s in order:
		var net = 0
		for h in hands[s]:
			var b = int(h["bet"])
			var pt = int(total(h["cards"])[0])
			var nat = is_bj(h["cards"]) and not bool(h["split"])
			var pay = 0
			var res = ""
			if pt > 21:
				res = "爆牌"
			elif dealer_bj:
				if nat:
					pay = b
					res = "平局"
				else:
					res = "输"
			elif nat:
				pay = b + b * 3 / 2
				res = "黑杰克"
			elif dbust or pt > dt:
				pay = b * 2
				res = "赢"
			elif pt == dt:
				pay = b
				res = "平局"
			else:
				res = "输"
			h["result"] = res
			h["payout"] = pay
			h["done"] = true
			chips[s] = int(chips[s]) + pay
			net += pay - b
		if net > 0:
			winners_list.append(int(s))
		parts.append("%s %+d" % [_lbl(int(s)), net])
	var dtxt = "黑杰克" if dealer_bj else ("爆牌" if dbust else "%d点" % dt)
	event = "庄家%s。结算：%s" % [dtxt, "，".join(PackedStringArray(parts))]


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
	return {"chips": cc, "rebuys": rb}


# ---------------------------------------------------------------- 状态

func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(v: int) -> Dictionary:
	var ps = []
	for s in order:
		var hs = []
		for k in hands.get(s, []).size():
			var h = hands[s][k]
			var tt = total(h["cards"])
			hs.append({"cards": h["cards"].duplicate(), "bet": int(h["bet"]), "total": int(tt[0]), "soft": bool(tt[1]), "done": bool(h["done"]), "doubled": bool(h["doubled"]), "result": str(h["result"]), "payout": int(h["payout"]), "active": phase == "play" and int(order[seat_i]) == s and k == hand_i})
		ps.append({"seat": int(s), "chips": int(chips[s]), "bet": int(bets.get(s, 0)), "has_bet": bets.has(s), "hands": hs, "rebuys": int(rebuys[s])})
	var dcards = dealer.duplicate()
	var hidden = phase == "play"
	if hidden and dcards.size() == 2:
		dcards = [dcards[0], -1]
	var me = {}
	if chips.has(v) and not over:
		if phase == "bet" and not bets.has(v):
			var opts = []
			for b in BETS:
				if b <= int(chips[v]):
					opts.append(b)
			me = {"bet_opts": opts}
		elif phase == "play" and v == current_seat():
			var h = hands[v][hand_i]
			me = {"can_hit": not bool(h["split_aces"]), "can_double": h["cards"].size() == 2 and not bool(h["split_aces"]) and int(chips[v]) >= int(h["bet"]), "can_split": can_split(v)}
	return {
		"phase": phase,
		"players": ps,
		"dealer": dcards,
		"dealer_total": int(total(dealer)[0]) if not hidden else value(int(dealer[0])) if not dealer.is_empty() else 0,
		"current_seat": current_seat(),
		"hand_i": hand_i,
		"me": me,
		"over": over,
		"winners": winners_list.duplicate(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI（简化的基本策略）

func timeout_action(s: int) -> Dictionary:
	if phase == "bet":
		return {"type": "bet", "amount": BETS[0]}
	return {"type": "stand"}


func bot_action(s: int) -> Dictionary:
	if over:
		return {}
	if phase == "bet":
		var opts = []
		for b in BETS.slice(0, 3):
			if b <= int(chips[s]):
				opts.append(b)
		return {"type": "bet", "amount": int(opts[randi() % opts.size()]) if not opts.is_empty() else BETS[0]}
	if s != current_seat():
		return {}
	var h = hands[s][hand_i]
	var tt = total(h["cards"])
	var t = int(tt[0])
	var soft = bool(tt[1])
	var up = value(int(dealer[0]))
	if can_split(s):
		var pv = value(int(h["cards"][0]))
		if pv == 11 or pv == 8 or (pv == 9 and up != 7 and up < 10) or ((pv == 2 or pv == 3 or pv == 7) and up <= 7) or (pv == 6 and up <= 6):
			return {"type": "split"}
	if bool(h["split_aces"]):
		return {"type": "stand"}
	var can_d = h["cards"].size() == 2 and int(chips[s]) >= int(h["bet"])
	if soft:
		if can_d and t >= 17 and t <= 18 and up >= 3 and up <= 6:
			return {"type": "double"}
		if t <= 17 or (t == 18 and up >= 9):
			return {"type": "hit"}
		return {"type": "stand"}
	if can_d and (t == 11 or (t == 10 and up <= 9) or (t == 9 and up >= 3 and up <= 6)):
		return {"type": "double"}
	if t <= 11:
		return {"type": "hit"}
	if t == 12:
		return {"type": "stand"} if up >= 4 and up <= 6 else {"type": "hit"}
	if t <= 16:
		return {"type": "stand"} if up <= 6 else {"type": "hit"}
	return {"type": "stand"}

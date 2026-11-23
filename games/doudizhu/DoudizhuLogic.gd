extends RefCounted
## 斗地主规则（只在房主端运行）
## 玩法开关：deal = shuffle 经典洗牌 / noshuffle 不洗牌；laizi = off / on；cap = none / 16 / 32 / 64 封顶倍数
## 叫分 1~3 分，炸弹/王炸 ×2，春天/反春 ×2

const R = preload("res://games/doudizhu/DdzRules.gd")

var rules = {}
var round_no = 1
var hands = [[], [], []]
var bottom = []
var phase = "bid"
var turn = 0
var start_seat = 0
var redeals = 0
var bids = [-1, -1, -1]
var bid_count = 0
var bid_best = 0
var bid_best_seat = -1
var landlord = -1
var laizi = 0
var last_play = {}
var passes = 0
var table = [{}, {}, {}]
var bombs = 0
var plays = [0, 0, 0]
var played_cards = 0
var winner = -1
var spring = ""
var scores = [0, 0, 0]
var final_mult = 1
var event = ""


func setup(_players: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	round_no = maxi(rn, 1)
	start_seat = (round_no - 1) % 3
	redeals = 0
	_deal()
	event = "发牌完成，%s开始叫地主" % _seat_label(start_seat)


func _seat_label(s: int) -> String:
	return "座位%d" % (s + 1)


func _clumped_deck() -> Array:
	# 模拟"上一局打完不洗牌"：同点数的牌大多挨在一起，只做少量切牌和交换
	var groups = []
	for r in range(13):
		var g = [r * 4, r * 4 + 1, r * 4 + 2, r * 4 + 3]
		g.shuffle()
		groups.append(g)
	groups.append([52, 53])
	groups.shuffle()
	var deck = []
	for g in groups:
		deck += g
	for i in 14:
		var a = randi() % deck.size()
		var b = randi() % deck.size()
		var tmp = deck[a]
		deck[a] = deck[b]
		deck[b] = tmp
	var cut = randi() % deck.size()
	return deck.slice(cut) + deck.slice(0, cut)


func _deal() -> void:
	hands = [[], [], []]
	var deck = []
	if str(rules.get("deal", "shuffle")) == "noshuffle":
		deck = _clumped_deck()
		var idx = 0
		for pk in [3, 3, 3, 3, 3, 2]:
			for k in 3:
				var s = (start_seat + k) % 3
				for j in pk:
					hands[s].append(deck[idx])
					idx += 1
		bottom = deck.slice(51, 54)
	else:
		for i in 54:
			deck.append(i)
		deck.shuffle()
		for i in 51:
			hands[i % 3].append(deck[i])
		bottom = deck.slice(51, 54)
	for s in 3:
		hands[s] = R.sort_hand(hands[s])
	phase = "bid"
	turn = start_seat
	bids = [-1, -1, -1]
	bid_count = 0
	bid_best = 0
	bid_best_seat = -1
	landlord = -1
	laizi = 0
	last_play = {}
	passes = 0
	table = [{}, {}, {}]
	bombs = 0
	plays = [0, 0, 0]
	played_cards = 0
	winner = -1
	spring = ""
	scores = [0, 0, 0]
	final_mult = 1


func is_over() -> bool:
	return winner != -1


func current_seat() -> int:
	if is_over():
		return -1
	return turn


func bot_delay() -> float:
	return 0.8 if phase == "bid" else 1.0


func _cap() -> int:
	var c = str(rules.get("cap", "none"))
	if c == "none":
		return 0
	return int(c)


func multiplier() -> int:
	var m = 1
	for i in bombs:
		m *= 2
	if spring != "":
		m *= 2
	var cap = _cap()
	if cap > 0:
		m = mini(m, cap)
	return m


func _become_landlord() -> void:
	landlord = bid_best_seat
	hands[landlord] = R.sort_hand(hands[landlord] + bottom)
	if str(rules.get("laizi", "off")) == "on":
		laizi = randi_range(3, 15)
	phase = "play"
	turn = landlord
	last_play = {}
	passes = 0
	table = [{}, {}, {}]


func apply(seat: int, a: Dictionary) -> String:
	if is_over():
		return "本局已结束"
	if seat != turn:
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if phase == "bid":
		if t != "bid":
			return "现在是叫地主阶段"
		return _apply_bid(seat, int(a.get("score", 0)))
	if t == "pass":
		return _apply_pass(seat)
	if t == "play":
		return _apply_play(seat, a.get("cards", []))
	return "无效操作"


func _apply_bid(seat: int, sc: int) -> String:
	if sc != 0 and (sc <= bid_best or sc > 3):
		return "叫分必须比当前更高（1~3分）"
	bids[seat] = sc
	bid_count += 1
	if sc > 0:
		bid_best = sc
		bid_best_seat = seat
		event = "%s 叫 %d 分" % [_seat_label(seat), sc]
	else:
		event = "%s 不叫" % _seat_label(seat)
	if sc == 3 or bid_count >= 3:
		if bid_best_seat == -1:
			redeals += 1
			if redeals >= 3:
				bid_best = 1
				bid_best_seat = start_seat
				_become_landlord()
				event = "连续三次没人叫，%s 当地主（1分）" % _seat_label(landlord)
			else:
				start_seat = (start_seat + 1) % 3
				_deal()
				event = "没人叫地主，重新发牌，%s先叫" % _seat_label(start_seat)
			return ""
		_become_landlord()
		event = "%s 当地主（%d分）" % [_seat_label(landlord), bid_best]
		if laizi > 0:
			event += "，本局癞子是 %s" % R.rank_text(laizi)
		return ""
	turn = (turn + 1) % 3
	return ""


func _lead_needed(seat: int) -> bool:
	return last_play.is_empty() or int(last_play["seat"]) == seat


func _apply_pass(seat: int) -> String:
	if _lead_needed(seat):
		return "你是首家，必须出牌"
	table[seat] = {"kind": "pass"}
	passes += 1
	event = "%s 不出" % _seat_label(seat)
	turn = (turn + 1) % 3
	if passes >= 2:
		last_play = {}
		passes = 0
	return ""


func _apply_play(seat: int, raw) -> String:
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return "请先选牌"
	var cards = []
	for c in raw:
		var ci = int(c)
		if cards.has(ci):
			return "选牌有重复"
		if not hands[seat].has(ci):
			return "你没有这张牌"
		cards.append(ci)
	var lead = _lead_needed(seat)
	var prev = {} if lead else last_play["pattern"]
	var p = R.choose_pattern(cards, laizi, prev)
	if p.is_empty():
		if R.evaluate(cards, laizi).is_empty():
			return "这不是有效的牌型"
		return "管不上上家的牌"
	if lead:
		table = [{}, {}, {}]
	for c in cards:
		hands[seat].erase(c)
	played_cards += cards.size()
	plays[seat] += 1
	if R.is_bomb(p):
		bombs += 1
	table[seat] = {"kind": "play", "cards": R.sort_hand(cards), "desc": R.describe(p)}
	last_play = {"seat": seat, "cards": cards, "pattern": p}
	passes = 0
	event = "%s 出了%s" % [_seat_label(seat), R.describe(p)]
	if hands[seat].is_empty():
		_finish(seat)
		return ""
	turn = (turn + 1) % 3
	return ""


func _finish(seat: int) -> void:
	winner = seat
	phase = "done"
	var landlord_win = seat == landlord
	var farmer_plays = 0
	for s in 3:
		if s != landlord:
			farmer_plays += plays[s]
	if landlord_win and farmer_plays == 0:
		spring = "春天"
	elif not landlord_win and plays[landlord] == 1:
		spring = "反春"
	final_mult = multiplier()
	var unit = bid_best * final_mult
	for s in 3:
		if s == landlord:
			scores[s] = 2 * unit if landlord_win else -2 * unit
		else:
			scores[s] = -unit if landlord_win else unit
	var who = "地主" if landlord_win else "农民"
	event = "%s获胜！底分%d × %d倍" % [who, bid_best, final_mult]
	if spring != "":
		event += "（%s）" % spring


func winners() -> Array:
	if winner == -1:
		return []
	if winner == landlord:
		return [landlord]
	var w = []
	for s in 3:
		if s != landlord:
			w.append(s)
	return w


func round_scores() -> Array:
	return scores.duplicate()


func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(viewer: int) -> Dictionary:
	var counts = []
	for s in 3:
		counts.append(hands[s].size())
	var my_hand = []
	if viewer >= 0 and viewer < 3:
		my_hand = hands[viewer].duplicate()
	var reveal = []
	if is_over():
		for s in 3:
			reveal.append(hands[s].duplicate())
	var lead = true
	var last_pattern = {}
	if not last_play.is_empty():
		last_pattern = last_play["pattern"].duplicate()
		lead = int(last_play["seat"]) == turn
	return {
		"phase": phase,
		"current_seat": current_seat(),
		"landlord": landlord,
		"bid_best": bid_best,
		"bids": bids.duplicate(),
		"laizi": laizi,
		"bottom": bottom.duplicate() if landlord >= 0 else [],
		"counts": counts,
		"my_hand": my_hand,
		"reveal": reveal,
		"table": table.duplicate(true),
		"lead": lead,
		"last_pattern": last_pattern,
		"last_seat": int(last_play.get("seat", -1)),
		"bombs": bombs,
		"mult": final_mult if is_over() else multiplier(),
		"spring": spring,
		"scores": scores.duplicate(),
		"over": is_over(),
		"winners": winners(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func _bid_strength(h: Array) -> int:
	var g = R.groups_of(h)
	var s = 0
	if g.has(17):
		s += 4
	if g.has(16):
		s += 3
	if g.has(15):
		s += g[15].size() * 2
	if g.has(14):
		s += g[14].size()
	for r in g:
		if g[r].size() == 4:
			s += 4
	return s


func bot_action(seat: int) -> Dictionary:
	if is_over():
		return {}
	if phase == "bid":
		var st = _bid_strength(hands[seat])
		var want = 0
		if st >= 11:
			want = 3
		elif st >= 8:
			want = 2
		elif st >= 5:
			want = 1
		if want <= bid_best:
			want = 0
		return {"type": "bid", "score": want}
	var h = hands[seat]
	if _lead_needed(seat):
		var nxt = (seat + 1) % 3
		var danger = hands[nxt].size() == 1 and (seat == landlord or nxt == landlord)
		return {"type": "play", "cards": R.bot_lead(h, laizi, danger)}
	var prev = last_play["pattern"]
	var cands = R.follow_candidates(h, laizi, prev)
	if cands.is_empty():
		return {"type": "pass"}
	for c in cands:
		if c.size() == h.size():
			return {"type": "play", "cards": c}
	var ps = int(last_play["seat"])
	var teammate = seat != landlord and ps != landlord
	if teammate:
		return {"type": "pass"}
	var normal = []
	var bomb_list = []
	for c in cands:
		if R.is_bomb(R.choose_pattern(c, laizi, prev)):
			bomb_list.append(c)
		else:
			normal.append(c)
	if not normal.is_empty():
		return {"type": "play", "cards": normal[0]}
	var opp_min = 99
	for s in 3:
		if s == seat:
			continue
		if seat == landlord or s == landlord:
			opp_min = mini(opp_min, hands[s].size())
	if opp_min <= 6 or h.size() <= 6 or randf() < 0.3:
		return {"type": "play", "cards": bomb_list[0]}
	return {"type": "pass"}

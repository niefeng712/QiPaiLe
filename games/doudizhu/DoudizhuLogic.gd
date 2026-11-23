extends RefCounted
## 斗地主规则（只在房主端运行），三人 / 四人通用
## 玩法开关：
##   players  3 / 4（四人：两副牌，每人25张，底牌8张，一个地主打三个农民）
##   deal     shuffle 经典洗牌 / noshuffle 不洗牌
##   laizi    off / on（仅三人）
##   bidmode  score 叫分(1~3分) / rob 叫地主+抢地主(每抢一次×2)
##   mingpai  on：看牌前可"明牌开始"×5；地主拿底牌后可明牌×2
##   double   on：定完地主后农民可加倍×2，地主可加倍×2/超级加倍×4
##   counter  on：记牌器
##   cap      none / 16 / 32 / 64 封顶倍数
## 每个农民和地主单独结算：底分 × 公共倍数(炸弹/春天/抢地主/明牌) × 该农民加倍 × 地主加倍

const R = preload("res://games/doudizhu/DdzRules.gd")

var rules = {}
var n = 3
var decks = 1
var round_no = 1
var hands = []
var bottom = []
var phase = "bid"
var turn = 0
var start_seat = 0
var redeals = 0
var says = []
var bid_mode = "score"
var bid_count = 0
var bid_best = 0
var bid_best_seat = -1
var rob_caller = -1
var rob_holder = -1
var robs = 0
var declined = []
var rob_queue = []
var rob_final_done = false
var use_ming = false
var shown = []
var ming_done = []
var ming_count = 0
var ming_mult = 1
var use_double = false
var doubles = []
var double_queue = []
var counter_on = true
var landlord = -1
var laizi = 0
var last_play = {}
var passes = 0
var table = []
var bombs = 0
var plays = []
var played_cards = 0
var played_rank = []
var winner = -1
var spring = ""
var scores = []
var final_mult = 1
var event = ""


func setup(_players: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	n = 4 if str(rules.get("players", "3")) == "4" else 3
	decks = 2 if n == 4 else 1
	R.set_two_decks(decks == 2)
	bid_mode = "rob" if str(rules.get("bidmode", "score")) == "rob" else "score"
	use_ming = str(rules.get("mingpai", "off")) == "on"
	use_double = str(rules.get("double", "off")) == "on"
	counter_on = str(rules.get("counter", "on")) == "on"
	round_no = maxi(rn, 1)
	start_seat = (round_no - 1) % n
	redeals = 0
	_deal()
	if phase == "ming":
		event = "发牌完成，请选择是否明牌开始"
	else:
		event = "发牌完成，%s开始叫地主" % _lbl(start_seat)


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func _filled(v) -> Array:
	var a = []
	for i in n:
		a.append(v)
	return a


func _clumped_deck() -> Array:
	# 模拟"上一局打完不洗牌"：同点数的牌大多挨在一起，只做少量切牌和交换
	var groups = []
	for r in range(13):
		var g = []
		for d in decks:
			for k in 4:
				g.append(d * 54 + r * 4 + k)
		g.shuffle()
		groups.append(g)
	var jg = []
	for d in decks:
		jg.append(d * 54 + 52)
		jg.append(d * 54 + 53)
	groups.append(jg)
	groups.shuffle()
	var deck = []
	for g in groups:
		deck += g
	for i in 14 * decks:
		var a = randi() % deck.size()
		var b = randi() % deck.size()
		var tmp = deck[a]
		deck[a] = deck[b]
		deck[b] = tmp
	var cut = randi() % deck.size()
	return deck.slice(cut) + deck.slice(0, cut)


func _deal() -> void:
	hands = []
	for s in n:
		hands.append([])
	var total = 54 * decks
	var per = 17 if n == 3 else 25
	var deck = []
	if str(rules.get("deal", "shuffle")) == "noshuffle":
		deck = _clumped_deck()
		var idx = 0
		var packs = [3, 3, 3, 3, 3, 2] if n == 3 else [5, 5, 5, 5, 5]
		for pk in packs:
			for k in n:
				var s = (start_seat + k) % n
				for j in pk:
					hands[s].append(deck[idx])
					idx += 1
	else:
		for i in total:
			deck.append(i)
		deck.shuffle()
		for i in per * n:
			hands[i % n].append(deck[i])
	bottom = deck.slice(per * n, total)
	for s in n:
		hands[s] = R.sort_hand(hands[s])
	says = _filled("")
	bid_count = 0
	bid_best = 0
	bid_best_seat = -1
	rob_caller = -1
	rob_holder = -1
	robs = 0
	declined = []
	rob_queue = []
	rob_final_done = false
	shown = _filled(false)
	ming_done = _filled(not use_ming)
	ming_count = 0
	ming_mult = 1
	doubles = _filled(1)
	double_queue = []
	landlord = -1
	laizi = 0
	last_play = {}
	passes = 0
	_clear_table()
	bombs = 0
	plays = _filled(0)
	played_cards = 0
	played_rank = []
	for i in 18:
		played_rank.append(0)
	winner = -1
	spring = ""
	scores = _filled(0)
	final_mult = 1
	phase = "ming" if use_ming else "bid"
	turn = start_seat


func _clear_table() -> void:
	table = []
	for i in n:
		table.append({})


func is_over() -> bool:
	return winner != -1


func current_seat() -> int:
	if is_over():
		return -1
	return turn


func bot_delay() -> float:
	return 1.0 if phase == "play" else 0.8


func _cap() -> int:
	var c = str(rules.get("cap", "none"))
	if c == "none" or not c.is_valid_int():
		return 0
	return int(c)


func _global_mult() -> int:
	var m = 1
	for i in bombs:
		m *= 2
	if spring != "":
		m *= 2
	for i in robs:
		m *= 2
	m *= ming_mult
	return m


func _farmer_mult(f: int) -> int:
	var dl = int(doubles[landlord]) if landlord >= 0 else 1
	var m = _global_mult() * int(doubles[f]) * dl
	var cap = _cap()
	if cap > 0:
		m = mini(m, cap)
	return m


func multiplier() -> int:
	return _global_mult()


func _my_mult(v: int) -> int:
	if landlord < 0 or v < 0 or v >= n:
		return _global_mult()
	if v == landlord:
		var t = 0
		for s in n:
			if s != landlord:
				t += _farmer_mult(s)
		return t
	return _farmer_mult(v)


# ---------------------------------------------------------------- 流程

func _finish_bidding(msg: String) -> void:
	event = msg
	landlord = bid_best_seat
	hands[landlord] = R.sort_hand(hands[landlord] + bottom)
	if str(rules.get("laizi", "off")) == "on" and decks == 1:
		laizi = randi_range(3, 15)
		event += "，本局癞子是 %s" % R.rank_text(laizi)
	for s in n:
		says[s] = ""
	if use_ming and not bool(shown[landlord]):
		phase = "lming"
		turn = landlord
		event += "，地主可以选择明牌"
	else:
		_after_lming()


func _after_lming() -> void:
	if use_double:
		phase = "double"
		double_queue = []
		for k in range(1, n):
			double_queue.append((landlord + k) % n)
		double_queue.append(landlord)
		turn = int(double_queue.pop_front())
		event += "，请选择是否加倍"
	else:
		_start_play()
		event += "，地主先出牌"


func _start_play() -> void:
	phase = "play"
	turn = landlord
	last_play = {}
	passes = 0
	_clear_table()
	for s in n:
		says[s] = ""


func _no_landlord() -> void:
	redeals += 1
	if redeals >= 3:
		bid_best = 1
		bid_best_seat = start_seat
		robs = 0
		_finish_bidding("连续三次没人叫，%s 当地主（1分）" % _lbl(start_seat))
		return
	start_seat = (start_seat + 1) % n
	_deal()
	if phase == "ming":
		event = "没人叫地主，重新发牌，请选择是否明牌开始"
	else:
		event = "没人叫地主，重新发牌，%s先叫" % _lbl(start_seat)


func apply(seat: int, a: Dictionary) -> String:
	R.set_two_decks(decks == 2)
	if is_over():
		return "本局已结束"
	if seat != turn:
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if phase == "ming" or phase == "lming":
		if t != "ming":
			return "请先选择是否明牌"
		return _apply_ming(seat, bool(a.get("yes", false)))
	if phase == "bid":
		if bid_mode == "rob":
			if t != "rob":
				return "现在是叫地主/抢地主阶段"
			return _apply_rob(seat, bool(a.get("yes", false)))
		if t != "bid":
			return "现在是叫地主阶段"
		return _apply_bid(seat, int(a.get("score", 0)))
	if phase == "double":
		if t != "double":
			return "请先选择是否加倍"
		return _apply_double(seat, int(a.get("x", 1)))
	if phase == "play":
		if t == "pass":
			return _apply_pass(seat)
		if t == "play":
			return _apply_play(seat, a.get("cards", []))
	return "无效操作"


func _apply_ming(seat: int, yes: bool) -> String:
	if phase == "lming":
		if yes:
			shown[seat] = true
			ming_mult = maxi(ming_mult, 2)
			event = "%s（地主）明牌了" % _lbl(seat)
		else:
			event = "%s（地主）不明牌" % _lbl(seat)
		_after_lming()
		return ""
	ming_done[seat] = true
	if yes:
		shown[seat] = true
		ming_mult = maxi(ming_mult, 5)
		says[seat] = "明牌"
		event = "%s 明牌开始，倍数×5" % _lbl(seat)
	else:
		event = "%s 不明牌" % _lbl(seat)
	ming_count += 1
	if ming_count >= n:
		phase = "bid"
		turn = start_seat
		for s in n:
			says[s] = ""
		event += "，%s开始叫地主" % _lbl(start_seat)
	else:
		turn = (turn + 1) % n
	return ""


func _apply_bid(seat: int, sc: int) -> String:
	if sc != 0 and (sc <= bid_best or sc > 3):
		return "叫分必须比当前更高（1~3分）"
	bid_count += 1
	if sc > 0:
		bid_best = sc
		bid_best_seat = seat
		says[seat] = "%d分" % sc
		event = "%s 叫 %d 分" % [_lbl(seat), sc]
	else:
		says[seat] = "不叫"
		event = "%s 不叫" % _lbl(seat)
	if sc == 3 or bid_count >= n:
		if bid_best_seat == -1:
			_no_landlord()
			return ""
		_finish_bidding("%s 当地主（%d分）" % [_lbl(bid_best_seat), bid_best])
		return ""
	turn = (turn + 1) % n
	return ""


func _apply_rob(seat: int, yes: bool) -> String:
	if rob_caller == -1:
		if yes:
			rob_caller = seat
			rob_holder = seat
			says[seat] = "叫地主"
			event = "%s 叫地主" % _lbl(seat)
			rob_queue = []
			for k in range(1, n):
				var s2 = (seat + k) % n
				if not declined.has(s2):
					rob_queue.append(s2)
		else:
			declined.append(seat)
			says[seat] = "不叫"
			event = "%s 不叫" % _lbl(seat)
			if declined.size() >= n:
				_no_landlord()
				return ""
			turn = (seat + 1) % n
			return ""
	else:
		if yes:
			rob_holder = seat
			robs += 1
			says[seat] = "抢地主"
			event = "%s 抢地主，倍数×2" % _lbl(seat)
		else:
			says[seat] = "不抢"
			event = "%s 不抢" % _lbl(seat)
	if not rob_queue.is_empty():
		turn = int(rob_queue.pop_front())
		return ""
	if robs > 0 and not rob_final_done and rob_holder != rob_caller:
		rob_final_done = true
		turn = rob_caller
		return ""
	bid_best = 1
	bid_best_seat = rob_holder
	var extra = ""
	if robs > 0:
		extra = "（抢了%d次，×%d）" % [robs, 1 << robs]
	_finish_bidding("%s 当地主%s" % [_lbl(rob_holder), extra])
	return ""


func _apply_double(seat: int, x: int) -> String:
	if x != 1 and x != 2 and not (x == 4 and seat == landlord):
		return "无效的加倍选择"
	doubles[seat] = x
	var txt = {1: "不加倍", 2: "加倍", 4: "超级加倍"}[x]
	says[seat] = txt
	event = "%s %s" % [_lbl(seat), txt]
	if double_queue.is_empty():
		_start_play()
		event += "，地主先出牌"
	else:
		turn = int(double_queue.pop_front())
	return ""


func _lead_needed(seat: int) -> bool:
	return last_play.is_empty() or int(last_play["seat"]) == seat


func _apply_pass(seat: int) -> String:
	if _lead_needed(seat):
		return "你是首家，必须出牌"
	table[seat] = {"kind": "pass"}
	passes += 1
	event = "%s 不出" % _lbl(seat)
	turn = (turn + 1) % n
	if passes >= n - 1:
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
		_clear_table()
	for c in cards:
		hands[seat].erase(c)
		played_rank[R.card_rank(c)] += 1
	played_cards += cards.size()
	plays[seat] += 1
	if R.is_bomb(p):
		bombs += 1
	table[seat] = {"kind": "play", "cards": R.sort_hand(cards), "desc": R.describe(p)}
	last_play = {"seat": seat, "cards": cards, "pattern": p}
	passes = 0
	event = "%s 出了%s" % [_lbl(seat), R.describe(p)]
	if hands[seat].is_empty():
		_finish(seat)
		return ""
	turn = (turn + 1) % n
	return ""


func _finish(seat: int) -> void:
	winner = seat
	phase = "done"
	var landlord_win = seat == landlord
	var farmer_plays = 0
	for s in n:
		if s != landlord:
			farmer_plays += plays[s]
	if landlord_win and farmer_plays == 0:
		spring = "春天"
	elif not landlord_win and plays[landlord] == 1:
		spring = "反春"
	final_mult = _global_mult()
	var total = 0
	for s in n:
		if s == landlord:
			continue
		var u = bid_best * _farmer_mult(s)
		scores[s] = -u if landlord_win else u
		total += scores[s]
	scores[landlord] = -total
	var who = "地主" if landlord_win else "农民"
	event = "%s获胜！底分%d，公共倍数×%d" % [who, bid_best, final_mult]
	if spring != "":
		event += "（%s）" % spring


func winners() -> Array:
	if winner == -1:
		return []
	if winner == landlord:
		return [landlord]
	var w = []
	for s in n:
		if s != landlord:
			w.append(s)
	return w


func round_scores() -> Array:
	return scores.duplicate()


func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(viewer: int) -> Dictionary:
	var counts = []
	var open = []
	for s in n:
		counts.append(hands[s].size())
		if bool(shown[s]) and not is_over():
			open.append(hands[s].duplicate())
		else:
			open.append([])
	var my_hand = []
	var hidden = false
	if viewer >= 0 and viewer < n:
		if phase == "ming" and not bool(ming_done[viewer]):
			hidden = true
		else:
			my_hand = hands[viewer].duplicate()
	var reveal = []
	if is_over():
		for s in n:
			reveal.append(hands[s].duplicate())
	var lead = true
	var last_pattern = {}
	if not last_play.is_empty():
		last_pattern = last_play["pattern"].duplicate()
		lead = int(last_play["seat"]) == turn
	return {
		"n": n,
		"decks": decks,
		"phase": phase,
		"current_seat": current_seat(),
		"landlord": landlord,
		"bid_mode": bid_mode,
		"bid_best": bid_best,
		"rob_caller": rob_caller,
		"robs": robs,
		"says": says.duplicate(),
		"doubles": doubles.duplicate(),
		"shown": shown.duplicate(),
		"open": open,
		"laizi": laizi,
		"bottom": bottom.duplicate() if landlord >= 0 else [],
		"bottom_count": bottom.size(),
		"counts": counts,
		"my_hand": my_hand,
		"hand_hidden": hidden,
		"reveal": reveal,
		"table": table.duplicate(true),
		"lead": lead,
		"last_pattern": last_pattern,
		"last_seat": int(last_play.get("seat", -1)),
		"bombs": bombs,
		"mult": final_mult if is_over() else _global_mult(),
		"my_mult": _my_mult(viewer),
		"counter_on": counter_on,
		"played": played_rank.duplicate(),
		"spring": spring,
		"scores": scores.duplicate(),
		"over": is_over(),
		"winners": winners(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI / 超时处理

func _strength(h: Array) -> float:
	var g = R.groups_of(h)
	var s = 0.0
	for r in g:
		var c = g[r].size()
		if r == 17:
			s += 4 * c
		elif r == 16:
			s += 3 * c
		elif r == 15:
			s += 2 * c
		elif r == 14:
			s += c
		if r < 16 and c >= 4:
			s += 4 + (c - 4) * 2
	if decks == 2:
		s /= 1.6
	return s


func timeout_action(seat: int) -> Dictionary:
	R.set_two_decks(decks == 2)
	if phase == "ming" or phase == "lming":
		return {"type": "ming", "yes": false}
	if phase == "bid":
		if bid_mode == "rob":
			return {"type": "rob", "yes": false}
		return {"type": "bid", "score": 0}
	if phase == "double":
		return {"type": "double", "x": 1}
	if phase == "play":
		if _lead_needed(seat):
			return {"type": "play", "cards": R.bot_lead(hands[seat], laizi, false)}
		return {"type": "pass"}
	return {}


func bot_action(seat: int) -> Dictionary:
	R.set_two_decks(decks == 2)
	if is_over():
		return {}
	var h = hands[seat]
	var st = _strength(h)
	if phase == "ming":
		return {"type": "ming", "yes": st >= 15.0}
	if phase == "lming":
		return {"type": "ming", "yes": st >= 17.0}
	if phase == "bid":
		if bid_mode == "rob":
			var need = 5.0 if rob_caller == -1 else 8.0
			return {"type": "rob", "yes": st >= need}
		var want = 0
		if st >= 11.0:
			want = 3
		elif st >= 8.0:
			want = 2
		elif st >= 5.0:
			want = 1
		if want <= bid_best:
			want = 0
		return {"type": "bid", "score": want}
	if phase == "double":
		var x = 1
		if seat == landlord:
			if st >= 16.0:
				x = 4
			elif st >= 11.0:
				x = 2
		elif st >= 8.0:
			x = 2
		return {"type": "double", "x": x}
	if _lead_needed(seat):
		var nxt = (seat + 1) % n
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
	for s in n:
		if s == seat:
			continue
		if seat == landlord or s == landlord:
			opp_min = mini(opp_min, hands[s].size())
	if opp_min <= 6 or h.size() <= 6 or randf() < 0.3:
		return {"type": "play", "cards": bomb_list[0]}
	return {"type": "pass"}

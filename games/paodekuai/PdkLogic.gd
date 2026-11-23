extends RefCounted
## 跑得快（只在房主端运行），3人
## 玩法开关：
##   deck   16 每人16张（去掉大小王、三张2留♠2、♠A）/ 15 每人15张（再去掉三张A留♠A、♠K）
##   must   on 有大必压（能管上就不能不出）/ off 可以不出
##   spade3 on 第一局拿♠3的人先出，而且第一手要带♠3
## 规则：下家只剩1张牌（报单）时，出单张必须出最大的那张
## 计分：先出完的人赢，其他人每剩一张牌输1分；剩1张不输分；一张都没出过（被关）输双倍；
##       每打出一个炸弹，其他两家各给他10分

const R = preload("res://games/paodekuai/PdkRules.gd")

var rules = {}
var n = 3
var hands = []
var start_n = 16
var turn = 0
var last_play = {}
var passes = 0
var table = []
var plays = []
var bombs = []
var scores = []
var winner = -1
var first_card = -1
var must = true
var event = ""
var played_count = 0
var _first_lead = false
var _prev_winner = -1


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func setup(_players: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	must = str(rules.get("must", "on")) == "on"
	var deck = []
	var small = str(rules.get("deck", "16")) == "15"
	for c in 52:
		var r = R.rank(c)
		var s = R.suit(c)
		if r == 15 and s != 0:
			continue
		if not small and r == 14 and s == 0:
			continue
		if small and r == 14 and s != 0:
			continue
		if small and r == 13 and s == 0:
			continue
		deck.append(c)
	deck.shuffle()
	start_n = deck.size() / 3
	hands = [[], [], []]
	for i in deck.size():
		hands[i % 3].append(deck[i])
	for s in 3:
		hands[s] = R.sort_hand(hands[s])
	plays = [0, 0, 0]
	bombs = [0, 0, 0]
	scores = [0, 0, 0]
	table = [{}, {}, {}]
	last_play = {}
	passes = 0
	winner = -1
	played_count = 0
	var carry = rules.get("_carry", {})
	_prev_winner = int(carry.get("winner", -1)) if typeof(carry) == TYPE_DICTIONARY else -1
	first_card = -1
	_first_lead = false
	if str(rules.get("spade3", "on")) == "on" and (_prev_winner < 0 or rn <= 1):
		var s3 = R.card_id(3, 0)
		for s in 3:
			if hands[s].has(s3):
				turn = s
				first_card = s3
				_first_lead = true
		event = "%s 有♠3，先出（第一手要带♠3）" % _lbl(turn)
	else:
		turn = _prev_winner if _prev_winner >= 0 else (rn - 1) % 3
		event = "%s 先出" % _lbl(turn)


func is_over() -> bool:
	return winner >= 0


func current_seat() -> int:
	return -1 if is_over() else turn


func bot_delay() -> float:
	return 0.9


func _lead(s: int) -> bool:
	return last_play.is_empty() or int(last_play["seat"]) == s


func _next(s: int) -> int:
	return (s + 1) % n


func _single_rule(s: int, cards: Array) -> String:
	if cards.size() == 1 and hands[_next(s)].size() == 1:
		var mx = R.max_card(hands[s])
		if R.rank(int(cards[0])) != R.rank(mx):
			return "下家报单了，出单张必须出你最大的牌（%s）" % R.rank_text(R.rank(mx))
	return ""


func apply(seat: int, a: Dictionary) -> String:
	if is_over():
		return "本局已结束"
	if seat != turn:
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if t == "pass":
		if _lead(seat):
			return "你是首家，必须出牌"
		if must and not R.candidates(hands[seat], last_play["pattern"]).is_empty():
			return "有大必压：你有能管上的牌，不能不出"
		table[seat] = {"kind": "pass"}
		passes += 1
		event = "%s 要不起" % _lbl(seat)
		turn = _next(seat)
		if passes >= n - 1:
			last_play = {}
			passes = 0
		return ""
	if t != "play":
		return "无效操作"
	var raw = a.get("cards", [])
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return "请先选牌"
	var cards = []
	for c in raw:
		var ci = int(c)
		if cards.has(ci) or not hands[seat].has(ci):
			return "选的牌不对"
		cards.append(ci)
	if _first_lead and first_card >= 0 and not cards.has(first_card):
		return "第一手要带♠3"
	var p = R.classify(cards, cards.size() == hands[seat].size())
	if p.is_empty():
		return "这不是有效的牌型"
	var lead = _lead(seat)
	if not lead and not R.can_beat(p, last_play["pattern"]):
		return "管不上上家的牌"
	var sr = _single_rule(seat, cards)
	if sr != "":
		return sr
	if lead:
		table = [{}, {}, {}]
	_first_lead = false
	for c in cards:
		hands[seat].erase(c)
	played_count += cards.size()
	plays[seat] += 1
	table[seat] = {"kind": "play", "cards": R.sort_hand(cards), "desc": R.describe(p)}
	last_play = {"seat": seat, "pattern": p}
	passes = 0
	event = "%s 出了%s" % [_lbl(seat), R.describe(p)]
	if str(p["type"]) == "bomb":
		bombs[seat] += 1
		for o in n:
			if o != seat:
				scores[o] -= 10
				scores[seat] += 10
		event += "，其他人各给他10分"
	if hands[seat].size() == 1:
		event += "，报单！"
	if hands[seat].is_empty():
		_finish(seat)
		return ""
	turn = _next(seat)
	return ""


func _finish(w: int) -> void:
	winner = w
	var parts = []
	for s in n:
		if s == w:
			continue
		var left = hands[s].size()
		var pay = 0 if left == 1 else left
		var tag = ""
		if plays[s] == 0:
			pay = left * 2
			tag = "（被关，双倍）"
		scores[s] -= pay
		scores[w] += pay
		parts.append("%s剩%d张输%d分%s" % [_lbl(s), left, pay, tag])
	event = "%s 出完了！%s" % [_lbl(w), "，".join(PackedStringArray(parts))]


func winners() -> Array:
	return [winner] if winner >= 0 else []


func round_scores() -> Array:
	return scores.duplicate()


func carry_out() -> Dictionary:
	return {"winner": winner}


func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(v: int) -> Dictionary:
	var counts = []
	for s in n:
		counts.append(hands[s].size())
	var reveal = []
	if is_over():
		for s in n:
			reveal.append(R.sort_hand(hands[s]))
	return {
		"n": n,
		"current_seat": current_seat(),
		"my_hand": R.sort_hand(hands[v]) if v >= 0 and v < n else [],
		"counts": counts,
		"table": table.duplicate(true),
		"lead": _lead(turn),
		"last_pattern": last_play.get("pattern", {}).duplicate() if not last_play.is_empty() else {},
		"must": must,
		"first_card": first_card if _first_lead else -1,
		"scores": scores.duplicate(),
		"reveal": reveal,
		"over": is_over(),
		"winners": winners(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func bot_action(s: int) -> Dictionary:
	if is_over():
		return {}
	var h = hands[s]
	var danger = hands[_next(s)].size() == 1
	if _lead(s):
		var opts = R.candidates(h, {})
		var good = []
		for it in opts:
			var cards = it[0]
			if _first_lead and first_card >= 0 and not cards.has(first_card):
				continue
			if _single_rule(s, cards) != "":
				continue
			good.append(it)
		for it in good:
			if it[0].size() == h.size():
				return {"type": "play", "cards": it[0]}
		var low = 99
		for c in h:
			low = mini(low, R.rank(int(c)))
		if _first_lead:
			low = 3
		var best = []
		for it in good:
			var cards2 = it[0]
			if str(it[1]["type"]) == "bomb":
				continue
			if R.min_rank(cards2) != low:
				continue
			if cards2.size() > best.size():
				best = cards2
		if danger:
			for it in good:
				if it[0].size() >= 2 and str(it[1]["type"]) != "bomb":
					best = it[0] if best.size() < 2 else best
		if best.is_empty():
			if not good.is_empty():
				best = good[0][0]
			elif _first_lead and first_card >= 0:
				best = [first_card]
			else:
				best = [R.max_card(h)]
		return {"type": "play", "cards": best}
	var prev = last_play["pattern"]
	var cands = []
	for it in R.candidates(h, prev):
		if _single_rule(s, it[0]) == "":
			cands.append(it)
	if cands.is_empty():
		return {"type": "pass"}
	for it in cands:
		if it[0].size() == h.size():
			return {"type": "play", "cards": it[0]}
	cands.sort_custom(func(a, b): return (1 if str(a[1]["type"]) == "bomb" else 0) * 100 + int(a[1]["rank"]) < (1 if str(b[1]["type"]) == "bomb" else 0) * 100 + int(b[1]["rank"]))
	var pick = cands[0]
	if str(pick[1]["type"]) == "bomb" and not must and not danger and h.size() > 6 and randf() < 0.5:
		return {"type": "pass"}
	return {"type": "play", "cards": pick[0]}

extends RefCounted
## 升级拖拉机（只在房主端运行）：4人两副牌，座位1、3 一伙，座位2、4 一伙
## 流程：发牌（每人25张，底牌8张）→ 亮主 → 庄家拿底牌并扣底 → 出牌25轮 → 抠底 → 算分升级
## 闲家得分：<80 庄家方升级（0分升3级，5~35分升2级，40~75分升1级）；≥80 闲家上台，每多40分再升1级
## 级数在一场比赛里一直累计（通过 carry 传给下一局），先打过A的一方赢得整场

const T = preload("res://games/tuolaji/TljRules.gd")

var rules = {}
var round_no = 1
var levels = [2, 2]
var dealer = -1
var next_dealer = -1
var match_rounds = 0
var level = 2
var trump = -1
var ctx = {}
var hands = []
var bottom = []
var phase = "declare"
var turn = 0
var decl = {}
var decl_passes = 0
var trick = []
var best_seat = -1
var best_val = [-1, -1]
var last_trick = []
var last_winner = -1
var points = 0
var all_points = 0
var played_count = 0
var tricks_done = 0
var winner_team = -1
var result = {}
var match_over = false
var match_winner = -1
var event = ""
var throw_on = true
var bottom_rule = "size"


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func setup(_players: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	round_no = maxi(rn, 1)
	throw_on = str(rules.get("throw", "on")) == "on"
	bottom_rule = str(rules.get("bottom", "size"))
	var carry = rules.get("_carry", {})
	if typeof(carry) == TYPE_DICTIONARY and not carry.is_empty() and not bool(carry.get("over", false)):
		levels = [int(carry["levels"][0]), int(carry["levels"][1])]
		dealer = int(carry.get("dealer", -1))
		match_rounds = int(carry.get("rounds", 0))
	else:
		levels = [2, 2]
		dealer = -1
		match_rounds = 0
	level = levels[dealer % 2] if dealer >= 0 else levels[0]
	var deck = []
	for i in 108:
		deck.append(i)
	deck.shuffle()
	hands = [[], [], [], []]
	for i in 100:
		hands[i % 4].append(deck[i])
	bottom = deck.slice(100, 108)
	trump = -2
	ctx = T.make_ctx(level, -2)
	phase = "declare"
	decl = {}
	decl_passes = 0
	turn = dealer if dealer >= 0 else (round_no - 1) % 4
	trick = []
	best_seat = -1
	best_val = [-1, -1]
	last_trick = []
	last_winner = -1
	points = 0
	all_points = 0
	played_count = 0
	tricks_done = 0
	winner_team = -1
	result = {}
	match_over = false
	match_winner = -1
	next_dealer = -1
	if dealer >= 0:
		event = "第%d局，%s坐庄，打%s。可以亮%s定主" % [match_rounds + 1, _lbl(dealer), T.rank_text(level), T.rank_text(level)]
	else:
		event = "新的一场，从%s打起。亮%s定主，第一局亮主的人坐庄" % [T.rank_text(level), T.rank_text(level)]
	_advance_declare()


func is_over() -> bool:
	return phase == "done"


func current_seat() -> int:
	if is_over():
		return -1
	return turn


func bot_delay() -> float:
	return 0.7 if phase == "declare" else 0.9


func attackers_team() -> int:
	if dealer < 0:
		return -1
	return 1 - dealer % 2


# ---------------------------------------------------------------- 亮主

func declare_options(seat: int) -> Array:
	var out = []
	if phase != "declare" or seat != turn or seat < 0:
		return out
	if not decl.is_empty() and int(decl["seat"]) == seat:
		return out
	var cur = int(decl.get("str", 0))
	var cnt = {}
	for c in hands[seat]:
		var f = int(c) % 54
		cnt[f] = int(cnt.get(f, 0)) + 1
	var lt = T.rank_text(level)
	for s in 4:
		var k = int(cnt.get((level - 2) * 4 + s, 0))
		if k >= 1 and cur < 1:
			out.append({"suit": s, "str": 1, "label": "亮%s%s" % [T.SUITS[s], lt]})
		if k >= 2 and cur < 2:
			out.append({"suit": s, "str": 2, "label": "亮一对%s%s" % [T.SUITS[s], lt]})
	if int(cnt.get(52, 0)) >= 2 and cur < 3:
		out.append({"suit": -1, "str": 3, "label": "一对小王·无主"})
	if int(cnt.get(53, 0)) >= 2 and cur < 4:
		out.append({"suit": -1, "str": 4, "label": "一对大王·无主"})
	return out


func _decl_done() -> bool:
	if decl.is_empty():
		return decl_passes >= 4
	return decl_passes >= 3


func _advance_declare() -> void:
	# 轮到的人没有能亮的牌就自动跳过
	for guard in 8:
		if _decl_done():
			_finish_declare()
			return
		if not declare_options(turn).is_empty():
			return
		decl_passes += 1
		turn = (turn + 1) % 4


func _apply_declare(seat: int, a: Dictionary) -> String:
	if bool(a.get("pass", false)):
		decl_passes += 1
		event = "%s 不亮" % _lbl(seat)
	else:
		var s = int(a.get("suit", -9))
		var k = int(a.get("str", 0))
		var label = ""
		for o in declare_options(seat):
			if int(o["suit"]) == s and int(o["str"]) == k:
				label = str(o["label"])
		if label == "":
			return "不能这样亮主"
		decl = {"seat": seat, "suit": s, "str": k}
		decl_passes = 0
		event = "%s %s" % [_lbl(seat), label]
	turn = (turn + 1) % 4
	_advance_declare()
	return ""


func _finish_declare() -> void:
	var msg = ""
	if decl.is_empty():
		var s = 0
		for c in bottom:
			if int(c) % 54 < 52 and T.rank(int(c)) != level:
				s = T.suit(int(c))
				break
		trump = s
		if dealer < 0:
			dealer = (round_no - 1) % 4
		msg = "没有人亮主，翻底牌定主：%s" % T.trump_text(trump)
	else:
		trump = int(decl["suit"])
		if dealer < 0:
			dealer = int(decl["seat"])
		msg = "%s亮主成功，主牌：%s" % [_lbl(int(decl["seat"])), T.trump_text(trump)]
	level = levels[dealer % 2]
	ctx = T.make_ctx(level, trump)
	hands[dealer] = hands[dealer] + bottom
	bottom = []
	phase = "bury"
	turn = dealer
	event = "%s，%s坐庄，请庄家扣底" % [msg, _lbl(dealer)]


func _apply_bury(seat: int, raw) -> String:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 8:
		return "请选择8张牌扣底"
	var cards = []
	for c in raw:
		var ci = int(c)
		if cards.has(ci) or not hands[seat].has(ci):
			return "选的牌不对"
		cards.append(ci)
	for c in cards:
		hands[seat].erase(c)
	bottom = cards
	phase = "play"
	turn = dealer
	trick = []
	event = "庄家扣底完成，%s先出牌" % _lbl(dealer)
	return ""


# ---------------------------------------------------------------- 出牌

func apply(seat: int, a: Dictionary) -> String:
	if is_over():
		return "本局已结束"
	if seat != turn:
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if phase == "declare":
		if t != "declare":
			return "现在是亮主阶段"
		return _apply_declare(seat, a)
	if phase == "bury":
		if t != "bury":
			return "请先扣底（选8张牌）"
		return _apply_bury(seat, a.get("cards", []))
	if phase == "play" and t == "play":
		return _apply_play(seat, a.get("cards", []))
	return "无效操作"


func _put(seat: int, cards: Array) -> void:
	for c in cards:
		hands[seat].erase(c)
	played_count += cards.size()
	trick.append([seat, T.sort_display(cards, ctx)])


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
	if trick.is_empty():
		if not T.same_suit(cards, ctx):
			return "首家出的牌必须是同一花色（或都是主牌）"
		var d = T.decompose(cards, ctx)
		var forced = []
		if T.n_components(d) > 1:
			if not throw_on:
				return "本房间不允许甩牌，请出单张、对子或拖拉机"
			var others = []
			for s in 4:
				if s != seat:
					others.append(hands[s])
			forced = T.throw_fail(cards, others, ctx)
		var desc = T.describe(cards, ctx)
		if not forced.is_empty():
			cards = forced
			desc = "甩牌失败，只能出%s" % T.describe(cards, ctx)
		_put(seat, cards)
		best_seat = seat
		best_val = T.play_value(cards, cards, ctx)
		event = "%s 出%s" % [_lbl(seat), desc]
	else:
		var lead = trick[0][1]
		var err = T.check_follow(hands[seat], cards, lead, ctx)
		if err != "":
			return err
		_put(seat, cards)
		var v = T.play_value(cards, lead, ctx)
		var ls = T.eff(int(lead[0]), ctx)
		if T.better(v, best_val):
			best_seat = seat
			best_val = v
			event = "%s %s" % [_lbl(seat), "毙了（用主牌杀）" if int(v[0]) == T.TRUMP and ls != T.TRUMP else "管上了"]
		else:
			event = "%s 跟牌" % _lbl(seat)
	if trick.size() >= 4:
		_end_trick()
	else:
		turn = (turn + 1) % 4
	return ""


func _end_trick() -> void:
	var pts = 0
	for p in trick:
		pts += T.sum_points(p[1])
	all_points += pts
	var att = attackers_team()
	var lead = trick[0][1]
	if best_seat % 2 == att:
		points += pts
	last_trick = trick.duplicate(true)
	last_winner = best_seat
	tricks_done += 1
	trick = []
	turn = best_seat
	event = "%s 这一轮最大" % _lbl(best_seat)
	if pts > 0:
		event += "，%s得%d分" % ["闲家" if best_seat % 2 == att else "庄家方", pts]
	if hands[0].is_empty():
		_finish(lead)


func _finish(lead: Array) -> void:
	var att = attackers_team()
	var dt = dealer % 2
	var bp = T.sum_points(bottom)
	var mult = 0
	var bonus = 0
	if last_winner % 2 == att and bp > 0:
		mult = 2 if bottom_rule == "2" else 2 * T.max_component_size(T.decompose(lead, ctx))
		bonus = bp * mult
		points += bonus
	var keep = points < 80
	var up = 0
	if keep:
		winner_team = dt
		if points == 0:
			up = 3
		elif points < 40:
			up = 2
		else:
			up = 1
		next_dealer = (dealer + 2) % 4
	else:
		winner_team = att
		up = (points - 80) / 40
		next_dealer = (dealer + 1) % 4
	var old = levels.duplicate()
	levels[winner_team] += up
	match_rounds += 1
	if levels[winner_team] > 14:
		match_over = true
		match_winner = winner_team
	phase = "done"
	turn = -1
	var who = "座位%d、%d" % [winner_team + 1, winner_team + 3]
	var txt = "闲家共得%d分" % points
	if bonus > 0:
		txt += "（抠底：底牌%d分×%d）" % [bp, mult]
	elif last_winner % 2 != att and bp > 0:
		txt += "（底牌%d分，庄家方守住了）" % bp
	if keep:
		txt += "。庄家方（%s）守庄，升%d级" % [who, up]
	elif up > 0:
		txt += "。闲家（%s）上台，升%d级" % [who, up]
	else:
		txt += "。闲家（%s）上台" % who
	txt += "，现在：座位1、3打%s，座位2、4打%s" % [T.level_text(levels[0]), T.level_text(levels[1])]
	if match_over:
		txt += "。%s打过A，赢得整场比赛！" % who
	event = txt
	result = {"points": points, "bottom_points": bp, "mult": mult, "bonus": bonus, "keep": keep, "up": up, "old_levels": old, "levels": levels.duplicate(), "next_dealer": next_dealer}


func winners() -> Array:
	if winner_team < 0:
		return []
	return [winner_team, winner_team + 2]


func carry_out() -> Dictionary:
	return {"levels": levels.duplicate(), "dealer": next_dealer, "rounds": match_rounds, "over": match_over}


func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(viewer: int) -> Dictionary:
	var counts = []
	for s in 4:
		counts.append(hands[s].size())
	var shown_trump = trump
	if phase == "declare":
		shown_trump = int(decl.get("suit", -2)) if not decl.is_empty() else -2
	var vctx = ctx if phase != "declare" else T.make_ctx(level, shown_trump)
	var my = []
	if viewer >= 0 and viewer < 4:
		my = T.sort_display(hands[viewer], vctx)
	var show_bottom = []
	if is_over() or (viewer == dealer and phase == "play"):
		show_bottom = T.sort_display(bottom, vctx)
	return {
		"phase": phase,
		"current_seat": current_seat(),
		"level": level,
		"levels": levels.duplicate(),
		"dealer": dealer,
		"trump": shown_trump,
		"decl": decl.duplicate(),
		"declare_opts": declare_options(viewer),
		"counts": counts,
		"my_hand": my,
		"trick": trick.duplicate(true),
		"last_trick": last_trick.duplicate(true),
		"last_winner": last_winner,
		"best_seat": best_seat if not trick.is_empty() else -1,
		"lead_cards": trick[0][1].duplicate() if not trick.is_empty() else [],
		"points": points,
		"attackers": attackers_team(),
		"tricks_done": tricks_done,
		"bottom": show_bottom,
		"throw_on": throw_on,
		"over": is_over(),
		"winners": winners(),
		"result": result.duplicate(true),
		"match_over": match_over,
		"rounds": match_rounds,
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI（超时也用它）

func _support(seat: int, o: Dictionary) -> int:
	var s = int(o["suit"])
	var n = 0
	for c in hands[seat]:
		var ci = int(c)
		var f = ci % 54
		var r = T.rank(ci)
		if s >= 0:
			if f >= 52 or r == level or T.suit(ci) == s:
				n += 1
		else:
			if f >= 52 or r == level:
				n += 2
	return n + (int(o["str"]) - 1)


func bot_action(seat: int) -> Dictionary:
	if is_over():
		return {}
	if phase == "declare":
		var opts = declare_options(seat)
		if opts.is_empty() or (not decl.is_empty() and int(decl["seat"]) % 2 == seat % 2):
			return {"type": "declare", "pass": true}
		var best = {}
		var bs = -1
		for o in opts:
			var v = _support(seat, o)
			if v > bs:
				bs = v
				best = o
		var need = 10 if decl.is_empty() else 12
		if bs >= need:
			return {"type": "declare", "suit": int(best["suit"]), "str": int(best["str"])}
		return {"type": "declare", "pass": true}
	if phase == "bury":
		return {"type": "bury", "cards": T.bury_suggest(hands[seat], ctx)}
	var h = hands[seat]
	if trick.is_empty():
		return {"type": "play", "cards": T.lead_suggest(h, ctx)}
	var lead = trick[0][1]
	var n = lead.size()
	if best_seat % 2 == seat % 2:
		return {"type": "play", "cards": T.follow_play(h, lead, ctx, "feed")}
	var s = T.eff(int(lead[0]), ctx)
	var hs = T.suit_cards(h, s, ctx)
	if hs.size() >= n:
		var hi = T.build_follow(hs, lead, ctx, "high")
		if T.better(T.play_value(hi, lead, ctx), best_val):
			return {"type": "play", "cards": hi}
		return {"type": "play", "cards": T.build_follow(hs, lead, ctx, "low")}
	if hs.is_empty():
		var tr = T.suit_cards(h, T.TRUMP, ctx)
		var pts = 0
		for p in trick:
			pts += T.sum_points(p[1])
		if tr.size() >= n and (pts > 0 or n >= 2 or randf() < 0.35):
			for mode in ["low", "high"]:
				var r = T.build_follow(tr, lead, ctx, mode)
				if T.better(T.play_value(r, lead, ctx), best_val):
					return {"type": "play", "cards": r}
	return {"type": "play", "cards": T.follow_play(h, lead, ctx, "low")}

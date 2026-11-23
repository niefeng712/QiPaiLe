extends SceneTree
## 规则单元测试：用电脑对电脑把整局下完，验证规则不会卡死、结果合法。
## 运行：godot --headless --script res://tests/run_tests.gd

const GomokuLogic = preload("res://games/gomoku/GomokuLogic.gd")
const LudoLogic = preload("res://games/ludo/LudoLogic.gd")
const Registry = preload("res://core/GameRegistry.gd")
const DdzRules = preload("res://games/doudizhu/DdzRules.gd")
const DdzLogic = preload("res://games/doudizhu/DoudizhuLogic.gd")
const TljRules = preload("res://games/tuolaji/TljRules.gd")
const TljLogic = preload("res://games/tuolaji/TuolajiLogic.gd")
const MjRules = preload("res://games/mahjong/MjRules.gd")
const MjLogic = preload("res://games/mahjong/MahjongLogic.gd")
const CcRules = preload("res://games/checkers/CcRules.gd")
const CcLogic = preload("res://games/checkers/CheckersLogic.gd")


func _init() -> void:
	var failures = 0
	failures += _test_registry()
	failures += _test_gomoku_win()
	for i in 5:
		failures += _test_gomoku_bots(i + 1)
	for i in 5:
		failures += _test_ludo_bots([0, 1, 2, 3], {"takeoff": "6", "jump": "on", "over": "bounce"}, i + 1)
	failures += _test_ludo_bots([0, 2], {"takeoff": "56", "jump": "off", "over": "free"}, 1)
	failures += _test_ludo_bots([1, 2, 3], {"takeoff": "6", "jump": "on", "over": "free"}, 2)
	failures += _test_ddz_rules()
	failures += _test_ddz2_rules()
	var modes = [
		{"players": "3", "deal": "shuffle", "laizi": "off", "cap": "none", "bidmode": "score", "double": "off", "mingpai": "off"},
		{"players": "3", "deal": "noshuffle", "laizi": "off", "cap": "none", "bidmode": "rob", "double": "on", "mingpai": "on"},
		{"players": "3", "deal": "shuffle", "laizi": "on", "cap": "32", "bidmode": "rob", "double": "on", "mingpai": "off"},
		{"players": "3", "deal": "noshuffle", "laizi": "on", "cap": "16", "bidmode": "score", "double": "on", "mingpai": "on"},
		{"players": "4", "deal": "shuffle", "laizi": "off", "cap": "none", "bidmode": "score", "double": "on", "mingpai": "on"},
		{"players": "4", "deal": "noshuffle", "laizi": "off", "cap": "64", "bidmode": "rob", "double": "on", "mingpai": "on"},
		{"players": "4", "deal": "shuffle", "laizi": "off", "cap": "none", "bidmode": "rob", "double": "off", "mingpai": "off"},
	]
	for m in modes:
		for i in 4:
			failures += _test_ddz_bots(m, i + 1, false)
	failures += _test_ddz_bots(modes[1], 1, true)
	failures += _test_ddz_bots(modes[3], 2, true)
	failures += _test_ddz_bots(modes[5], 3, true)
	failures += _test_ddz_bots(modes[4], 4, true)
	failures += _test_tlj_rules()
	failures += _test_tlj_random()
	failures += _test_tlj_match({"throw": "on", "bottom": "size"}, 10)
	failures += _test_tlj_match({"throw": "off", "bottom": "2"}, 6)
	failures += _test_mj_rules()
	var mjm = [
		[{"mode": "xuezhan", "huan": "on", "cap": "4"}, 4],
		[{"mode": "xuezhan", "huan": "off", "cap": "none"}, 2],
		[{"mode": "tuidao", "pao": "zimo", "ma": "4", "cap": "5"}, 3],
		[{"mode": "tuidao", "pao": "pao", "ma": "0", "cap": "5"}, 2],
		[{"mode": "dazhong", "cap": "4"}, 4],
	]
	for mm in mjm:
		for i in int(mm[1]):
			failures += _test_mj_game(mm[0], i + 1, false)
	failures += _test_mj_game({"mode": "xuezhan", "huan": "on", "cap": "4"}, 2, true)
	failures += _test_mj_game({"mode": "dazhong", "cap": "4"}, 3, true)
	failures += _test_cc_rules()
	var ccm = [
		[[0, 1], {"jump": "adjacent", "pieces": "10", "end": "first"}, 3],
		[[0, 1], {"jump": "far", "pieces": "10", "end": "first"}, 2],
		[[0, 2, 4], {"jump": "adjacent", "pieces": "10", "end": "all"}, 1],
		[[0, 1, 2, 3], {"jump": "adjacent", "pieces": "10", "end": "first"}, 1],
		[[0, 1, 2, 3, 4, 5], {"jump": "adjacent", "pieces": "6", "end": "first"}, 1],
		[[0, 1, 2, 3, 4, 5], {"jump": "far", "pieces": "10", "end": "first"}, 1],
		[[0, 1, 2, 3, 4, 5], {"jump": "adjacent", "pieces": "10", "end": "first"}, 1],
	]
	for cm in ccm:
		for i in int(cm[2]):
			failures += _test_cc_game(cm[0], cm[1], i + 1)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("TESTS FAILED: %d" % failures)
	quit(1 if failures > 0 else 0)


func _fail(msg: String) -> int:
	printerr("FAIL: " + msg)
	return 1


func _test_registry() -> int:
	var f = 0
	for g in Registry.GAMES:
		if bool(g.get("ready", false)):
			if load(str(g["logic"])) == null:
				f += _fail("logic missing for " + str(g["id"]))
			if not ResourceLoader.exists(str(g["view"])):
				f += _fail("view missing for " + str(g["id"]))
	print("registry ok")
	return f


func _test_gomoku_win() -> int:
	var lg = GomokuLogic.new()
	lg.setup([0, 1], {"first": "seat0"}, 1)
	for i in 4:
		if lg.apply(0, {"type": "place", "x": i, "y": 0}) != "":
			return _fail("gomoku black place")
		if lg.apply(1, {"type": "place", "x": i, "y": 1}) != "":
			return _fail("gomoku white place")
	if lg.apply(1, {"type": "place", "x": 9, "y": 9}) == "":
		return _fail("gomoku accepted out-of-turn move")
	if lg.apply(0, {"type": "place", "x": 4, "y": 0}) != "":
		return _fail("gomoku final place")
	var st = lg.get_state()
	if not bool(st["over"]) or int(st["winners"][0]) != 0:
		return _fail("gomoku win not detected")
	print("gomoku win ok")
	return 0


func _test_gomoku_bots(round_no: int) -> int:
	var lg = GomokuLogic.new()
	lg.setup([0, 1], {"first": "alternate"}, round_no)
	var steps = 0
	while not lg.is_over() and steps < 300:
		var seat = lg.current_seat()
		var a = lg.bot_action(seat)
		var err = lg.apply(seat, a)
		if err != "":
			return _fail("gomoku bot illegal move: " + err)
		steps += 1
	if not lg.is_over():
		return _fail("gomoku bots never finished")
	print("gomoku bots round %d finished in %d moves" % [round_no, steps])
	return 0


func _test_ludo_bots(players: Array, rules: Dictionary, round_no: int) -> int:
	var lg = LudoLogic.new()
	lg.setup(players, rules, round_no)
	var steps = 0
	while not lg.is_over() and steps < 30000:
		var seat = lg.current_seat()
		var a = lg.bot_action(seat)
		if a.is_empty():
			return _fail("ludo bot returned empty action")
		var err = lg.apply(seat, a)
		if err != "":
			return _fail("ludo bot illegal action: " + err)
		var st = lg.get_state()
		for s in players:
			for k in 4:
				var p = int(st["pos"][s][k])
				if p < -1 or p > 56:
					return _fail("ludo bad position %d" % p)
		steps += 1
	if not lg.is_over():
		return _fail("ludo bots never finished")
	var st2 = lg.get_state()
	if st2["winners"].size() != players.size():
		return _fail("ludo ranking incomplete")
	print("ludo %s finished in %d actions, ranking %s" % [str(players), steps, str(st2["winners"])])
	return 0


# ---------------------------------------------------------------- 斗地主

func _c(r: int, s: int) -> int:
	return (r - 3) * 4 + s


func _type_of(cards: Array, laizi: int) -> String:
	var p = DdzRules.choose_pattern(cards, laizi, {})
	return str(p.get("type", "none"))


func _expect(cond: bool, msg: String) -> int:
	if cond:
		return 0
	return _fail("ddz rule: " + msg)


func _test_ddz_rules() -> int:
	DdzRules.set_two_decks(false)
	var f = 0
	f += _expect(_type_of([_c(3, 0)], 0) == "single", "single")
	f += _expect(_type_of([_c(5, 0), _c(5, 1)], 0) == "pair", "pair")
	f += _expect(_type_of([_c(5, 0), _c(6, 1)], 0) == "none", "bad pair")
	f += _expect(_type_of([_c(3, 0), _c(4, 0), _c(5, 0), _c(6, 0), _c(7, 0)], 0) == "straight", "straight")
	f += _expect(_type_of([_c(11, 0), _c(12, 0), _c(13, 0), _c(14, 0), _c(15, 0)], 0) == "none", "straight with 2")
	f += _expect(_type_of([_c(3, 0), _c(3, 1), _c(4, 0), _c(4, 1), _c(5, 0), _c(5, 1)], 0) == "pair_straight", "pair straight")
	f += _expect(_type_of([_c(3, 0), _c(3, 1), _c(3, 2), _c(4, 0), _c(4, 1), _c(4, 2), _c(9, 0), _c(10, 0)], 0) == "plane_1", "plane_1")
	f += _expect(_type_of([_c(8, 0), _c(8, 1), _c(8, 2), _c(6, 0)], 0) == "triple_1", "triple_1")
	f += _expect(_type_of([_c(8, 0), _c(8, 1), _c(8, 2), _c(6, 0), _c(6, 1)], 0) == "triple_2", "triple_2")
	f += _expect(_type_of([52, 53], 0) == "rocket", "rocket")
	f += _expect(_type_of([_c(7, 0), _c(7, 1), _c(7, 2), _c(7, 3)], 0) == "bomb", "bomb")
	var straight = DdzRules.choose_pattern([_c(3, 0), _c(4, 0), _c(5, 0), _c(6, 0), _c(7, 0)], 0, {})
	var bomb3 = DdzRules.choose_pattern([_c(3, 0), _c(3, 1), _c(3, 2), _c(3, 3)], 0, {})
	f += _expect(DdzRules.can_beat(bomb3, straight), "bomb beats straight")
	f += _expect(not DdzRules.choose_pattern([_c(4, 0), _c(5, 0), _c(6, 0), _c(7, 0), _c(8, 0)], 0, straight).is_empty(), "higher straight beats")
	f += _expect(DdzRules.choose_pattern([_c(4, 0), _c(5, 0), _c(6, 0), _c(7, 0), _c(8, 0), _c(9, 0)], 0, straight).is_empty(), "longer straight can't beat")
	f += _expect(not DdzRules.choose_pattern([52, 53], 0, bomb3).is_empty(), "rocket beats bomb")
	# 癞子 = 9
	var soft = DdzRules.choose_pattern([_c(5, 0), _c(5, 1), _c(5, 2), _c(9, 0)], 9, {})
	f += _expect(str(soft.get("type", "")) == "bomb" and int(soft["level"]) == 1, "soft bomb")
	var hard4 = DdzRules.choose_pattern([_c(4, 0), _c(4, 1), _c(4, 2), _c(4, 3)], 9, {})
	f += _expect(int(hard4.get("level", 0)) == 2 and DdzRules.can_beat(hard4, soft), "hard bomb beats soft bomb")
	var lz4 = DdzRules.choose_pattern([_c(9, 0), _c(9, 1), _c(9, 2), _c(9, 3)], 9, {})
	f += _expect(int(lz4.get("level", 0)) == 3 and DdzRules.can_beat(lz4, hard4), "laizi bomb beats hard bomb")
	f += _expect(_type_of([_c(3, 0), _c(4, 0), _c(9, 1), _c(6, 0), _c(7, 0)], 9) == "straight", "laizi fills straight")
	var pair5 = DdzRules.choose_pattern([_c(5, 0), _c(5, 1)], 9, {})
	f += _expect(not DdzRules.choose_pattern([_c(13, 0), _c(9, 2)], 9, pair5).is_empty(), "laizi pair beats")
	var hint = DdzRules.follow_candidates([_c(6, 0), _c(6, 1), _c(10, 0), 53], 0, pair5)
	f += _expect(hint.size() >= 1, "follow hint pair")
	if f == 0:
		print("doudizhu rules ok")
	return f


func _test_ddz2_rules() -> int:
	DdzRules.set_two_decks(true)
	var f = 0
	var b4 = DdzRules.choose_pattern([_c(14, 0), _c(14, 1), _c(14, 2), _c(14, 3)], 0, {})
	var b5 = DdzRules.choose_pattern([_c(5, 0), _c(5, 1), _c(5, 2), _c(5, 3), _c(5, 0) + 54], 0, {})
	f += _expect(str(b5.get("type", "")) == "bomb" and int(b5["n"]) == 5, "5-card bomb")
	f += _expect(DdzRules.can_beat(b5, b4), "5-card bomb beats 4-card bomb")
	f += _expect(not DdzRules.can_beat(b4, b5), "4-card bomb can't beat 5-card bomb")
	var jj = DdzRules.choose_pattern([52, 53, 106, 107], 0, {})
	f += _expect(str(jj.get("type", "")) == "rocket" and DdzRules.can_beat(jj, b5), "four jokers")
	f += _expect(_type_of([53, 107], 0) == "pair", "pair of big jokers")
	f += _expect(_type_of([52, 53], 0) == "none", "mixed jokers invalid with two decks")
	var hints = DdzRules.follow_candidates([_c(9, 0), _c(9, 1), _c(9, 2), _c(9, 3), _c(9, 0) + 54, _c(3, 0)], 0, b4)
	f += _expect(hints.size() >= 1, "two-deck bomb hint")
	var sorted = DdzRules.sort_hand([_c(3, 0), _c(3, 0) + 54, 53, _c(15, 1) + 54])
	f += _expect(int(sorted[0]) == 53 and DdzRules.card_rank(int(sorted[3])) == 3, "two-deck sort")
	DdzRules.set_two_decks(false)
	if f == 0:
		print("doudizhu two-deck rules ok")
	return f


func _test_ddz_bots(rules: Dictionary, round_no: int, timeout0: bool) -> int:
	var lg = DdzLogic.new()
	var nn = 4 if str(rules.get("players", "3")) == "4" else 3
	var seats = []
	for i in nn:
		seats.append(i)
	lg.setup(seats, rules, round_no)
	var steps = 0
	var t0 = Time.get_ticks_msec()
	var phases = {}
	while not lg.is_over() and steps < 4000:
		var seat = lg.current_seat()
		phases[lg.phase] = true
		if lg.phase == "ming" and not lg.ming_done[seat]:
			if not lg.get_state_for(seat)["my_hand"].is_empty():
				return _fail("ddz hand visible before ming decision")
		var a = lg.timeout_action(seat) if (timeout0 and seat == 0) else lg.bot_action(seat)
		if a.is_empty():
			return _fail("ddz bot empty action (phase %s)" % lg.phase)
		var err = lg.apply(seat, a)
		if err != "":
			return _fail("ddz illegal action %s: %s (phase %s)" % [str(a), err, lg.phase])
		var total = lg.played_cards
		for s in nn:
			total += lg.hands[s].size()
		if lg.landlord < 0:
			total += lg.bottom.size()
		if total != 54 * lg.decks:
			return _fail("ddz card count %d" % total)
		steps += 1
	if not lg.is_over():
		return _fail("ddz never finished")
	var sum = 0
	for v in lg.round_scores():
		sum += int(v)
	if sum != 0 or lg.round_scores().size() != nn:
		return _fail("ddz scores not zero-sum")
	var played = 0
	for v in lg.played_rank:
		played += int(v)
	if played != lg.played_cards:
		return _fail("ddz card counter mismatch")
	print("ddz %dp %s/%s dbl=%s ming=%s laizi=%s r%d%s: %d actions, landlord %d, bombs %d, robs %d, ming x%d, doubles %s, mult x%d, scores %s, %dms" % [nn, str(rules.get("deal")), str(rules.get("bidmode")), str(rules.get("double")), str(rules.get("mingpai")), str(rules.get("laizi")), round_no, " (seat0 timeouts)" if timeout0 else "", steps, lg.landlord, lg.bombs, lg.robs, lg.ming_mult, str(lg.doubles), lg.final_mult, str(lg.round_scores()), Time.get_ticks_msec() - t0])
	return 0


# ---------------------------------------------------------------- 升级拖拉机

func _tc(r: int, s: int, d: int = 0) -> int:
	return TljRules.card_id(r, s, d)


func _test_tlj_rules() -> int:
	var f = 0
	var ctx = TljRules.make_ctx(2, 1)
	var d = TljRules.decompose([_tc(3, 0), _tc(3, 0, 1), _tc(4, 0), _tc(4, 0, 1)], ctx)
	f += _expect(TljRules.max_tractor(d) == 2, "tlj plain tractor")
	var ctx5 = TljRules.make_ctx(5, 1)
	d = TljRules.decompose([_tc(4, 0), _tc(4, 0, 1), _tc(6, 0), _tc(6, 0, 1)], ctx5)
	f += _expect(TljRules.max_tractor(d) == 2, "tlj tractor skips level rank")
	var chain = [_tc(14, 1), _tc(14, 1, 1), _tc(2, 0), _tc(2, 0, 1), _tc(2, 1), _tc(2, 1, 1), 52, 106, 53, 107]
	d = TljRules.decompose(chain, ctx)
	f += _expect(TljRules.max_tractor(d) == 5, "tlj trump tractor A-副2-主2-小王-大王")
	d = TljRules.decompose([_tc(2, 0), _tc(2, 0, 1), _tc(2, 2), _tc(2, 2, 1)], ctx)
	f += _expect(TljRules.max_tractor(d) == 0 and TljRules.total_pairs(d) == 2, "two off-suit level pairs are not a tractor")
	f += _expect(TljRules.eff(_tc(2, 3), ctx) == TljRules.TRUMP and TljRules.eff(_tc(9, 1), ctx) == TljRules.TRUMP and TljRules.eff(_tc(9, 0), ctx) == 0, "trump membership")
	var lead = [_tc(9, 0), _tc(9, 0, 1)]
	var hand = [_tc(5, 0), _tc(5, 0, 1), _tc(7, 0), _tc(8, 0), _tc(3, 2)]
	f += _expect(TljRules.check_follow(hand, [_tc(7, 0), _tc(8, 0)], lead, ctx) != "", "must follow pair")
	f += _expect(TljRules.check_follow(hand, [_tc(5, 0), _tc(5, 0, 1)], lead, ctx) == "", "pair follow ok")
	f += _expect(TljRules.check_follow(hand, [_tc(7, 0), _tc(3, 2)], lead, ctx) != "", "must follow suit")
	var tlead = [_tc(9, 0), _tc(9, 0, 1), _tc(10, 0), _tc(10, 0, 1)]
	var th = [_tc(3, 0), _tc(3, 0, 1), _tc(4, 0), _tc(4, 0, 1), _tc(12, 0), _tc(13, 0)]
	f += _expect(TljRules.check_follow(th, [_tc(3, 0), _tc(3, 0, 1), _tc(12, 0), _tc(13, 0)], tlead, ctx) != "", "must follow tractor")
	f += _expect(TljRules.check_follow(th, [_tc(3, 0), _tc(3, 0, 1), _tc(4, 0), _tc(4, 0, 1)], tlead, ctx) == "", "tractor follow ok")
	var lv = TljRules.play_value(lead, lead, ctx)
	f += _expect(TljRules.better(TljRules.play_value([_tc(3, 1), _tc(3, 1, 1)], lead, ctx), lv), "trump pair ruffs plain pair")
	f += _expect(not TljRules.better(TljRules.play_value([_tc(3, 1), _tc(4, 1)], lead, ctx), lv), "two trump singles can't beat a pair")
	f += _expect(TljRules.better(TljRules.play_value([_tc(10, 0), _tc(10, 0, 1)], lead, ctx), lv), "higher pair wins")
	f += _expect(not TljRules.better(TljRules.play_value([_tc(5, 0), _tc(5, 0, 1)], lead, ctx), lv), "lower pair loses")
	var s1 = TljRules.play_value([_tc(2, 0)], [_tc(2, 2)], ctx)
	f += _expect(not TljRules.better(s1, TljRules.play_value([_tc(2, 2)], [_tc(2, 2)], ctx)), "equal off-suit level cards: first one wins")
	var thr = [_tc(14, 0), _tc(13, 0)]
	var fl = TljRules.throw_fail(thr, [[_tc(14, 0, 1)], [_tc(3, 0)], []], ctx)
	f += _expect(fl.size() == 1 and int(fl[0]) == _tc(13, 0), "failed throw forces the K")
	f += _expect(TljRules.throw_fail(thr, [[_tc(12, 0)], [], [_tc(5, 1)]], ctx).is_empty(), "valid throw")
	var thr2 = [_tc(14, 0), _tc(14, 0, 1), _tc(6, 0)]
	f += _expect(TljRules.throw_fail(thr2, [[_tc(5, 0), _tc(4, 0)]], ctx).is_empty(), "pair A + small single throw ok when others only have smaller")
	f += _expect(TljRules.throw_fail(thr2, [[_tc(7, 0)]], ctx).size() == 1, "throw fails on single")
	if f == 0:
		print("tuolaji rules ok")
	return f


func _test_tlj_random() -> int:
	var f = 0
	for it in 400:
		var deck = []
		for i in 108:
			deck.append(i)
		deck.shuffle()
		var cx = TljRules.make_ctx(randi_range(2, 14), randi_range(-1, 3))
		var h = deck.slice(0, randi_range(6, 25))
		var other = deck.slice(60, 85)
		var leads = [TljRules.lead_suggest(other, cx)]
		var e = TljRules.eff(int(other[0]), cx)
		var sc = TljRules.suit_cards(other, e, cx)
		leads.append(sc.slice(0, mini(sc.size(), randi_range(1, 6))))
		var od = TljRules.decompose(sc, cx)
		if not od["tractors"].is_empty():
			leads.append(od["tractors"][0][2])
		for ld in leads:
			if ld.is_empty():
				continue
			if not TljRules.same_suit(ld, cx):
				return _fail("tlj lead not single suit")
			if ld.size() > h.size():
				continue
			for mode in ["low", "high", "feed"]:
				var pl = TljRules.follow_play(h, ld, cx, mode)
				var err = TljRules.check_follow(h, pl, ld, cx)
				if err != "" or pl.size() != ld.size():
					return _fail("tlj follow_play %s illegal (%s) lead=%s play=%s" % [mode, err, str(ld), str(pl)])
				for c in pl:
					if not h.has(c):
						return _fail("tlj follow_play used a card not in hand")
		var b = TljRules.bury_suggest(deck.slice(0, 33), cx)
		if b.size() != 8:
			return _fail("tlj bury size")
	print("tuolaji random follow ok")
	return f


func _test_tlj_match(rules: Dictionary, rounds: int) -> int:
	var carry = {}
	var t0 = Time.get_ticks_msec()
	for rn in range(1, rounds + 1):
		var r = rules.duplicate()
		r["_carry"] = carry
		var lg = TljLogic.new()
		lg.setup([0, 1, 2, 3], r, rn)
		var steps = 0
		var phases = {}
		while not lg.is_over() and steps < 3000:
			var seat = lg.current_seat()
			phases[lg.phase] = true
			var a = lg.bot_action(seat)
			if a.is_empty():
				return _fail("tlj bot empty action in %s" % lg.phase)
			var err = lg.apply(seat, a)
			if err != "":
				return _fail("tlj illegal %s in %s: %s" % [str(a), lg.phase, err])
			var total = lg.played_count + lg.bottom.size()
			for s in 4:
				total += lg.hands[s].size()
			if total != 108:
				return _fail("tlj card count %d" % total)
			steps += 1
		if not lg.is_over():
			return _fail("tlj round never finished")
		if lg.tricks_done < 1 or lg.all_points + TljRules.sum_points(lg.bottom) != 200:
			return _fail("tlj points don't add up to 200")
		var st = lg.get_state_for(0)
		if st["winners"].size() != 2:
			return _fail("tlj winners")
		print("tlj %s r%d: dealer %d, trump %d, level %d, tricks %d, attackers %d pts (bottom bonus %d), levels %s, next dealer %d%s" % [str(rules), rn, lg.dealer, lg.trump, lg.level, lg.tricks_done, lg.points, int(lg.result.get("bonus", 0)), str(lg.levels), lg.next_dealer, " MATCH OVER" if lg.match_over else ""])
		carry = lg.carry_out()
	print("tlj match ok in %dms" % (Time.get_ticks_msec() - t0))
	return 0


# ---------------------------------------------------------------- 麻将

func _mk(types: Array) -> Array:
	var used = {}
	var out = []
	for t in types:
		var k = int(used.get(t, 0))
		used[t] = k + 1
		out.append(int(t) * 4 + k)
	return out


func _mc(types: Array) -> Array:
	return MjRules.counts_of(_mk(types))


func _test_mj_rules() -> int:
	var f = 0
	var win = _mc([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22, 22])
	f += _expect(MjRules.is_win(win, 0, true, true) and MjRules.shanten(win, 0, true) == -1, "mj standard win")
	var tp = _mc([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22])
	f += _expect(MjRules.shanten(tp, 0, true) == 0, "mj tenpai single wait")
	var tp2 = _mc([1, 2, 3, 4, 5, 6, 10, 11, 12, 20, 20, 30, 30])
	f += _expect(MjRules.shanten(tp2, 0, false) == 0, "mj tenpai shanpon")
	var not_win = _mc([0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 22, 22])
	f += _expect(not MjRules.is_win(not_win, 0, true, true), "mj not a win")
	var seven = _mc([0, 0, 2, 2, 5, 5, 9, 9, 13, 13, 20, 20, 26, 26])
	f += _expect(MjRules.is_win(seven, 0, true, false) and not MjRules.is_win(seven, 0, false, false), "mj seven pairs")
	var dragon = _mc([0, 0, 0, 0, 5, 5, 9, 9, 13, 13, 20, 20, 26, 26])
	f += _expect(MjRules.is_win(dragon, 0, true, false), "mj dragon seven pairs")
	var ko = _mc([0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33, 33])
	f += _expect(MjRules.is_win(ko, 0, false, true) and not MjRules.is_win(ko, 0, false, false), "mj thirteen orphans")
	var pp = _mc([1, 1, 1, 5, 5, 5, 12, 12, 12, 20, 20, 20, 30, 30])
	f += _expect(MjRules.is_all_triplets(pp) and MjRules.is_win(pp, 0, false, false), "mj all triplets")
	f += _expect(MjRules.is_win(_mc([7, 7]), 4, false, false), "mj four melds + pair")
	f += _expect(MjRules.shanten(_mc([7]), 4, false) == 0, "mj single-tile wait")
	var nine = _mc([0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 4])
	f += _expect(MjRules.is_win(nine, 0, false, false), "mj pure nine gates style win")
	var hand = _mk([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22, 30])
	var d = MjRules.suggest_discard(hand, 0, -1, 34)
	f += _expect(d / 4 == 30 or d / 4 == 22, "mj suggest discard isolated tile (got %s)" % MjRules.tname(d / 4))
	var qh = _mk([0, 1, 2, 9, 10, 11, 12, 13, 14, 18, 19, 20, 21, 21])
	f += _expect(MjRules.tsuit(MjRules.suggest_discard(qh, 0, 0, 27) / 4) == 0, "mj must discard que suit first")
	if f == 0:
		print("mahjong rules ok")
	return f


func _test_mj_game(rules: Dictionary, round_no: int, timeout0: bool) -> int:
	var lg = MjLogic.new()
	lg.setup([0, 1, 2, 3], rules, round_no)
	var full = 108 if str(rules["mode"]) == "xuezhan" else 136
	var steps = 0
	var t0 = Time.get_ticks_msec()
	var stat = {"peng": 0, "gang": 0, "chi": 0, "agang": 0}
	while not lg.is_over() and steps < 4000:
		var seat = lg.current_seat()
		var a = {}
		if timeout0 and seat == 0:
			a = lg.timeout_action(seat)
		if a.is_empty():
			a = lg.bot_action(seat)
		if a.is_empty():
			return _fail("mj bot empty action in %s" % lg.phase)
		var act = str(a.get("act", a.get("type", "")))
		var err = lg.apply(seat, a)
		if err != "":
			return _fail("mj illegal %s in %s: %s" % [str(a), lg.phase, err])
		if stat.has(act):
			stat[act] += 1
		var tot = lg.wall.size() + lg.ma.size()
		for s in 4:
			tot += lg.hands[s].size() + lg.discards[s].size()
			for m in lg.melds[s]:
				tot += m["tiles"].size()
		for s in 4:
			for x in lg.exch_pick[s]:
				if not lg.hands[(s + lg.exch_dir) % 4].has(x) and lg.phase == "exchange":
					tot += 1
		if tot != full:
			return _fail("mj tile count %d != %d (phase %s)" % [tot, full, lg.phase])
		steps += 1
	if not lg.is_over():
		return _fail("mj never finished")
	var sum = 0
	for v in lg.scores:
		sum += int(v)
	if sum != 0:
		return _fail("mj scores not zero-sum %s" % str(lg.scores))
	for s in 4:
		var st = lg.get_state_for(s)
		if st["my_hand"].size() + (1 if int(st["drawn"]) >= 0 else 0) != lg.hands[s].size():
			return _fail("mj state hand mismatch")
	var ws = []
	for w in lg.wins:
		var fn = []
		for x in w["fans"]:
			fn.append(str(x[0]))
		ws.append("%d:%s%s%d番" % [int(w["seat"]), "自摸" if bool(w["zimo"]) else "点炮", "/".join(PackedStringArray(fn)), int(w["fan"])])
	print("mj %s r%d%s: %d actions, wall left %d, %s, wins [%s], checks %d, scores %s, %dms" % [str(rules["mode"]), round_no, " (seat0 timeouts)" if timeout0 else "", steps, lg.wall.size(), str(stat), ", ".join(PackedStringArray(ws)), lg.checks.size(), str(lg.scores), Time.get_ticks_msec() - t0])
	return 0


# ---------------------------------------------------------------- 中国跳棋

func _ci(x: int, y: int) -> int:
	for i in CcRules.count():
		var c = CcRules.cell(i)
		if c.x == x and c.y == y:
			return i
	return -1


func _test_cc_rules() -> int:
	var f = 0
	f += _expect(CcRules.count() == 121, "cc board has 121 holes (got %d)" % CcRules.count())
	for p in 6:
		f += _expect(CcRules.zone(p, 10).size() == 10, "cc corner %d has 10 holes" % p)
		f += _expect(CcRules.zone(p, 6).size() == 6, "cc corner %d small zone 6" % p)
	var occ = []
	occ.resize(121)
	occ.fill(-1)
	var a = _ci(0, 0)
	var b = _ci(1, -1)
	var c = _ci(2, -2)
	occ[a] = 0
	occ[b] = 1
	var r = CcRules.reachable(occ, a, false)
	f += _expect(r.has(c) and r[c].size() == 2, "cc adjacent jump")
	f += _expect(r.has(_ci(-1, 1)), "cc single step")
	occ[b] = -1
	occ[c] = 1
	r = CcRules.reachable(occ, a, false)
	f += _expect(not r.has(_ci(4, -4)), "cc no far jump in adjacent mode")
	r = CcRules.reachable(occ, a, true)
	f += _expect(r.has(_ci(4, -4)), "cc far jump over midpoint piece")
	occ[c] = -1
	occ[b] = 1
	occ[_ci(3, -3)] = 1
	r = CcRules.reachable(occ, a, false)
	f += _expect(r.has(c) and r.has(_ci(4, -4)) and r[_ci(4, -4)].size() == 3, "cc chain jump")
	if f == 0:
		print("checkers rules ok")
	return f


func _test_cc_game(seats: Array, rules: Dictionary, rn: int) -> int:
	var lg = CcLogic.new()
	lg.setup(seats, rules, rn)
	var t0 = Time.get_ticks_msec()
	var steps = 0
	var np = 10 if str(rules["pieces"]) == "10" else 6
	while not lg.is_over() and steps < 20000:
		var s = lg.current_seat()
		var a = lg.bot_action(s)
		if a.is_empty():
			return _fail("cc bot empty action")
		var err = lg.apply(s, a)
		if err != "":
			return _fail("cc illegal %s: %s" % [str(a), err])
		steps += 1
	if not lg.is_over():
		return _fail("cc never finished")
	var cnt = {}
	for v in lg.occ:
		if int(v) >= 0:
			cnt[int(v)] = int(cnt.get(int(v), 0)) + 1
	for s in seats:
		if int(cnt.get(int(s), 0)) != np:
			return _fail("cc piece count wrong for seat %d" % int(s))
	if lg.ranking.size() != seats.size():
		return _fail("cc ranking incomplete")
	var prog = []
	for s in seats:
		prog.append(lg.in_target_count(int(s)))
	if not lg.capped and not lg.finished.is_empty():
		var w = int(lg.finished[0])
		if lg.in_target_count(w) < np and lg.moves / seats.size() < CcLogic.BLOCK_ROUNDS:
			return _fail("cc winner %d finished early with only %d pieces in target" % [w, lg.in_target_count(w)])
	print("cc %dp %s r%d: %d moves (%d rounds)%s, finished %s, ranking %s, in-target %s, %dms" % [seats.size(), str(rules), rn, lg.moves, lg.moves / seats.size(), " CAPPED" if lg.capped else "", str(lg.finished), str(lg.ranking), str(prog), Time.get_ticks_msec() - t0])
	return 0

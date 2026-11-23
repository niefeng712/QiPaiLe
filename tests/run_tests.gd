extends SceneTree
## 规则单元测试：用电脑对电脑把整局下完，验证规则不会卡死、结果合法。
## 运行：godot --headless --script res://tests/run_tests.gd

const GomokuLogic = preload("res://games/gomoku/GomokuLogic.gd")
const LudoLogic = preload("res://games/ludo/LudoLogic.gd")
const Registry = preload("res://core/GameRegistry.gd")
const DdzRules = preload("res://games/doudizhu/DdzRules.gd")
const DdzLogic = preload("res://games/doudizhu/DoudizhuLogic.gd")


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

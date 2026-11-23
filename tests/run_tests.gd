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
	var modes = [
		{"deal": "shuffle", "laizi": "off", "cap": "none"},
		{"deal": "noshuffle", "laizi": "off", "cap": "none"},
		{"deal": "shuffle", "laizi": "on", "cap": "32"},
		{"deal": "noshuffle", "laizi": "on", "cap": "16"},
	]
	for m in modes:
		for i in 4:
			failures += _test_ddz_bots(m, i + 1)
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


func _test_ddz_bots(rules: Dictionary, round_no: int) -> int:
	var lg = DdzLogic.new()
	lg.setup([0, 1, 2], rules, round_no)
	var steps = 0
	var t0 = Time.get_ticks_msec()
	while not lg.is_over() and steps < 2000:
		var seat = lg.current_seat()
		var a = lg.bot_action(seat)
		if a.is_empty():
			return _fail("ddz bot empty action")
		var err = lg.apply(seat, a)
		if err != "":
			return _fail("ddz bot illegal action %s: %s (phase %s)" % [str(a), err, lg.phase])
		var total = lg.played_cards
		for s in 3:
			total += lg.hands[s].size()
		if lg.landlord < 0:
			total += lg.bottom.size()
		if total != 54:
			return _fail("ddz card count %d" % total)
		steps += 1
	if not lg.is_over():
		return _fail("ddz bots never finished")
	var sum = 0
	for v in lg.round_scores():
		sum += int(v)
	if sum != 0:
		return _fail("ddz scores not zero-sum")
	var st = lg.get_state_for(0)
	if st["my_hand"].size() != lg.hands[0].size():
		return _fail("ddz state hand mismatch")
	print("ddz %s round %d: %d actions, landlord seat %d, bombs %d, x%d, scores %s, laizi %d, %dms" % [str(rules), round_no, steps, lg.landlord, lg.bombs, lg.final_mult, str(lg.round_scores()), lg.laizi, Time.get_ticks_msec() - t0])
	return 0

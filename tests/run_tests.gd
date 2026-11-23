extends SceneTree
## 规则单元测试：用电脑对电脑把整局下完，验证规则不会卡死、结果合法。
## 运行：godot --headless --script res://tests/run_tests.gd

const GomokuLogic = preload("res://games/gomoku/GomokuLogic.gd")
const LudoLogic = preload("res://games/ludo/LudoLogic.gd")
const Registry = preload("res://core/GameRegistry.gd")


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

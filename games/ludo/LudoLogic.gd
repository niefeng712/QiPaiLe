extends RefCounted
## 飞行棋规则（只在房主端运行）
## 座位号 = 颜色：0红 1黄 2蓝 3绿
## 每架飞机的进度：-1 = 在老家；0..50 = 外圈跑道；51..55 = 本色终点通道；56 = 到达终点

const TRACK_LEN = 52
const LAST_MAIN = 50
const FINISH = 56
const JUMP = 4
const CNAMES = ["红方", "黄方", "蓝方", "绿方"]

var players = []
var pos = []
var turn = 0
var phase = "roll"
var dice = 0
var movable = []
var six_count = 0
var finished_order = []
var over = false
var event = ""
var rules = {}


func setup(seat_list: Array, game_rules: Dictionary, round_no: int) -> void:
	players = []
	for s in seat_list:
		players.append(int(s))
	players.sort()
	rules = game_rules.duplicate(true)
	pos = []
	for i in 4:
		pos.append([-1, -1, -1, -1])
	turn = (maxi(round_no, 1) - 1) % players.size()
	phase = "roll"
	dice = 0
	movable = []
	six_count = 0
	finished_order = []
	over = false
	event = "游戏开始，%s先掷骰子" % CNAMES[players[turn]]


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	return int(players[turn])


func bot_delay() -> float:
	return 0.7


func _square(seat: int, p: int) -> int:
	return (seat * 13 + p) % TRACK_LEN


func _can_takeoff(d: int) -> bool:
	if d == 6:
		return true
	return d == 5 and str(rules.get("takeoff", "6")) == "56"


func _target(p: int, d: int) -> int:
	if p < 0:
		return 0
	var t = p + d
	if t > FINISH:
		if str(rules.get("over", "bounce")) == "bounce":
			t = FINISH - (t - FINISH)
		else:
			t = FINISH
	return t


func _jump_applies(p: int, t: int) -> bool:
	if str(rules.get("jump", "on")) != "on":
		return false
	return p >= 0 and t > 0 and t <= LAST_MAIN and t % 4 == 0 and t + JUMP <= LAST_MAIN


func _compute_movable(seat: int, d: int) -> Array:
	var res = []
	for i in 4:
		var p = int(pos[seat][i])
		if p == FINISH:
			continue
		if p == -1:
			if _can_takeoff(d):
				res.append(i)
		else:
			res.append(i)
	return res


func _opponents_at(seat: int, t: int) -> int:
	if t < 0 or t > LAST_MAIN:
		return 0
	var sq = _square(seat, t)
	var n = 0
	for s in players:
		if s == seat:
			continue
		for k in 4:
			var q = int(pos[s][k])
			if q >= 0 and q <= LAST_MAIN and _square(s, q) == sq:
				n += 1
	return n


func _capture(seat: int, t: int) -> int:
	if t < 0 or t > LAST_MAIN:
		return 0
	var sq = _square(seat, t)
	var n = 0
	for s in players:
		if s == seat:
			continue
		for k in 4:
			var q = int(pos[s][k])
			if q >= 0 and q <= LAST_MAIN and _square(s, q) == sq:
				pos[s][k] = -1
				n += 1
	return n


func _all_finished(seat: int) -> bool:
	for k in 4:
		if int(pos[seat][k]) != FINISH:
			return false
	return true


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if seat != current_seat():
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if t == "roll":
		if phase != "roll":
			return "请先选择要走的飞机"
		dice = randi() % 6 + 1
		movable = _compute_movable(seat, dice)
		if movable.is_empty():
			event = "%s掷出 %d，没有可以走的飞机" % [CNAMES[seat], dice]
			_next_turn(false)
		else:
			phase = "move"
			event = "%s掷出 %d" % [CNAMES[seat], dice]
		return ""
	if t == "move":
		if phase != "move":
			return "请先掷骰子"
		var i = int(a.get("plane", -1))
		if not movable.has(i):
			return "这架飞机不能走"
		_do_move(seat, i, dice)
		if _all_finished(seat):
			finished_order.append(seat)
			event += "，四架飞机全部到达！"
			if finished_order.size() >= players.size() - 1:
				for s in players:
					if not finished_order.has(s):
						finished_order.append(s)
				over = true
				phase = "done"
				movable = []
				return ""
			_next_turn(false)
		else:
			_next_turn(dice == 6)
		return ""
	return "无效操作"


func _do_move(seat: int, i: int, d: int) -> void:
	var p = int(pos[seat][i])
	var t = _target(p, d)
	var parts = []
	if p == -1:
		parts.append("%s起飞了%d号飞机" % [CNAMES[seat], i + 1])
	else:
		parts.append("%s的%d号飞机前进%d步" % [CNAMES[seat], i + 1, d])
		if p + d > FINISH and str(rules.get("over", "bounce")) == "bounce":
			parts.append("超出终点回弹")
	pos[seat][i] = t
	var caps = _capture(seat, t)
	if _jump_applies(p, t):
		t += JUMP
		pos[seat][i] = t
		parts.append("踩到同色格，跳4格")
		caps += _capture(seat, t)
	if caps > 0:
		parts.append("撞回%d架飞机" % caps)
	if t == FINISH:
		parts.append("到达终点")
	event = "，".join(PackedStringArray(parts))


func _next_turn(extra: bool) -> void:
	movable = []
	phase = "roll"
	if extra and six_count < 2:
		six_count += 1
		event += "，掷出6再掷一次"
		return
	six_count = 0
	for k in players.size():
		turn = (turn + 1) % players.size()
		if not finished_order.has(players[turn]):
			return


func get_state() -> Dictionary:
	return {
		"players": players.duplicate(),
		"pos": pos.duplicate(true),
		"current_seat": current_seat(),
		"phase": phase,
		"dice": dice,
		"movable": movable.duplicate(),
		"over": over,
		"winners": finished_order.duplicate(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func bot_action(seat: int) -> Dictionary:
	if phase == "roll":
		return {"type": "roll"}
	if movable.is_empty():
		return {}
	var best = -1.0e9
	var bi = int(movable[0])
	for i in movable:
		var s = _eval_move(seat, int(i), dice) + randf()
		if s > best:
			best = s
			bi = int(i)
	return {"type": "move", "plane": bi}


func _eval_move(seat: int, i: int, d: int) -> float:
	var p = int(pos[seat][i])
	var t = _target(p, d)
	var score = 0.0
	if p == -1:
		score += 40.0
	if t == FINISH:
		score += 100.0
	if p <= LAST_MAIN and t > LAST_MAIN:
		score += 25.0
	score += 60.0 * _opponents_at(seat, t)
	if _jump_applies(p, t):
		score += 10.0
		score += 60.0 * _opponents_at(seat, t + JUMP)
	if p >= 0:
		score += t * 0.5
	return score

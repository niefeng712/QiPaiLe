extends RefCounted
## 中国跳棋（只在房主端运行）：2 / 3 / 4 / 6 人
## 每人从自己的角出发，把全部棋子移到正对面的角。一步可以走到相邻空孔，或连续跳过棋子。
## 进了对面角的棋子不能再出来。对面角被填满、而且里面至少有一颗自己的棋子，就算到达（防止别人堵角）。
## 玩法开关：pieces 10 / 6；jump adjacent 相邻跳 / far 隔空跳；end first 有人到达就结束 / all 排出全部名次

const C = preload("res://games/checkers/CcRules.gd")
const LAYOUT = {2: [0, 3], 3: [0, 2, 4], 4: [0, 1, 3, 4], 6: [0, 1, 2, 3, 4, 5]}
const CNAMES = ["红方", "黄方", "绿方", "蓝方", "紫方", "橙方"]
const MAX_ROUNDS = 220

var rules = {}
var order = []
var home = {}
var occ = []
var pieces = 10
var far = false
var end_mode = "first"
var turn_i = 0
var finished = []
var over = false
var moves = 0
var last_path = []
var last_seat = -1
var ranking = []
var capped = false
var event = ""
var _targets = {}


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func _cname(s: int) -> String:
	return CNAMES[int(home[s])]


func setup(players: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	pieces = 6 if str(rules.get("pieces", "10")) == "6" else 10
	far = str(rules.get("jump", "adjacent")) == "far"
	end_mode = "all" if str(rules.get("end", "first")) == "all" else "first"
	var ps = []
	for p in players:
		ps.append(int(p))
	ps.sort()
	var n = ps.size()
	if not LAYOUT.has(n):
		n = 2
		ps = ps.slice(0, 2)
	var pts = LAYOUT[n]
	home = {}
	order = []
	for i in n:
		home[ps[i]] = int(pts[i])
		order.append(ps[i])
	occ = []
	occ.resize(C.count())
	occ.fill(-1)
	_targets = {}
	for s in order:
		for c in C.zone(int(home[s]), pieces):
			occ[c] = s
		_targets[s] = C.zone((int(home[s]) + 3) % 6, pieces)
	turn_i = (maxi(rn, 1) - 1) % n
	finished = []
	over = false
	moves = 0
	last_path = []
	last_seat = -1
	ranking = []
	capped = false
	event = "游戏开始，%s（%s）先走" % [_lbl(order[turn_i]), _cname(order[turn_i])]


func target_point(s: int) -> int:
	return (int(home[s]) + 3) % 6


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	return int(order[turn_i])


func bot_delay() -> float:
	return 0.6


func _in_target(s: int, i: int) -> bool:
	return C.depth(i, target_point(s)) >= C.min_depth(pieces)


func _done(s: int) -> bool:
	var own = 0
	for c in _targets[s]:
		var v = int(occ[c])
		if v == -1:
			return false
		if v == s:
			own += 1
	return own > 0


func legal_moves(s: int, from: int) -> Dictionary:
	if from < 0 or from >= occ.size() or int(occ[from]) != s:
		return {}
	var r = C.reachable(occ, from, far)
	if _in_target(s, from):
		for d in r.keys():
			if not _in_target(s, int(d)):
				r.erase(d)
	return r


func _my_pieces(s: int) -> Array:
	var out = []
	for i in occ.size():
		if int(occ[i]) == s:
			out.append(i)
	return out


func _has_any_move(s: int) -> bool:
	for p in _my_pieces(s):
		if not legal_moves(s, p).is_empty():
			return true
	return false


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if seat != current_seat():
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if t == "pass":
		if _has_any_move(seat):
			return "还有棋可以走"
		event = "%s 无棋可走，跳过" % _lbl(seat)
		_next()
		return ""
	if t != "move":
		return "无效操作"
	var from = int(a.get("from", -1))
	var to = int(a.get("to", -1))
	if from < 0 or from >= occ.size() or int(occ[from]) != seat:
		return "请选择你自己的棋子"
	var lm = legal_moves(seat, from)
	if not lm.has(to):
		if _in_target(seat, from) and C.reachable(occ, from, far).has(to):
			return "已经进了终点的棋子不能再出来"
		return "这颗棋子走不到那里"
	occ[from] = -1
	occ[to] = seat
	last_path = lm[to].duplicate()
	last_seat = seat
	moves += 1
	var hops = last_path.size() - 1
	if hops >= 2:
		event = "%s 连跳%d次" % [_lbl(seat), hops]
	elif _adjacent(from, to):
		event = "%s 走了一步" % _lbl(seat)
	else:
		event = "%s 跳了一步" % _lbl(seat)
	if _done(seat):
		finished.append(seat)
		event += "，全部到达！第%d名" % finished.size()
		if end_mode == "first" or finished.size() >= order.size() - 1:
			_finish(false)
			return ""
	if moves >= MAX_ROUNDS * order.size():
		_finish(true)
		return ""
	_next()
	return ""


func _adjacent(a: int, b: int) -> bool:
	for d in 6:
		if C.nbr(a, d) == b:
			return true
	return false


func _next() -> void:
	for k in order.size():
		turn_i = (turn_i + 1) % order.size()
		if not finished.has(order[turn_i]):
			return


func remaining(s: int) -> int:
	var tp = target_point(s)
	var md = C.min_depth(pieces)
	var tot = 0
	for p in _my_pieces(s):
		tot += maxi(0, md - C.depth(p, tp))
	return tot


func in_target_count(s: int) -> int:
	var n = 0
	for p in _my_pieces(s):
		if _in_target(s, p):
			n += 1
	return n


func _finish(cap: bool) -> void:
	over = true
	capped = cap
	ranking = finished.duplicate()
	var rest = []
	for s in order:
		if not ranking.has(s):
			rest.append([in_target_count(s) * -1000 + remaining(s), s])
	rest.sort_custom(func(a, b): return a[0] < b[0])
	for r in rest:
		ranking.append(int(r[1]))
	if cap:
		event = "已走满%d轮，按离终点的远近排名" % MAX_ROUNDS
	var w = int(ranking[0])
	event += "。%s（%s）获胜！" % [_lbl(w), _cname(w)]


func get_state() -> Dictionary:
	var hm = {}
	var prog = {}
	for s in order:
		hm[str(s)] = int(home[s])
		prog[str(s)] = in_target_count(s)
	return {
		"occ": occ.duplicate(),
		"order": order.duplicate(),
		"home": hm,
		"progress": prog,
		"pieces": pieces,
		"far": far,
		"current_seat": current_seat(),
		"last_path": last_path.duplicate(),
		"last_seat": last_seat,
		"finished": finished.duplicate(),
		"moves": moves,
		"rounds": moves / maxi(order.size(), 1),
		"max_rounds": MAX_ROUNDS,
		"over": over,
		"winners": [int(ranking[0])] if over and not ranking.is_empty() else [],
		"ranking": ranking.duplicate(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func _piece_value(s: int, i: int) -> float:
	var tp = target_point(s)
	var d = C.depth(i, tp)
	var v = d * 10.0
	if not _in_target(s, i):
		v -= C.lateral(i, tp) * 1.5
	return v


func _total(s: int) -> float:
	var tp = target_point(s)
	var tot = 0.0
	var mn = 99
	for p in _my_pieces(s):
		tot += _piece_value(s, p)
		mn = mini(mn, C.depth(p, tp))
	return tot + mn * 4.0


func _all_moves(s: int) -> Array:
	var out = []
	for p in _my_pieces(s):
		var lm = legal_moves(s, p)
		for d in lm:
			out.append([p, int(d)])
	return out


func _best_followup(s: int) -> float:
	var base = _total(s)
	var best = 0.0
	for p in _my_pieces(s):
		var lm = legal_moves(s, p)
		for d in lm:
			occ[p] = -1
			occ[int(d)] = s
			best = maxf(best, _total(s) - base)
			occ[int(d)] = -1
			occ[p] = s
	return best


func bot_action(s: int) -> Dictionary:
	if over:
		return {}
	var mv = _all_moves(s)
	if mv.is_empty():
		return {"type": "pass"}
	var base = _total(s)
	var scored = []
	for m in mv:
		var f = int(m[0])
		var t = int(m[1])
		occ[f] = -1
		occ[t] = s
		var g = _total(s) - base
		if _done(s):
			g += 100000.0
		occ[t] = -1
		occ[f] = s
		scored.append([g + randf() * 0.6, f, t])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var best = scored[0]
	var bv = -1.0e9
	for k in mini(8, scored.size()):
		var it = scored[k]
		var f2 = int(it[1])
		var t2 = int(it[2])
		occ[f2] = -1
		occ[t2] = s
		var v = float(it[0]) + 0.6 * _best_followup(s)
		occ[t2] = -1
		occ[f2] = s
		if v > bv:
			bv = v
			best = it
	return {"type": "move", "from": int(best[1]), "to": int(best[2])}

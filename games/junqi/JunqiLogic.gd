extends RefCounted
## 军棋（只在房主端运行）
##   四国军棋：4人，座位1、3 一伙，座位2、4 一伙；两国军棋：2人
## 流程：布阵（可以交换自己两个棋子的位置，点「布阵完成」）→ 轮流走棋
## 规则：大子吃小子，同级同归于尽；炸弹和任何棋子同归于尽；工兵能挖地雷，其他棋子碰到地雷阵亡；
##       行营里的棋子不能被攻击；大本营里的棋子不能动；司令阵亡后亮出他的军旗；
##       军旗被扛走或者无棋可走就出局，出局的棋子全部拿掉；一方全部出局就输
## 玩法开关：view dark 暗棋（只看到自己的）/ team 能看到队友的 / open 明棋

const B = preload("res://games/junqi/JqBoard.gd")
const VALUE = [0, 100, 80, 60, 45, 35, 25, 15, 10, 20, 50, 15, 1000]
const WIN_P = [0, 0.92, 0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25, 0.12, 1.0, 0.0, 0.0]
const COLORS_NAME = ["红", "黄", "绿", "蓝"]

var rules = {}
var board = null
var n = 4
var seats = []
var occ = []
var code = []
var moved = []
var strong = []
var phase = "deploy"
var ready = []
var alive = []
var flag_shown = []
var turn = 0
var plies = 0
var max_plies = 1200
var last_path = []
var last_fight = {}
var over = false
var win_team = -1
var view = "dark"
var event = ""
var out_order = []


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func team(s: int) -> int:
	return s % 2


func is_enemy(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and team(a) != team(b) and bool(alive[b])


func setup(players: Array, game_rules: Dictionary, _rn: int) -> void:
	rules = game_rules.duplicate(true)
	n = 2 if str(rules.get("board", "4")) == "2" else 4
	board = B.new(n)
	view = str(rules.get("view", "dark"))
	max_plies = 1200 if n == 4 else 600
	seats = []
	for s in n:
		seats.append(s)
	occ = []
	code = []
	moved = []
	strong = []
	for i in board.count():
		occ.append(-1)
		code.append(0)
		moved.append(false)
		strong.append(false)
	for s in n:
		var lay = board.random_layout(s)
		for i in lay:
			occ[int(i)] = s
			code[int(i)] = int(lay[i])
	ready = []
	alive = []
	flag_shown = []
	for s in n:
		ready.append(false)
		alive.append(true)
		flag_shown.append(false)
	phase = "deploy"
	turn = 0
	plies = 0
	last_path = []
	last_fight = {}
	over = false
	win_team = -1
	out_order = []
	event = "布阵：点自己的两个棋子可以交换位置，摆好后点「布阵完成」"


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	if phase == "deploy":
		for s in n:
			if not bool(ready[s]):
				return s
		return -1
	return turn


func bot_delay() -> float:
	return 0.2 if phase == "deploy" else 0.7


# ---------------------------------------------------------------- 操作

func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if seat < 0 or seat >= n:
		return "你不在对局中"
	var t = str(a.get("type", ""))
	if phase == "deploy":
		if bool(ready[seat]):
			return "你已经布阵完成，等其他人"
		if t == "swap":
			return _swap(seat, int(a.get("a", -1)), int(a.get("b", -1)))
		if t == "ready":
			ready[seat] = true
			event = "%s 布阵完成" % _lbl(seat)
			var all_ready = true
			for s in n:
				if not bool(ready[s]):
					all_ready = false
			if all_ready:
				phase = "play"
				turn = 0
				event = "全部布阵完成，%s先走" % _lbl(turn)
				_skip_stuck()
			return ""
		return "现在是布阵阶段"
	if seat != turn:
		return "还没轮到你"
	if t == "move":
		return _move(seat, int(a.get("from", -1)), int(a.get("to", -1)))
	if t == "pass":
		if _has_move(seat):
			return "你还有棋可以走"
		_eliminate(seat, "无棋可走")
		_next_turn()
		return ""
	if t == "resign":
		_eliminate(seat, "认输")
		_next_turn()
		return ""
	return "无效操作"


func _swap(s: int, i: int, j: int) -> String:
	if i < 0 or j < 0 or i >= occ.size() or j >= occ.size() or int(occ[i]) != s or int(occ[j]) != s:
		return "只能交换自己的棋子"
	var ci = int(code[i])
	var cj = int(code[j])
	if not board.slot_ok(j, ci) or not board.slot_ok(i, cj):
		var why = "军旗只能放在大本营；地雷只能放在最后两排；炸弹不能放在第一排"
		return "不能这样换：" + why
	code[i] = cj
	code[j] = ci
	return ""


func _has_move(s: int) -> bool:
	for i in occ.size():
		if int(occ[i]) == s and not board.destinations(occ, i, int(code[i]), func(o): return is_enemy(s, o)).is_empty():
			return true
	return false


func legal_moves(s: int) -> Array:
	var out = []
	for i in occ.size():
		if int(occ[i]) != s:
			continue
		var d = board.destinations(occ, i, int(code[i]), func(o): return is_enemy(s, o))
		for j in d:
			out.append([i, int(j), d[j]])
	return out


func _move(s: int, f: int, t: int) -> String:
	if f < 0 or f >= occ.size() or int(occ[f]) != s:
		return "请选择自己的棋子"
	var c = int(code[f])
	if c == B.MINE or c == B.FLAG:
		return "地雷和军旗不能移动"
	if board.hq[f]:
		return "大本营里的棋子不能再动"
	var d = board.destinations(occ, f, c, func(o): return is_enemy(s, o))
	if not d.has(t):
		return "走不到那里（铁路只能直走，只有工兵能拐弯）"
	last_path = d[t].duplicate()
	plies += 1
	moved[f] = false
	if int(occ[t]) == -1:
		occ[t] = s
		code[t] = c
		moved[t] = true
		strong[t] = strong[f]
		occ[f] = -1
		code[f] = 0
		strong[f] = false
		last_fight = {}
		event = "%s 走了一步" % _lbl(s)
	else:
		var o = int(occ[t])
		var dc = int(code[t])
		var res = B.fight(c, dc)
		last_fight = {"att": s, "def": o, "res": res, "at": t}
		occ[f] = -1
		code[f] = 0
		strong[f] = false
		if res == "att":
			occ[t] = s
			code[t] = c
			moved[t] = true
			strong[t] = true
			event = "%s 进攻 %s：进攻方胜" % [_lbl(s), _lbl(o)]
		elif res == "def":
			strong[t] = true
			event = "%s 进攻 %s：进攻方阵亡" % [_lbl(s), _lbl(o)]
			if dc == B.MINE:
				event += "（踩到地雷）"
		else:
			occ[t] = -1
			code[t] = 0
			strong[t] = false
			event = "%s 进攻 %s：同归于尽" % [_lbl(s), _lbl(o)]
		if res != "att" and c == 1:
			_show_flag(s)
		if res != "def" and dc == 1:
			_show_flag(o)
		if dc == B.FLAG and res == "att":
			_eliminate(o, "军旗被扛")
			event = "%s 扛走了 %s 的军旗！" % [_lbl(s), _lbl(o)]
	if not over:
		_check_cap()
	if not over:
		_next_turn()
	return ""


func _show_flag(s: int) -> void:
	if not bool(flag_shown[s]):
		flag_shown[s] = true
		event += "。%s 的司令阵亡，亮出军旗" % _lbl(s)


func _eliminate(s: int, why: String) -> void:
	if not bool(alive[s]):
		return
	alive[s] = false
	out_order.append(s)
	for i in occ.size():
		if int(occ[i]) == s:
			occ[i] = -1
			code[i] = 0
	event += "。%s %s，出局" % [_lbl(s), why]
	var tm = team(s)
	var team_alive = false
	for o in n:
		if team(o) == tm and bool(alive[o]):
			team_alive = true
	if not team_alive:
		over = true
		win_team = 1 - tm
		phase = "done"
		event += "。%s 获胜！" % ("座位1、3" if win_team == 0 and n == 4 else ("座位2、4" if n == 4 else _lbl(win_team)))


func _check_cap() -> void:
	if plies < max_plies:
		return
	var tot = [0, 0]
	for i in occ.size():
		var o = int(occ[i])
		if o >= 0:
			tot[team(o)] += VALUE[int(code[i])] if int(code[i]) != B.FLAG else 0
	over = true
	phase = "done"
	if tot[0] == tot[1]:
		win_team = -1
		event += "。已走满%d步，双方兵力相当，和棋" % max_plies
	else:
		win_team = 0 if tot[0] > tot[1] else 1
		event += "。已走满%d步，按剩余兵力判%s获胜" % [max_plies, "座位1、3" if win_team == 0 and n == 4 else ("座位2、4" if n == 4 else _lbl(win_team))]


func _next_turn() -> void:
	if over:
		return
	for k in n:
		turn = (turn + 1) % n
		if bool(alive[turn]):
			break
	_skip_stuck()


func _skip_stuck() -> void:
	for guard in n:
		if over or not bool(alive[turn]) or _has_move(turn):
			return
		_eliminate(turn, "无棋可走")
		if over:
			return
		for k in n:
			turn = (turn + 1) % n
			if bool(alive[turn]):
				break


func winners() -> Array:
	var out = []
	if win_team >= 0:
		for s in n:
			if team(s) == win_team:
				out.append(s)
	return out


# ---------------------------------------------------------------- 状态

func _visible(viewer: int, i: int) -> bool:
	var o = int(occ[i])
	if o < 0:
		return false
	if over or view == "open" or o == viewer:
		return true
	if view == "team" and viewer >= 0 and team(viewer) == team(o):
		return true
	if int(code[i]) == B.FLAG and bool(flag_shown[o]):
		return true
	return false


func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(viewer: int) -> Dictionary:
	var vis = []
	for i in occ.size():
		vis.append(int(code[i]) if _visible(viewer, i) else (0 if int(occ[i]) < 0 else -1))
	return {
		"n": n,
		"phase": phase,
		"current_seat": current_seat() if phase != "deploy" else -1,
		"turn": turn,
		"occ": occ.duplicate(),
		"code": vis,
		"ready": ready.duplicate(),
		"alive": alive.duplicate(),
		"flag_shown": flag_shown.duplicate(),
		"last_path": last_path.duplicate(),
		"last_fight": last_fight.duplicate(),
		"plies": plies,
		"max_plies": max_plies,
		"view": view,
		"over": over,
		"winners": winners(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI

func _enemy_hqs(s: int) -> Array:
	var out = []
	for i in occ.size():
		var a = int(board.army[i])
		if a >= 0 and is_enemy(s, a) and board.hq[i]:
			out.append(i)
	return out


func _dist(i: int, targets: Array) -> float:
	var best = 999.0
	var p: Vector2i = board.pos[i]
	for t in targets:
		var q: Vector2i = board.pos[int(t)]
		best = minf(best, absi(p.x - q.x) + absi(p.y - q.y))
	return best


func _guess(t: int) -> Dictionary:
	## 估计一个看不见的敌方棋子：可能是地雷 / 军旗的概率、估计价值
	var o = int(occ[t])
	var a = int(board.army[t])
	var r = board.local[t].x if a == o else 0
	var mine_p = 0.0
	var flag_p = 0.0
	if not bool(moved[t]):
		if board.hq[t] and a == o:
			flag_p = 0.0 if bool(flag_shown[o]) else 0.5
			mine_p = 0.3
		elif r >= 4 and a == o:
			mine_p = 0.35
	var val = 70.0 if bool(strong[t]) else 30.0
	return {"mine": mine_p, "flag": flag_p, "val": val}


func bot_action(s: int) -> Dictionary:
	if over:
		return {}
	if phase == "deploy":
		return {"type": "ready"}
	var moves = legal_moves(s)
	if moves.is_empty():
		return {"type": "pass"}
	var hqs = _enemy_hqs(s)
	var best = null
	var bv = -1.0e9
	for m in moves:
		var f = int(m[0])
		var t = int(m[1])
		var c = int(code[f])
		var sc = (_dist(f, hqs) - _dist(t, hqs)) * 2.0 + randf() * 3.0
		if board.camp[t]:
			sc += 3.0
		if int(occ[t]) >= 0:
			var o = int(occ[t])
			var known = _visible(s, t)
			var dc = int(code[t])
			if known:
				var res = B.fight(c, dc)
				if res == "att":
					sc += VALUE[dc] + (2000.0 if dc == B.FLAG else 0.0)
				elif res == "both":
					sc += VALUE[dc] - VALUE[c]
				else:
					sc -= VALUE[c]
			else:
				var g = _guess(t)
				var mp = float(g["mine"])
				var fp = float(g["flag"])
				var other = maxf(0.0, 1.0 - mp - fp)
				var gain = fp * 2000.0
				if c == B.BOMB:
					gain += mp * (15.0 - VALUE[c]) + other * (float(g["val"]) - VALUE[c])
					if not bool(strong[t]):
						gain -= 25.0
				elif c == B.ENGINEER:
					gain += mp * 15.0 + other * (WIN_P[c] * float(g["val"]) - (1.0 - WIN_P[c]) * VALUE[c])
				else:
					var wp = WIN_P[c]
					if bool(strong[t]):
						wp *= 0.6
					gain += -mp * VALUE[c] + other * (wp * float(g["val"]) - (1.0 - wp) * VALUE[c])
				sc += gain
		if c <= 2 and int(occ[t]) < 0:
			sc -= 1.0
		if sc > bv:
			bv = sc
			best = m
	return {"type": "move", "from": int(best[0]), "to": int(best[1])}

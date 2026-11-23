extends RefCounted
## 连连看（只在房主端运行）：每人一盘一样的牌，同时开始
## 两张相同的牌，能用不超过两个拐弯的线连起来（线可以走棋盘外面一圈）就能消掉
## 单人：限时内全部消完就赢；多人：比谁先消完，时间到了比谁消得多
## 没有能消的牌时自动重排；每人可以用「提示」和「重排」各几次

const KINDS = ["福", "禄", "寿", "喜", "财", "吉", "祥", "如", "意", "春", "夏", "秋", "冬", "梅", "兰", "竹", "菊", "龙", "凤", "虎", "鹤", "鹿", "松", "日", "月", "星", "云", "山"]
const SIZES = {"small": [10, 6], "normal": [14, 8], "large": [16, 9]}
const BOT_SPEED = {"easy": [4.0, 7.0], "normal": [2.5, 4.5], "hard": [1.4, 2.6]}

var rules = {}
var W = 14
var H = 8
var players = []
var boards = {}
var scores = {}
var hints = {}
var shuffles = {}
var last = {}
var done = []
var time_left = 300.0
var over = false
var winners_list = []
var event = ""
var bot_cd = {}
var bot_speed = [2.5, 4.5]
var _sync = 0.0
var hint_pair = {}


func setup(seat_list: Array, game_rules: Dictionary, _rn: int) -> void:
	rules = game_rules.duplicate(true)
	var sz = SIZES.get(str(rules.get("size", "normal")), SIZES["normal"])
	W = int(sz[0])
	H = int(sz[1])
	var tl = str(rules.get("time", "300"))
	time_left = float(int(tl)) if tl.is_valid_int() else 300.0
	bot_speed = BOT_SPEED.get(str(rules.get("level", "normal")), BOT_SPEED["normal"])
	players = []
	for s in seat_list:
		players.append(int(s))
	var base = _new_board()
	boards = {}
	scores = {}
	hints = {}
	shuffles = {}
	last = {}
	bot_cd = {}
	for s in players:
		boards[s] = base.duplicate()
		scores[s] = 0
		hints[s] = 3
		shuffles[s] = 2
		last[s] = []
		bot_cd[s] = randf_range(float(bot_speed[0]), float(bot_speed[1])) + 1.0
	done = []
	over = false
	winners_list = []
	_sync = 0.0
	hint_pair = {}
	event = "开始！%d秒内消完全部%d张牌" % [int(time_left), W * H] if players.size() == 1 else "开始！比谁先消完%d张牌" % (W * H)


func _gw() -> int:
	return W + 2


func _gh() -> int:
	return H + 2


func _new_board() -> Array:
	var tiles = []
	var pairs = W * H / 2
	var kinds = mini(KINDS.size(), maxi(pairs / 2, 1))
	for k in pairs:
		var t = k % kinds
		tiles.append(t)
		tiles.append(t)
	var b = []
	b.resize(_gw() * _gh())
	b.fill(-1)
	for guard in 50:
		tiles.shuffle()
		var k = 0
		for y in H:
			for x in W:
				b[(y + 1) * _gw() + x + 1] = tiles[k]
				k += 1
		if not find_pair(b).is_empty():
			break
	return b


func is_over() -> bool:
	return over


func current_seat() -> int:
	return -1


func bot_delay() -> float:
	return 1.0


# ---------------------------------------------------------------- 连线

## 两个格子能否用不超过两个拐弯的线连起来，返回路径上的拐点（含两端），连不上返回 []
func connect_path(b: Array, a: int, c: int) -> Array:
	if a == c or int(b[a]) < 0 or int(b[a]) != int(b[c]):
		return []
	var gw = _gw()
	var gh = _gh()
	var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var start = Vector2i(a % gw, a / gw)
	var goal = Vector2i(c % gw, c / gw)
	# best[cell*4+dir] = 最少拐弯数
	var best = {}
	var queue = []
	for d in 4:
		queue.append([start, d, 0, [start]])
	while not queue.is_empty():
		var it = queue.pop_front()
		var p: Vector2i = it[0]
		var d2 = int(it[1])
		var turns = int(it[2])
		var pts: Array = it[3]
		var np = p + dirs[d2]
		if np.x < 0 or np.y < 0 or np.x >= gw or np.y >= gh:
			continue
		var idx = np.y * gw + np.x
		if np == goal:
			var out = pts.duplicate()
			out.append(np)
			return out
		if int(b[idx]) != -1:
			continue
		var key = idx * 4 + d2
		if best.has(key) and int(best[key]) <= turns:
			continue
		best[key] = turns
		for nd in 4:
			if nd == d2:
				queue.push_front([np, nd, turns, pts])
			elif turns < 2 and dirs[nd] != -dirs[d2]:
				var npts = pts.duplicate()
				npts.append(np)
				queue.append([np, nd, turns + 1, npts])
	return []


func find_pair(b: Array) -> Array:
	var by_kind = {}
	for i in b.size():
		var k = int(b[i])
		if k >= 0:
			if not by_kind.has(k):
				by_kind[k] = []
			by_kind[k].append(i)
	var ks = by_kind.keys()
	ks.shuffle()
	for k in ks:
		var arr = by_kind[k]
		for i in arr.size():
			for j in range(i + 1, arr.size()):
				if not connect_path(b, int(arr[i]), int(arr[j])).is_empty():
					return [int(arr[i]), int(arr[j])]
	return []


func _left(s: int) -> int:
	var n = 0
	for v in boards[s]:
		if int(v) >= 0:
			n += 1
	return n


func _reshuffle(s: int) -> void:
	var b = boards[s]
	var cells = []
	var vals = []
	for i in b.size():
		if int(b[i]) >= 0:
			cells.append(i)
			vals.append(int(b[i]))
	for guard in 60:
		vals.shuffle()
		for k in cells.size():
			b[cells[k]] = vals[k]
		if cells.is_empty() or not find_pair(b).is_empty():
			return


# ---------------------------------------------------------------- 操作

func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if not boards.has(seat):
		return "你不在这局游戏里"
	if done.has(seat):
		return "你已经消完了"
	var t = str(a.get("type", ""))
	var b = boards[seat]
	if t == "pick":
		var i = int(a.get("a", -1))
		var j = int(a.get("b", -1))
		if i < 0 or j < 0 or i >= b.size() or j >= b.size():
			return "位置无效"
		if int(b[i]) < 0 or int(b[i]) != int(b[j]):
			return "两张牌不一样"
		var path = connect_path(b, i, j)
		if path.is_empty():
			return "连不上（最多拐两个弯）"
		b[i] = -1
		b[j] = -1
		hint_pair.erase(seat)
		var cells = []
		for p in path:
			cells.append(p.y * _gw() + p.x)
		last[seat] = cells
		scores[seat] = int(scores[seat]) + 10
		if _left(seat) == 0:
			done.append(seat)
			scores[seat] = int(scores[seat]) + int(time_left)
			event = "%s 全部消完！" % _lbl(seat)
			_finish()
		elif find_pair(b).is_empty():
			_reshuffle(seat)
			if seat == players[0] or players.size() == 1:
				event = "没有能消的牌了，自动重排"
		return ""
	if t == "hint":
		if int(hints[seat]) <= 0:
			return "提示用完了"
		hints[seat] = int(hints[seat]) - 1
		hint_pair[seat] = find_pair(b)
		return ""
	if t == "shuffle":
		if int(shuffles[seat]) <= 0:
			return "重排用完了"
		shuffles[seat] = int(shuffles[seat]) - 1
		_reshuffle(seat)
		hint_pair.erase(seat)
		return ""
	return "无效操作"


func tick(dt: float) -> bool:
	if over:
		return false
	time_left -= dt
	for s in bot_cd:
		bot_cd[s] = float(bot_cd[s]) - dt
	if time_left <= 0.0:
		time_left = 0.0
		event = "时间到！"
		_finish()
		return true
	_sync += dt
	if _sync >= 5.0:
		_sync = 0.0
		return true
	return false


func bot_action(s: int) -> Dictionary:
	if over or not boards.has(s) or done.has(s) or float(bot_cd.get(s, 1.0)) > 0.0:
		return {}
	bot_cd[s] = randf_range(float(bot_speed[0]), float(bot_speed[1]))
	var p = find_pair(boards[s])
	if p.is_empty():
		return {"type": "shuffle"} if int(shuffles[s]) > 0 else {}
	return {"type": "pick", "a": int(p[0]), "b": int(p[1])}


func _finish() -> void:
	over = true
	if players.size() == 1:
		var s = int(players[0])
		if done.has(s):
			winners_list = [s]
			event += "得分 %d" % int(scores[s])
		else:
			winners_list = []
			event += "还剩 %d 张没消，挑战失败" % _left(s)
		return
	if not done.is_empty():
		winners_list = [int(done[0])]
	else:
		var best = -1
		for s in players:
			var v = W * H - _left(int(s))
			if v > best:
				best = v
				winners_list = [int(s)]
			elif v == best:
				winners_list.append(int(s))
		event += "按消掉的数量排名"


func winners() -> Array:
	return winners_list.duplicate()


func get_state() -> Dictionary:
	return get_state_for(-1)


func get_state_for(v: int) -> Dictionary:
	var me = v if boards.has(v) else (int(players[0]) if not players.is_empty() else -1)
	var others = []
	for s in players:
		others.append({"seat": int(s), "left": _left(int(s)), "score": int(scores[s]), "done": done.has(int(s))})
	return {
		"hint": hint_pair.get(me, []).duplicate(),
		"w": W,
		"h": H,
		"board": boards[me].duplicate() if me >= 0 else [],
		"me": me,
		"playing": boards.has(v),
		"score": int(scores.get(me, 0)),
		"hints": int(hints.get(me, 0)),
		"shuffles": int(shuffles.get(me, 0)),
		"last": last.get(me, []).duplicate(),
		"players": others,
		"time_left": time_left,
		"current_seat": -1,
		"over": over,
		"winners": winners_list.duplicate(),
		"event": event,
	}

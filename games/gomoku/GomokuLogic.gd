extends RefCounted
## 五子棋规则（只在房主端运行）。无禁手：任意方向连成5子及以上即获胜。

const SIZE = 15
const DIRS = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]

var board = []
var black_seat = 0
var white_seat = 1
var turn_color = 0  # 0 = 黑, 1 = 白
var winner_color = -1
var draw = false
var last_move = []
var win_line = []
var moves = 0


func setup(players: Array, rules: Dictionary, round_no: int) -> void:
	board = []
	board.resize(SIZE * SIZE)
	board.fill(-1)
	var a = int(players[0])
	var b = int(players[1])
	var first = str(rules.get("first", "alternate"))
	var swap = false
	if first == "random":
		swap = randi() % 2 == 1
	elif first == "alternate":
		swap = round_no % 2 == 0
	if swap:
		black_seat = b
		white_seat = a
	else:
		black_seat = a
		white_seat = b
	turn_color = 0
	winner_color = -1
	draw = false
	last_move = []
	win_line = []
	moves = 0


func is_over() -> bool:
	return winner_color != -1 or draw


func current_seat() -> int:
	if is_over():
		return -1
	return black_seat if turn_color == 0 else white_seat


func bot_delay() -> float:
	return 0.5


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE


func _at(x: int, y: int) -> int:
	return int(board[y * SIZE + x])


func _is_empty(x: int, y: int) -> bool:
	return _in(x, y) and _at(x, y) == -1


func apply(seat: int, a: Dictionary) -> String:
	if is_over():
		return "本局已结束"
	if seat != current_seat():
		return "还没轮到你"
	if str(a.get("type", "")) != "place":
		return "无效操作"
	var x = int(a.get("x", -1))
	var y = int(a.get("y", -1))
	if not _in(x, y):
		return "位置无效"
	if _at(x, y) != -1:
		return "这里已经有棋子了"
	board[y * SIZE + x] = turn_color
	moves += 1
	last_move = [x, y]
	var line = _five_line(x, y, turn_color)
	if not line.is_empty():
		winner_color = turn_color
		win_line = line
	elif moves >= SIZE * SIZE:
		draw = true
	else:
		turn_color = 1 - turn_color
	return ""


func _count_dir(x: int, y: int, dx: int, dy: int, c: int) -> int:
	var n = 0
	var cx = x + dx
	var cy = y + dy
	while _in(cx, cy) and _at(cx, cy) == c:
		n += 1
		cx += dx
		cy += dy
	return n


func _five_line(x: int, y: int, c: int) -> Array:
	for d in DIRS:
		var f = _count_dir(x, y, d.x, d.y, c)
		var b = _count_dir(x, y, -d.x, -d.y, c)
		if f + b + 1 >= 5:
			return [x - d.x * b, y - d.y * b, x + d.x * f, y + d.y * f]
	return []


func get_state() -> Dictionary:
	var winners = []
	if winner_color == 0:
		winners = [black_seat]
	elif winner_color == 1:
		winners = [white_seat]
	return {
		"board": board.duplicate(),
		"size": SIZE,
		"black_seat": black_seat,
		"white_seat": white_seat,
		"current_seat": current_seat(),
		"last": last_move.duplicate(),
		"win_line": win_line.duplicate(),
		"over": is_over(),
		"draw": draw,
		"winners": winners,
		"moves": moves,
	}


# ---------------------------------------------------------------- 电脑 AI（棋型打分）

func bot_action(seat: int) -> Dictionary:
	var me = 0 if seat == black_seat else 1
	if moves == 0:
		return {"type": "place", "x": SIZE / 2, "y": SIZE / 2}
	var best = -1.0
	var bx = -1
	var by = -1
	for y in SIZE:
		for x in SIZE:
			if _at(x, y) != -1 or not _has_neighbor(x, y, 2):
				continue
			var att = _score_point(x, y, me)
			var de = _score_point(x, y, 1 - me)
			var s = att * 1.1 + de + randf() * 0.5
			if s > best:
				best = s
				bx = x
				by = y
	if bx == -1:
		for i in SIZE * SIZE:
			if int(board[i]) == -1:
				return {"type": "place", "x": i % SIZE, "y": i / SIZE}
		return {}
	return {"type": "place", "x": bx, "y": by}


func _has_neighbor(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			var nx = x + dx
			var ny = y + dy
			if _in(nx, ny) and _at(nx, ny) != -1:
				return true
	return false


func _score_point(x: int, y: int, c: int) -> float:
	var total = 0.0
	for d in DIRS:
		var f = _count_dir(x, y, d.x, d.y, c)
		var b = _count_dir(x, y, -d.x, -d.y, c)
		var n = f + b + 1
		var open_ends = 0
		if _is_empty(x + d.x * (f + 1), y + d.y * (f + 1)):
			open_ends += 1
		if _is_empty(x - d.x * (b + 1), y - d.y * (b + 1)):
			open_ends += 1
		total += _pattern_score(n, open_ends)
	return total


func _pattern_score(n: int, open_ends: int) -> float:
	if n >= 5:
		return 100000.0
	if open_ends == 0:
		return 0.0
	if n == 4:
		return 10000.0 if open_ends == 2 else 1200.0
	if n == 3:
		return 1000.0 if open_ends == 2 else 120.0
	if n == 2:
		return 100.0 if open_ends == 2 else 12.0
	return 2.0 if open_ends == 2 else 1.0

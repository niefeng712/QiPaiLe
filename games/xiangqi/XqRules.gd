extends RefCounted
## 中国象棋规则（静态函数：房主端判定、电脑AI、界面共用）
## 棋盘 9 列 × 10 行，下标 = y*9 + x；黑方在上（y=0..4），红方在下（y=5..9）
## 棋子：0 空；红方正数、黑方负数；1帅/将 2仕/士 3相/象 4马 5车 6炮 7兵/卒

const RED_CH = ["", "帅", "仕", "相", "马", "车", "炮", "兵"]
const BLK_CH = ["", "将", "士", "象", "马", "车", "炮", "卒"]
const VAL = [0, 20000, 200, 200, 400, 900, 450, 100]
const ORTHO = [[1, 0], [-1, 0], [0, 1], [0, -1]]
const DIAG = [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const KNIGHT = [[1, 2, 0, 1], [-1, 2, 0, 1], [1, -2, 0, -1], [-1, -2, 0, -1], [2, 1, 1, 0], [2, -1, 1, 0], [-2, 1, -1, 0], [-2, -1, -1, 0]]

static var nodes = 0
static var budget = 0


static func initial() -> Array:
	var b = []
	b.resize(90)
	b.fill(0)
	var back = [5, 4, 3, 2, 1, 2, 3, 4, 5]
	for x in 9:
		b[x] = -back[x]
		b[81 + x] = back[x]
	b[19] = -6
	b[25] = -6
	b[64] = 6
	b[70] = 6
	for x in [0, 2, 4, 6, 8]:
		b[27 + x] = -7
		b[54 + x] = 7
	return b


static func piece_name(p: int) -> String:
	if p > 0:
		return RED_CH[p]
	if p < 0:
		return BLK_CH[-p]
	return ""


static func _own(b: Array, i: int, sg: int) -> bool:
	var p = int(b[i])
	return p != 0 and (p > 0) == (sg > 0)


static func _palace(x: int, y: int, sg: int) -> bool:
	if x < 3 or x > 5:
		return false
	if sg > 0:
		return y >= 7 and y <= 9
	return y >= 0 and y <= 2


static func _add(b: Array, i: int, x: int, y: int, sg: int, out: Array) -> void:
	if x < 0 or x > 8 or y < 0 or y > 9:
		return
	var j = y * 9 + x
	if not _own(b, j, sg):
		out.append([i, j])


static func gen_piece(b: Array, i: int, sg: int, out: Array) -> void:
	var t = absi(int(b[i]))
	var x = i % 9
	var y = i / 9
	match t:
		1:
			for d in ORTHO:
				var nx = x + d[0]
				var ny = y + d[1]
				if _palace(nx, ny, sg) and not _own(b, ny * 9 + nx, sg):
					out.append([i, ny * 9 + nx])
			var dy = -1 if sg > 0 else 1
			var ny2 = y + dy
			while ny2 >= 0 and ny2 <= 9:
				var q = int(b[ny2 * 9 + x])
				if q != 0:
					if q == -sg:
						out.append([i, ny2 * 9 + x])
					break
				ny2 += dy
		2:
			for d in DIAG:
				var nx = x + d[0]
				var ny = y + d[1]
				if _palace(nx, ny, sg) and not _own(b, ny * 9 + nx, sg):
					out.append([i, ny * 9 + nx])
		3:
			for d in DIAG:
				var nx = x + 2 * d[0]
				var ny = y + 2 * d[1]
				if nx < 0 or nx > 8 or ny < 0 or ny > 9:
					continue
				if (sg > 0 and ny < 5) or (sg < 0 and ny > 4):
					continue
				if int(b[(y + d[1]) * 9 + x + d[0]]) != 0:
					continue
				_add(b, i, nx, ny, sg, out)
		4:
			for k in KNIGHT:
				var nx = x + k[0]
				var ny = y + k[1]
				if nx < 0 or nx > 8 or ny < 0 or ny > 9:
					continue
				if int(b[(y + k[3]) * 9 + x + k[2]]) != 0:
					continue
				_add(b, i, nx, ny, sg, out)
		5:
			for d in ORTHO:
				var nx = x + d[0]
				var ny = y + d[1]
				while nx >= 0 and nx <= 8 and ny >= 0 and ny <= 9:
					var j = ny * 9 + nx
					var q = int(b[j])
					if q == 0:
						out.append([i, j])
					else:
						if (q > 0) != (sg > 0):
							out.append([i, j])
						break
					nx += d[0]
					ny += d[1]
		6:
			for d in ORTHO:
				var nx = x + d[0]
				var ny = y + d[1]
				var screen = false
				while nx >= 0 and nx <= 8 and ny >= 0 and ny <= 9:
					var j = ny * 9 + nx
					var q = int(b[j])
					if not screen:
						if q == 0:
							out.append([i, j])
						else:
							screen = true
					elif q != 0:
						if (q > 0) != (sg > 0):
							out.append([i, j])
						break
					nx += d[0]
					ny += d[1]
		7:
			var fy = -1 if sg > 0 else 1
			_add(b, i, x, y + fy, sg, out)
			var crossed = y <= 4 if sg > 0 else y >= 5
			if crossed:
				_add(b, i, x - 1, y, sg, out)
				_add(b, i, x + 1, y, sg, out)


static func pseudo(b: Array, sg: int) -> Array:
	var out = []
	for i in 90:
		var p = int(b[i])
		if p != 0 and (p > 0) == (sg > 0):
			gen_piece(b, i, sg, out)
	return out


static func king_pos(b: Array, sg: int) -> int:
	for i in 90:
		if int(b[i]) == sg:
			return i
	return -1


static func in_check(b: Array, sg: int) -> bool:
	var k = king_pos(b, sg)
	if k < 0:
		return true
	for m in pseudo(b, -sg):
		if int(m[1]) == k:
			return true
	return false


static func legal(b: Array, sg: int) -> Array:
	var out = []
	for m in pseudo(b, sg):
		var f = int(m[0])
		var t = int(m[1])
		var cap = b[t]
		b[t] = b[f]
		b[f] = 0
		if not in_check(b, sg):
			out.append(m)
		b[f] = b[t]
		b[t] = cap
	return out


static func legal_from(b: Array, sg: int, from: int) -> Array:
	var out = []
	for m in legal(b, sg):
		if int(m[0]) == from:
			out.append(int(m[1]))
	return out


# ---------------------------------------------------------------- 电脑 AI

static func evaluate(b: Array) -> int:
	var s = 0
	for i in 90:
		var p = int(b[i])
		if p == 0:
			continue
		var t = absi(p)
		var v = VAL[t]
		var x = i % 9
		var y = i / 9
		if t == 7:
			var adv = (9 - y) if p > 0 else y
			if adv >= 5:
				v += 70 + (10 - absi(x - 4) * 8)
			v += adv * 6
		elif t == 4 or t == 6:
			v -= absi(x - 4) * 6
			var adv2 = (9 - y) if p > 0 else y
			v += mini(adv2, 6) * 4
		elif t == 5:
			v += 10 - absi(x - 4) * 2
		s += v if p > 0 else -v
	return s


static func _ordered(b: Array, sg: int) -> Array:
	var ms = pseudo(b, sg)
	var caps = []
	var quiet = []
	for m in ms:
		var q = int(b[int(m[1])])
		if q != 0:
			caps.append([VAL[absi(q)] * 10 - VAL[absi(int(b[int(m[0])]))], m])
		else:
			quiet.append(m)
	caps.sort_custom(func(a, c): return a[0] > c[0])
	var out = []
	for c in caps:
		out.append(c[1])
	return out + quiet


static func _negamax(b: Array, sg: int, depth: int, alpha: int, beta: int) -> int:
	nodes += 1
	if depth <= 0 or nodes > budget:
		return sg * evaluate(b)
	var best = -100000
	for m in _ordered(b, sg):
		var f = int(m[0])
		var t = int(m[1])
		var cap = int(b[t])
		if absi(cap) == 1:
			return 50000 + depth
		b[t] = b[f]
		b[f] = 0
		var v = -_negamax(b, -sg, depth - 1, -beta, -alpha)
		b[f] = b[t]
		b[t] = cap
		if v > best:
			best = v
		if v > alpha:
			alpha = v
		if alpha >= beta:
			break
	return best


static func best_move(b: Array, sg: int, max_depth: int, node_budget: int) -> Array:
	var moves = legal(b, sg)
	if moves.is_empty():
		return []
	var work = b.duplicate()
	var chosen = moves[randi() % moves.size()]
	nodes = 0
	budget = node_budget
	for depth in range(1, max_depth + 1):
		var best_v = -1000000
		var best_m = []
		var complete = true
		for m in moves:
			var f = int(m[0])
			var t = int(m[1])
			var cap = int(work[t])
			work[t] = work[f]
			work[f] = 0
			var v = -_negamax(work, -sg, depth - 1, -1000000, 1000000) + randi() % 7
			work[f] = work[t]
			work[t] = cap
			if v > best_v:
				best_v = v
				best_m = m
			if nodes > budget:
				complete = false
				break
		if complete or depth == 1:
			chosen = best_m
		if not complete:
			break
	return chosen

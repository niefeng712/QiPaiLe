extends RefCounted
## 军棋棋盘与规则（四国 / 两国 共用）
## 每家的阵地是 5 列 × 6 行，本地坐标 (r, c)：r=0 最靠前，r=5 最后一排
## 行营：(1,1)(1,3)(2,2)(3,1)(3,3)，里面的棋子不能被攻击；大本营：(5,1)(5,3)，进去的棋子不能再动
## 铁路：第0排、第4排、第0列和第4列（第0~4排）；四国中间还有九个兵站和四段弧形铁路
## 棋子编号：1司令 2军长 3师长 4旅长 5团长 6营长 7连长 8排长 9工兵 10炸弹 11地雷 12军旗（数字越小官越大）

const NAMES = ["", "司令", "军长", "师长", "旅长", "团长", "营长", "连长", "排长", "工兵", "炸弹", "地雷", "军旗"]
const SHORT = ["", "司", "军", "师", "旅", "团", "营", "连", "排", "工", "炸", "雷", "旗"]
const COUNTS = {1: 1, 2: 1, 3: 2, 4: 2, 5: 2, 6: 2, 7: 3, 8: 3, 9: 3, 10: 2, 11: 3, 12: 1}
const CAMPS = [Vector2i(1, 1), Vector2i(1, 3), Vector2i(2, 2), Vector2i(3, 1), Vector2i(3, 3)]
const HQS = [Vector2i(5, 1), Vector2i(5, 3)]
const ENGINEER = 9
const BOMB = 10
const MINE = 11
const FLAG = 12

var armies = 4
var pos = []
var army = []
var local = []
var camp = []
var hq = []
var rail = []
var road = []
var rail_adj = []
var lines = []
var line_of = []
var grid = Vector2i(17, 17)
var _at = {}
var _home = {}


func _init(n_armies: int = 4) -> void:
	armies = n_armies
	if armies == 4:
		_build4()
	else:
		_build2()
	_finish()


func _rot(p: Vector2i, k: int) -> Vector2i:
	var q = p
	for i in k:
		q = Vector2i(16 - q.y, q.x)
	return q


func _add(p: Vector2i, a: int, l: Vector2i) -> int:
	var i = pos.size()
	pos.append(p)
	army.append(a)
	local.append(l)
	camp.append(a >= 0 and CAMPS.has(l))
	hq.append(a >= 0 and HQS.has(l))
	rail.append(false)
	road.append([])
	rail_adj.append([])
	line_of.append([])
	_at[p] = i
	if a >= 0:
		_home["%d,%d,%d" % [a, l.x, l.y]] = i
	return i


func node(a: int, r: int, c: int) -> int:
	return int(_home.get("%d,%d,%d" % [a, r, c], -1))


func _col(a: int, c: int, rows: Array) -> Array:
	var out = []
	for r in rows:
		out.append(node(a, r, c))
	return out


func _row(a: int, r: int) -> Array:
	var out = []
	for c in 5:
		out.append(node(a, r, c))
	return out


func _between(i: int, j: int) -> Array:
	var p = pos[i]
	var q = pos[j]
	var out = []
	var d = Vector2i(signi(q.x - p.x), signi(q.y - p.y))
	var cur = p + d
	while cur != q:
		if _at.has(cur):
			out.append(int(_at[cur]))
		cur += d
	return out


func _build4() -> void:
	grid = Vector2i(17, 17)
	for k in 4:
		for r in 6:
			for c in 5:
				_add(_rot(Vector2i(11 + r, 6 + c), k), k, Vector2i(r, c))
	for row in [6, 8, 10]:
		for col in [6, 8, 10]:
			_add(Vector2i(row, col), -1, Vector2i(-1, -1))
	var down = [4, 3, 2, 1, 0]
	var up = [0, 1, 2, 3, 4]
	for k in 4:
		lines.append(_row(k, 0))
		lines.append(_row(k, 4))
		lines.append(_col(k, 0, down) + _col((k + 3) % 4, 4, up))
		var a = _col(k, 0, down)
		var b = _col((k + 2) % 4, 4, up)
		lines.append(a + _between(a[a.size() - 1], b[0]) + b)
	for k in 2:
		var m1 = node(k, 0, 2)
		var m2 = node(k + 2, 0, 2)
		lines.append([m1] + _between(m1, m2) + [m2])


func _build2() -> void:
	grid = Vector2i(12, 5)
	for r in 6:
		for c in 5:
			_add(Vector2i(6 + r, c), 0, Vector2i(r, c))
	for r in 6:
		for c in 5:
			_add(Vector2i(5 - r, 4 - c), 1, Vector2i(r, c))
	var down = [4, 3, 2, 1, 0]
	var up = [0, 1, 2, 3, 4]
	for k in 2:
		lines.append(_row(k, 0))
		lines.append(_row(k, 4))
	lines.append(_col(0, 0, down) + _col(1, 4, up))
	lines.append(_col(0, 4, down) + _col(1, 0, up))
	_link(node(0, 0, 2), node(1, 0, 2))


func _link(i: int, j: int) -> void:
	if not road[i].has(j):
		road[i].append(j)
	if not road[j].has(i):
		road[j].append(i)


func _finish() -> void:
	for li in lines.size():
		var ln = lines[li]
		for k in ln.size():
			var i = int(ln[k])
			rail[i] = true
			line_of[i].append([li, k])
			if k > 0:
				var j = int(ln[k - 1])
				if not rail_adj[i].has(j):
					rail_adj[i].append(j)
				if not rail_adj[j].has(i):
					rail_adj[j].append(i)
				_link(i, j)
	for i in pos.size():
		var a = int(army[i])
		if a < 0:
			continue
		var l: Vector2i = local[i]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var j = node(a, l.x + d.x, l.y + d.y)
			if j >= 0:
				_link(i, j)
		if camp[i]:
			for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var j2 = node(a, l.x + d.x, l.y + d.y)
				if j2 >= 0:
					_link(i, j2)


func count() -> int:
	return pos.size()


func army_nodes(a: int) -> Array:
	var out = []
	for i in pos.size():
		if int(army[i]) == a:
			out.append(i)
	return out


# ---------------------------------------------------------------- 布阵

func slot_ok(i: int, code: int) -> bool:
	if camp[i]:
		return false
	var r = local[i].x
	if code == FLAG:
		return hq[i]
	if code == MINE:
		return r >= 4
	if code == BOMB:
		return r >= 1
	return true


func random_layout(a: int) -> Dictionary:
	## 返回 节点 -> 棋子编号；军旗在大本营，地雷在后两排，炸弹不在第一排
	var out = {}
	var free = []
	for i in army_nodes(a):
		if not camp[i]:
			free.append(i)
	free.shuffle()
	var hqs = []
	for i in free:
		if hq[i]:
			hqs.append(i)
	var flag = int(hqs[randi() % hqs.size()])
	out[flag] = FLAG
	free.erase(flag)
	var near = []
	for j in road[flag]:
		if free.has(int(j)) and local[int(j)].x >= 4:
			near.append(int(j))
	var mines_left = 3
	if not near.is_empty():
		var m0 = int(near[randi() % near.size()])
		out[m0] = MINE
		free.erase(m0)
		mines_left -= 1
	var back = []
	for i in free:
		if local[i].x >= 4:
			back.append(i)
	back.shuffle()
	for k in mines_left:
		out[back[k]] = MINE
		free.erase(back[k])
	var bombs = 0
	for i in free.duplicate():
		if bombs >= 2:
			break
		if local[i].x >= 1:
			out[i] = BOMB
			free.erase(i)
			bombs += 1
	var rest = []
	for code in range(1, 10):
		for k in int(COUNTS[code]):
			rest.append(code)
	rest.shuffle()
	for k in free.size():
		out[free[k]] = rest[k]
	return out


# ---------------------------------------------------------------- 走法

func movable(code: int, at: int) -> bool:
	return code > 0 and code != MINE and code != FLAG and not hq[at]


## 返回能去的节点 -> 路径（用于画出走过的铁路）
## occ: 节点 -> 所属座位（-1 空）；is_enemy: Callable(seat) -> bool
func destinations(occ: Array, from: int, code: int, is_enemy: Callable) -> Dictionary:
	var out = {}
	if not movable(code, from):
		return out
	var me = int(occ[from])
	var ok = func(j: int) -> bool:
		var o = int(occ[j])
		if o == -1:
			return true
		return is_enemy.call(o) and not camp[j]
	for j in road[from]:
		if ok.call(int(j)):
			out[int(j)] = [from, int(j)]
	if not rail[from]:
		return out
	if code == ENGINEER:
		var seen = {from: true}
		var queue = [[from, [from]]]
		while not queue.is_empty():
			var it = queue.pop_front()
			for j in rail_adj[int(it[0])]:
				var jj = int(j)
				if seen.has(jj):
					continue
				seen[jj] = true
				var path = it[1].duplicate()
				path.append(jj)
				if int(occ[jj]) == -1:
					out[jj] = path
					queue.append([jj, path])
				elif ok.call(jj):
					out[jj] = path
		return out
	for lk in line_of[from]:
		var ln = lines[int(lk[0])]
		var k0 = int(lk[1])
		for step in [-1, 1]:
			var k = k0 + step
			var path = [from]
			while k >= 0 and k < ln.size():
				var j = int(ln[k])
				path.append(j)
				if int(occ[j]) == -1:
					if not out.has(j) or out[j].size() > path.size():
						out[j] = path.duplicate()
				else:
					if ok.call(j) and (not out.has(j) or out[j].size() > path.size()):
						out[j] = path.duplicate()
					break
				k += step
	return out


## 碰子结果："att" 进攻方胜，"def" 防守方胜，"both" 同归于尽
static func fight(att: int, dfn: int) -> String:
	if dfn == FLAG:
		return "att"
	if att == BOMB or dfn == BOMB:
		return "both"
	if dfn == MINE:
		return "att" if att == ENGINEER else "def"
	if att < dfn:
		return "att"
	if att == dfn:
		return "both"
	return "def"

extends RefCounted
## 中国跳棋棋盘与走法（静态函数：房主端规则、电脑AI、界面共用）
## 棋盘用立方坐标 (x, y, z)，x + y + z = 0，一共 121 个孔：
##   两个大三角形的并集：{x,y,z 都 >= -4} ∪ {x,y,z 都 <= 4}
## 六个角（顺时针）：0: x>=5  1: z<=-5  2: y>=5  3: x<=-5  4: z>=5  5: y<=-5，角 p 的对面是 p+3
## 深度 depth：角里离中间六边形越远越深（5..8，8 是尖）

const DIRS = [Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1)]
const AXIS = [[0, 1], [2, -1], [1, 1], [0, -1], [2, 1], [1, -1]]

static var _cells = []
static var _index = {}
static var _nbr = []
static var _point = []


static func _build() -> void:
	if not _cells.is_empty():
		return
	for x in range(-8, 9):
		for y in range(-8, 9):
			var z = -x - y
			if z < -8 or z > 8:
				continue
			var a = x >= -4 and y >= -4 and z >= -4
			var b = x <= 4 and y <= 4 and z <= 4
			if a or b:
				_index[Vector3i(x, y, z)] = _cells.size()
				_cells.append(Vector3i(x, y, z))
	for c in _cells:
		var row = []
		for d in DIRS:
			row.append(int(_index.get(c + d, -1)))
		_nbr.append(row)
		var p = -1
		for k in 6:
			if _coord(c, int(AXIS[k][0])) * int(AXIS[k][1]) >= 5:
				p = k
		_point.append(p)


static func _coord(c: Vector3i, k: int) -> int:
	if k == 0:
		return c.x
	if k == 1:
		return c.y
	return c.z


static func cells() -> Array:
	_build()
	return _cells


static func count() -> int:
	_build()
	return _cells.size()


static func cell(i: int) -> Vector3i:
	_build()
	return _cells[i]


static func nbr(i: int, d: int) -> int:
	_build()
	return int(_nbr[i][d])


static func point_of(i: int) -> int:
	_build()
	return int(_point[i])


## 这个孔在角 p 方向上的深度（正数越大越靠近角 p 的尖）
static func depth(i: int, p: int) -> int:
	_build()
	return _coord(_cells[i], int(AXIS[p][0])) * int(AXIS[p][1])


static func min_depth(pieces: int) -> int:
	return 6 if pieces == 6 else 5


static func zone(p: int, pieces: int) -> Array:
	_build()
	var out = []
	var md = min_depth(pieces)
	for i in _cells.size():
		if depth(i, p) >= md:
			out.append(i)
	return out


## 偏离中轴线的距离（离开中轴越远越容易被堵）
static func lateral(i: int, p: int) -> int:
	_build()
	var c = _cells[i]
	var k = int(AXIS[p][0])
	var a = _coord(c, (k + 1) % 3)
	var b = _coord(c, (k + 2) % 3)
	return absi(a - b)


## 从 from 出发能到的所有孔：dest -> 路径（包含起点和终点）
## far = true 时允许隔空跳（中间那颗棋子正好在中点、两边都空就能跳过去）
static func reachable(occ: Array, from: int, far: bool) -> Dictionary:
	_build()
	var out = {}
	for d in 6:
		var n = int(_nbr[from][d])
		if n >= 0 and int(occ[n]) == -1:
			out[n] = [from, n]
	var seen = {from: true}
	var queue = [[from, [from]]]
	while not queue.is_empty():
		var it = queue.pop_front()
		var cur = int(it[0])
		var path = it[1]
		for d in 6:
			var land = _jump(occ, cur, d, far, from)
			if land < 0 or seen.has(land):
				continue
			seen[land] = true
			var np = path.duplicate()
			np.append(land)
			out[land] = np
			queue.append([land, np])
	return out


static func _empty(occ: Array, i: int, from: int) -> bool:
	return i == from or int(occ[i]) == -1


static func _jump(occ: Array, cur: int, d: int, far: bool, from: int) -> int:
	var k = 0
	var c = cur
	while true:
		c = int(_nbr[c][d])
		k += 1
		if c < 0:
			return -1
		if not _empty(occ, c, from):
			break
		if not far:
			return -1
	# c 是第 k 格上的棋子，后面还要再空 k-1 格，第 2k 格落下
	var land = c
	for j in k:
		land = int(_nbr[land][d])
		if land < 0:
			return -1
		if not _empty(occ, land, from):
			return -1
	return land

extends RefCounted
## 麻将牌与胡牌判定（静态函数：房主端规则、电脑AI、界面"提示"共用）
## 牌种 0..33：0..8 一~九万，9..17 一~九条，18..26 一~九筒，27..33 东南西北中发白
## 牌编号 = 牌种*4 + 第几张(0..3)
## 向听数 shanten：-1 = 已经胡了，0 = 听牌，1 = 差一张听牌 ……

const NUMS = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
const SUIT_CH = ["万", "条", "筒"]
const HONORS = ["东", "南", "西", "北", "中", "发", "白"]
const TERMINALS = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]

static var _memo = {}


static func ttype(id: int) -> int:
	return id / 4


static func tsuit(t: int) -> int:
	if t >= 27:
		return 3
	return t / 9


static func tnum(t: int) -> int:
	if t >= 27:
		return 0
	return t % 9 + 1


static func tname(t: int) -> String:
	if t < 0:
		return "?"
	if t >= 27:
		return HONORS[t - 27]
	return NUMS[t % 9] + SUIT_CH[t / 9]


static func counts_of(ids: Array) -> Array:
	var c = []
	c.resize(34)
	c.fill(0)
	for i in ids:
		c[int(i) / 4] += 1
	return c


static func total(c: Array) -> int:
	var n = 0
	for v in c:
		n += int(v)
	return n


# ---------------------------------------------------------------- 向听数

static func _merge(acc: Dictionary, res: Array, dm: int, dt: int, dp: int) -> void:
	for r in res:
		var p = int(r[2]) + dp
		if p > 1:
			continue
		var m = int(r[0]) + dm
		var t = int(r[1]) + dt
		acc[m * 100 + t * 10 + p] = [m, t, p]


## 一门牌（9种，字牌7种）能拆出的所有 [面子数, 搭子数, 是否有雀头]
static func _sub(c: Array, i: int, honors: bool) -> Array:
	var n = c.size()
	while i < n and int(c[i]) == 0:
		i += 1
	if i >= n:
		return [[0, 0, 0]]
	var key = "%s%d:%s" % ["h" if honors else "s", n - i, str(c.slice(i))]
	if _memo.has(key):
		return _memo[key]
	var acc = {}
	if int(c[i]) >= 3:
		c[i] -= 3
		_merge(acc, _sub(c, i, honors), 1, 0, 0)
		c[i] += 3
	if not honors and i + 2 < n and int(c[i + 1]) > 0 and int(c[i + 2]) > 0:
		c[i] -= 1
		c[i + 1] -= 1
		c[i + 2] -= 1
		_merge(acc, _sub(c, i, honors), 1, 0, 0)
		c[i] += 1
		c[i + 1] += 1
		c[i + 2] += 1
	if int(c[i]) >= 2:
		c[i] -= 2
		var r = _sub(c, i, honors)
		_merge(acc, r, 0, 0, 1)
		_merge(acc, r, 0, 1, 0)
		c[i] += 2
	if not honors and i + 1 < n and int(c[i + 1]) > 0:
		c[i] -= 1
		c[i + 1] -= 1
		_merge(acc, _sub(c, i, honors), 0, 1, 0)
		c[i] += 1
		c[i + 1] += 1
	if not honors and i + 2 < n and int(c[i + 2]) > 0:
		c[i] -= 1
		c[i + 2] -= 1
		_merge(acc, _sub(c, i, honors), 0, 1, 0)
		c[i] += 1
		c[i + 2] += 1
	c[i] -= 1
	_merge(acc, _sub(c, i, honors), 0, 0, 0)
	c[i] += 1
	var out = acc.values()
	_memo[key] = out
	return out


static func shanten(c: Array, ex: int, allow7: bool) -> int:
	if _memo.size() > 80000:
		_memo.clear()
	var best = {0: 0}
	for g in 4:
		var part = c.slice(g * 9, g * 9 + 9) if g < 3 else c.slice(27, 34)
		var opts = _sub(part, 0, g == 3)
		var nb = {}
		for k in best:
			var m0 = int(k) / 10
			var p0 = int(k) % 10
			var t0 = int(best[k])
			for o in opts:
				var p = p0 + int(o[2])
				if p > 1:
					continue
				var nk = (m0 + int(o[0])) * 10 + p
				var t = t0 + int(o[1])
				if not nb.has(nk) or int(nb[nk]) < t:
					nb[nk] = t
		best = nb
	var s = 99
	for k in best:
		var m = mini(int(k) / 10 + ex, 4)
		var p = int(k) % 10
		var t = mini(int(best[k]), 4 - m)
		s = mini(s, 8 - 2 * m - t - p)
	if allow7 and ex == 0:
		var pairs = 0
		var kinds = 0
		for v in c:
			if int(v) >= 2:
				pairs += 1
			if int(v) >= 1:
				kinds += 1
		s = mini(s, 6 - pairs + maxi(0, 7 - kinds))
	return s


# ---------------------------------------------------------------- 胡牌判定

static func is_seven_pairs(c: Array) -> bool:
	if total(c) != 14:
		return false
	for v in c:
		if int(v) % 2 != 0:
			return false
	return true


static func is_kokushi(c: Array) -> bool:
	if total(c) != 14:
		return false
	for t in 34:
		var v = int(c[t])
		if TERMINALS.has(t):
			if v < 1:
				return false
		elif v != 0:
			return false
	return true


## 手里的牌是不是全是刻子 + 一对将（对对胡）
static func is_all_triplets(c: Array) -> bool:
	var pairs = 0
	for v in c:
		var x = int(v)
		if x == 2:
			pairs += 1
		elif x != 0 and x != 3:
			return false
	return pairs == 1


static func is_win(c: Array, ex: int, allow7: bool, allow13: bool) -> bool:
	if total(c) % 3 != 2:
		return false
	if shanten(c, ex, false) == -1:
		return true
	if ex == 0 and allow7 and is_seven_pairs(c):
		return true
	if ex == 0 and allow13 and is_kokushi(c):
		return true
	return false


# ---------------------------------------------------------------- 电脑AI / 提示

## 孤张程度：越小越没用、越应该先打
static func iso(c: Array, t: int) -> int:
	var v = int(c[t]) * 4
	if t >= 27:
		return v
	var s = t / 9
	for d in [-2, -1, 1, 2]:
		var u = t + d
		if u >= 0 and u < 27 and u / 9 == s:
			v += int(c[u]) * (3 if absi(d) == 1 else 1)
	var nm = t % 9
	if nm == 0 or nm == 8:
		v -= 1
	return v


static func _near(c: Array, u: int) -> bool:
	if int(c[u]) > 0:
		return true
	if u >= 27:
		return false
	for d in [-2, -1, 1, 2]:
		var v = u + d
		if v >= 0 and v < 27 and v / 9 == u / 9 and int(c[v]) > 0:
			return true
	return false


## 进张数：摸到哪些牌能让向听数变小，一共还有几张
static func ukeire(c: Array, ex: int, base: int, que_s: int, n_types: int) -> int:
	var tot = 0
	for u in n_types:
		if que_s >= 0 and tsuit(u) == que_s:
			continue
		if int(c[u]) >= 4 or not _near(c, u):
			continue
		c[u] += 1
		if shanten(c, ex, ex == 0) < base:
			tot += 5 - int(c[u])
		c[u] -= 1
	return tot


static func _id_of(ids: Array, t: int) -> int:
	for i in range(ids.size() - 1, -1, -1):
		if int(ids[i]) / 4 == t:
			return int(ids[i])
	return -1


## 建议打哪张：有缺门的牌先打缺门；否则打完向听数最小、进张最多的那张
static func suggest_discard(ids: Array, ex: int, que_s: int, n_types: int) -> int:
	if ids.is_empty():
		return -1
	var c = counts_of(ids)
	if que_s >= 0:
		var bt = -1
		var bv = 999
		for i in ids:
			var t = int(i) / 4
			if tsuit(t) == que_s and iso(c, t) < bv:
				bv = iso(c, t)
				bt = t
		if bt >= 0:
			return _id_of(ids, bt)
	var best = 99
	var cands = []
	for t in 34:
		if int(c[t]) == 0:
			continue
		c[t] -= 1
		var s = shanten(c, ex, ex == 0)
		c[t] += 1
		if s < best:
			best = s
			cands = [t]
		elif s == best:
			cands.append(t)
	var pick = int(cands[0])
	if cands.size() > 1:
		var bk = -999999
		for t in cands:
			var k = -iso(c, t)
			if best <= 2:
				c[t] -= 1
				k += ukeire(c, ex, best, que_s, n_types) * 100
				c[t] += 1
			if k > bk:
				bk = k
				pick = t
	return _id_of(ids, pick)


## 定缺建议：牌最少的那一门
static func suggest_que(ids: Array) -> int:
	var c = counts_of(ids)
	var best = 0
	var bk = 999999
	for s in 3:
		var n = 0
		var v = 0
		for t in range(s * 9, s * 9 + 9):
			n += int(c[t])
			if int(c[t]) > 0:
				v += iso(c, t)
		var k = n * 1000 + v
		if k < bk:
			bk = k
			best = s
	return best


## 换三张建议：在至少有3张的花色里挑最少的那门，换出最没用的3张
static func suggest_exchange(ids: Array) -> Array:
	var c = counts_of(ids)
	var best = -1
	var bn = 99
	for s in 3:
		var n = 0
		for t in range(s * 9, s * 9 + 9):
			n += int(c[t])
		if n >= 3 and n < bn:
			bn = n
			best = s
	var keyed = []
	for i in ids:
		var t = int(i) / 4
		if tsuit(t) == best:
			keyed.append([iso(c, t) * 1000 + t, int(i)])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out = []
	for k in mini(3, keyed.size()):
		out.append(keyed[k][1])
	return out

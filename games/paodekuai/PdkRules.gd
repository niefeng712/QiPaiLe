extends RefCounted
## 跑得快牌型（静态函数）：一副牌，没有大小王；3最小，2最大
## 牌编号 0..51：点数 = c/4 + 3（3..15，15 是 2），花色 = c%4（0♠ 1♥ 2♣ 3♦）
## 牌型：单张、对子、连对（2对起）、三带二、顺子（5张起，不能带2）、飞机（2个三张连起来，各带两张）、炸弹（4张）
## 最后一手牌可以少带：三张、三带一、飞机少带都可以一次出完

const SUITS = ["♠", "♥", "♣", "♦"]
const TYPE_NAMES = {"single": "单张", "pair": "对子", "pairs": "连对", "triple": "三带二", "straight": "顺子", "plane": "飞机", "bomb": "炸弹"}


static func rank(c: int) -> int:
	return c / 4 + 3


static func suit(c: int) -> int:
	return c % 4


static func rank_text(r: int) -> String:
	match r:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
		15:
			return "2"
	return str(r)


static func card_id(r: int, s: int) -> int:
	return (r - 3) * 4 + s


static func sort_hand(cards: Array) -> Array:
	var a = cards.duplicate()
	a.sort()
	a.reverse()
	return a


static func _counts(cards: Array) -> Dictionary:
	var c = {}
	for x in cards:
		var r = rank(int(x))
		c[r] = int(c.get(r, 0)) + 1
	return c


static func _run(ranks: Array) -> bool:
	for i in range(1, ranks.size()):
		if int(ranks[i]) != int(ranks[i - 1]) + 1:
			return false
	return true


## 识别牌型；final = 这是手里最后几张牌（可以少带）
static func classify(cards: Array, final: bool) -> Dictionary:
	var n = cards.size()
	if n == 0:
		return {}
	var cnt = _counts(cards)
	var ranks = cnt.keys()
	ranks.sort()
	var top = int(ranks[ranks.size() - 1])
	if n == 1:
		return {"type": "single", "rank": top, "len": 1, "n": 1}
	if n == 2 and ranks.size() == 1:
		return {"type": "pair", "rank": top, "len": 1, "n": 2}
	if n == 4 and ranks.size() == 1:
		return {"type": "bomb", "rank": top, "len": 1, "n": 4}
	if n >= 5 and ranks.size() == n and top <= 14 and _run(ranks):
		return {"type": "straight", "rank": top, "len": n, "n": n}
	if n >= 4 and n % 2 == 0 and ranks.size() == n / 2 and top <= 14 and _run(ranks):
		var ok = true
		for r in ranks:
			if int(cnt[r]) != 2:
				ok = false
		if ok:
			return {"type": "pairs", "rank": top, "len": n / 2, "n": n}
	# 三带二 / 飞机：找最长的一串三张
	var trip = []
	for r in ranks:
		if int(cnt[r]) >= 3:
			trip.append(int(r))
	var best = {}
	for i in trip.size():
		for j in range(i, trip.size()):
			var seq = trip.slice(i, j + 1)
			var k = seq.size()
			if k > 1 and (not _run(seq) or int(seq[k - 1]) > 14):
				continue
			var need = 5 * k
			if n == need or (final and n >= 3 * k and n < need):
				if best.is_empty() or k > int(best["len"]):
					best = {"type": "triple" if k == 1 else "plane", "rank": int(seq[k - 1]), "len": k, "n": n, "short": n != need}
	return best


static func describe(p: Dictionary) -> String:
	var t = str(p.get("type", ""))
	var nm = str(TYPE_NAMES.get(t, t))
	if t == "triple" and bool(p.get("short", false)):
		nm = "三带一" if int(p["n"]) == 4 else "三张"
	return nm


static func can_beat(p: Dictionary, prev: Dictionary) -> bool:
	if p.is_empty():
		return false
	if prev.is_empty():
		return true
	var t = str(p["type"])
	var pt = str(prev["type"])
	if t == "bomb":
		return pt != "bomb" or int(p["rank"]) > int(prev["rank"])
	if pt == "bomb" or t != pt:
		return false
	if int(p["len"]) != int(prev["len"]):
		return false
	if t != "triple" and t != "plane" and int(p["n"]) != int(prev["n"]):
		return false
	if (t == "triple" or t == "plane") and int(p["n"]) > int(prev["n"]):
		return false
	return int(p["rank"]) > int(prev["rank"])


# ---------------------------------------------------------------- 候选出牌（提示 + 电脑）

static func _groups(hand: Array) -> Dictionary:
	var g = {}
	var asc = hand.duplicate()
	asc.sort()
	for c in asc:
		var r = rank(int(c))
		if not g.has(r):
			g[r] = []
		g[r].append(int(c))
	return g


static func _kick(g: Dictionary, excl: Array, count: int) -> Array:
	## 挑最没用的单牌当带的牌：先挑单张，再拆对子，不拆炸弹
	var out = []
	for want in [1, 2, 3]:
		for r in range(3, 16):
			if out.size() >= count:
				return out
			if excl.has(r) or not g.has(r) or g[r].size() != want:
				continue
			for c in g[r]:
				if out.size() < count:
					out.append(int(c))
	return out


static func options(hand: Array) -> Array:
	var g = _groups(hand)
	var out = []
	var seen = {}
	var add = func(cards: Array):
		if cards.is_empty():
			return
		var key = str(sort_hand(cards))
		if not seen.has(key):
			seen[key] = true
			out.append(cards)
	add.call(hand.duplicate())
	for r in range(3, 16):
		if not g.has(r):
			continue
		var arr = g[r]
		add.call([arr[0]])
		if arr.size() >= 2:
			add.call(arr.slice(0, 2))
		if arr.size() >= 3:
			var k = _kick(g, [r], 2)
			add.call(arr.slice(0, 3) + k)
		if arr.size() == 4:
			add.call(arr.duplicate())
	for start in range(3, 11):
		for l in range(5, 13):
			var top = start + l - 1
			if top > 14:
				break
			var cards = []
			var ok = true
			for r in range(start, top + 1):
				if not g.has(r):
					ok = false
					break
				cards.append(g[r][0])
			if not ok:
				break
			add.call(cards)
	for start in range(3, 14):
		for l in range(2, 9):
			var top2 = start + l - 1
			if top2 > 14:
				break
			var cards2 = []
			var ok2 = true
			for r in range(start, top2 + 1):
				if not g.has(r) or g[r].size() < 2:
					ok2 = false
					break
				cards2 += g[r].slice(0, 2)
			if not ok2:
				break
			add.call(cards2)
	for start in range(3, 14):
		for l in range(2, 5):
			var top3 = start + l - 1
			if top3 > 14:
				break
			var cards3 = []
			var used = []
			var ok3 = true
			for r in range(start, top3 + 1):
				if not g.has(r) or g[r].size() < 3:
					ok3 = false
					break
				cards3 += g[r].slice(0, 3)
				used.append(r)
			if not ok3:
				break
			add.call(cards3 + _kick(g, used, 2 * l))
	return out


static func candidates(hand: Array, prev: Dictionary) -> Array:
	var out = []
	for o in options(hand):
		var p = classify(o, o.size() == hand.size())
		if p.is_empty():
			continue
		if can_beat(p, prev):
			out.append([o, p])
	return out


static func min_rank(cards: Array) -> int:
	var m = 99
	for c in cards:
		m = mini(m, rank(int(c)))
	return m


static func max_card(hand: Array) -> int:
	var best = -1
	for c in hand:
		if best < 0 or rank(int(c)) > rank(best) or (rank(int(c)) == rank(best) and int(c) > best):
			best = int(c)
	return best

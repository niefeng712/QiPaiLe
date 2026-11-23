extends RefCounted
## 斗地主牌型规则（房主端判定 + 客户端"提示"共用，全部是静态函数）
## 牌编号：0..51 = (点数-3)*4 + 花色，52 = 小王，53 = 大王
## 点数：3..10, J=11, Q=12, K=13, A=14, 2=15, 小王=16, 大王=17
## 癞子：laizi > 0 时，该点数的牌可以当作 3..2 中任意点数（不能当王）

const TYPE_NAMES = {
	"single": "单张", "pair": "对子", "triple": "三张", "triple_1": "三带一", "triple_2": "三带二",
	"straight": "顺子", "pair_straight": "连对", "plane": "飞机", "plane_1": "飞机带翅膀",
	"plane_2": "飞机带对子", "four_2": "四带二", "four_22": "四带两对", "bomb": "炸弹", "rocket": "王炸",
}
const BOMB_NAMES = {1: "软炸弹", 2: "炸弹", 3: "癞子炸弹"}


static func card_rank(c: int) -> int:
	if c == 52:
		return 16
	if c == 53:
		return 17
	return c / 4 + 3


static func card_suit(c: int) -> int:
	if c >= 52:
		return -1
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
		16:
			return "小王"
		17:
			return "大王"
	return str(r)


static func sort_hand(cards: Array) -> Array:
	var out = cards.duplicate()
	out.sort()
	out.reverse()
	return out


static func describe(p: Dictionary) -> String:
	var t = str(p.get("type", ""))
	if t == "bomb":
		return "%s %s" % [BOMB_NAMES.get(int(p.get("level", 2)), "炸弹"), rank_text(int(p["rank"]))]
	if t == "rocket":
		return "王炸"
	return str(TYPE_NAMES.get(t, t))


static func is_bomb(p: Dictionary) -> bool:
	var t = str(p.get("type", ""))
	return t == "bomb" or t == "rocket"


# ---------------------------------------------------------------- 牌型识别

static func _pat(t: String, r: int, l: int, n: int) -> Dictionary:
	return {"type": t, "rank": r, "len": l, "n": n, "level": 0}


static func _consecutive(ranks: Array) -> bool:
	for i in range(1, ranks.size()):
		if int(ranks[i]) != int(ranks[i - 1]) + 1:
			return false
	return true


static func classify(cnt: Dictionary, n: int) -> Array:
	var out = []
	var ranks = []
	for r in cnt.keys():
		if int(cnt[r]) > 0:
			ranks.append(int(r))
	ranks.sort()
	if ranks.is_empty():
		return out
	var top = int(ranks[ranks.size() - 1])
	if n == 1:
		out.append(_pat("single", int(ranks[0]), 1, 1))
	elif n == 2:
		if int(cnt.get(16, 0)) == 1 and int(cnt.get(17, 0)) == 1:
			var rk = _pat("rocket", 17, 1, 2)
			rk["level"] = 9
			out.append(rk)
		elif ranks.size() == 1 and top < 16:
			out.append(_pat("pair", top, 1, 2))
	elif n == 3:
		if ranks.size() == 1 and top < 16:
			out.append(_pat("triple", top, 1, 3))
	elif n == 4:
		if ranks.size() == 1 and top < 16:
			out.append(_pat("bomb", top, 1, 4))
		elif ranks.size() == 2:
			for r in ranks:
				if int(cnt[r]) == 3 and r < 16:
					out.append(_pat("triple_1", r, 1, 4))
	elif n == 5:
		if ranks.size() == 2:
			for r in ranks:
				var other = int(ranks[0]) if r == int(ranks[1]) else int(ranks[1])
				if int(cnt[r]) == 3 and int(cnt[other]) == 2 and r < 16 and other < 16:
					out.append(_pat("triple_2", r, 1, 5))
	if n == 6:
		for r in ranks:
			if int(cnt[r]) == 4 and r < 16:
				out.append(_pat("four_2", r, 1, 6))
	if n == 8 and ranks.size() == 3:
		for r in ranks:
			if int(cnt[r]) == 4 and r < 16:
				var ok = true
				for o in ranks:
					if o != r and (int(cnt[o]) != 2 or o >= 16):
						ok = false
				if ok:
					out.append(_pat("four_22", r, 1, 8))
	# 顺子
	if n >= 5 and ranks.size() == n and top <= 14 and _consecutive(ranks):
		out.append(_pat("straight", top, n, n))
	# 连对
	if n >= 6 and n % 2 == 0 and ranks.size() == n / 2 and top <= 14 and _consecutive(ranks):
		var all2 = true
		for r in ranks:
			if int(cnt[r]) != 2:
				all2 = false
		if all2:
			out.append(_pat("pair_straight", top, n / 2, n))
	# 飞机
	for k in range(2, 7):
		if n == 3 * k and ranks.size() == k and top <= 14 and _consecutive(ranks):
			var all3 = true
			for r in ranks:
				if int(cnt[r]) != 3:
					all3 = false
			if all3:
				out.append(_pat("plane", top, k, n))
		if n == 4 * k or n == 5 * k:
			for start in range(3, 15 - k + 1):
				var ok2 = true
				for r in range(start, start + k):
					if int(cnt.get(r, 0)) < 3:
						ok2 = false
						break
				if not ok2:
					continue
				var t_top = start + k - 1
				if n == 4 * k:
					out.append(_pat("plane_1", t_top, k, n))
				else:
					var rest_ok = true
					for r in ranks:
						var left = int(cnt[r])
						if r >= start and r <= t_top:
							left -= 3
						if left % 2 != 0 or (left > 0 and r >= 16):
							rest_ok = false
					if rest_ok:
						out.append(_pat("plane_2", t_top, k, n))
	return out


static func _subs(l: int, start: int, cur: Array, out: Array) -> void:
	if cur.size() == l:
		out.append(cur.duplicate())
		return
	for r in range(start, 16):
		cur.append(r)
		_subs(l, r, cur, out)
		cur.pop_back()


static func bomb_level(cards: Array, r: int, laizi: int) -> int:
	if laizi <= 0:
		return 2
	var natural = 0
	for c in cards:
		if card_rank(int(c)) == r:
			natural += 1
	if natural == 4 and r == laizi:
		return 3
	if natural == 4:
		return 2
	return 1


static func evaluate(cards: Array, laizi: int) -> Array:
	var n = cards.size()
	var out = []
	if n == 0:
		return out
	var base = {}
	var lz = 0
	for c in cards:
		var r = card_rank(int(c))
		if laizi > 0 and r == laizi:
			lz += 1
		else:
			base[r] = int(base.get(r, 0)) + 1
	var subs = []
	_subs(lz, 3, [], subs)
	var seen = {}
	for s in subs:
		var cnt = base.duplicate()
		for r in s:
			cnt[r] = int(cnt.get(r, 0)) + 1
		for p in classify(cnt, n):
			if str(p["type"]) == "bomb":
				p["level"] = bomb_level(cards, int(p["rank"]), laizi)
			var key = "%s|%d|%d|%d" % [str(p["type"]), int(p["rank"]), int(p["len"]), int(p["level"])]
			if not seen.has(key):
				seen[key] = true
				out.append(p)
	return out


static func can_beat(p: Dictionary, prev: Dictionary) -> bool:
	if prev.is_empty():
		return true
	var t = str(p["type"])
	var pt = str(prev["type"])
	if t == "rocket":
		return pt != "rocket"
	if pt == "rocket":
		return false
	if t == "bomb":
		if pt != "bomb":
			return true
		if int(p["level"]) != int(prev["level"]):
			return int(p["level"]) > int(prev["level"])
		return int(p["rank"]) > int(prev["rank"])
	if pt == "bomb":
		return false
	return t == pt and int(p["len"]) == int(prev["len"]) and int(p["n"]) == int(prev["n"]) and int(p["rank"]) > int(prev["rank"])


## 选出这手牌最合适的牌型；prev 为空表示首家出牌。管不上或不成牌型时返回 {}
static func choose_pattern(cards: Array, laizi: int, prev: Dictionary) -> Dictionary:
	var pats = evaluate(cards, laizi)
	if pats.is_empty():
		return {}
	var best = {}
	if not prev.is_empty():
		for p in pats:
			if not can_beat(p, prev):
				continue
			if best.is_empty():
				best = p
				continue
			var pb = is_bomb(p)
			var bb = is_bomb(best)
			if pb != bb:
				if not pb:
					best = p
			elif int(p["level"]) < int(best["level"]) or (int(p["level"]) == int(best["level"]) and int(p["rank"]) < int(best["rank"])):
				best = p
		return best
	for p in pats:
		if best.is_empty():
			best = p
			continue
		if int(p["level"]) != int(best["level"]):
			if int(p["level"]) > int(best["level"]):
				best = p
		elif int(p["rank"]) > int(best["rank"]):
			best = p
	return best


# ---------------------------------------------------------------- 候选出牌（电脑AI + 提示）

static func groups_of(hand: Array) -> Dictionary:
	var g = {}
	for c in sort_hand(hand):
		var r = card_rank(int(c))
		if not g.has(r):
			g[r] = []
		g[r].append(int(c))
	return g


static func _cnt(g: Dictionary, r: int) -> int:
	if g.has(r):
		return g[r].size()
	return 0


static func _kickers(g: Dictionary, excl: Array, count: int, per: int) -> Array:
	var out = []
	var used = 0
	for pass_i in 2:
		for r in range(3, 16):
			if used >= count:
				break
			if excl.has(r):
				continue
			var c = _cnt(g, r)
			if c < per or c == 4:
				continue
			if pass_i == 0 and c != per:
				continue
			if pass_i == 1 and c == per:
				continue
			out += g[r].slice(0, per)
			used += 1
	if used < count:
		return []
	return out


static func _dedupe_valid(lists: Array, laizi: int, prev: Dictionary) -> Array:
	var out = []
	var seen = {}
	for c in lists:
		if c.is_empty():
			continue
		var key = str(sort_hand(c))
		if seen.has(key):
			continue
		seen[key] = true
		if choose_pattern(c, laizi, prev).is_empty():
			continue
		out.append(c)
	return out


static func follow_candidates(hand: Array, laizi: int, prev: Dictionary) -> Array:
	var g = groups_of(hand)
	var cands = []
	var t = str(prev.get("type", ""))
	var pr = int(prev.get("rank", 0))
	var k = int(prev.get("len", 1))
	if t == "single":
		for want in [1, 2, 3]:
			for r in range(pr + 1, 18):
				if _cnt(g, r) == want:
					cands.append([g[r][0]])
	elif t == "pair":
		for want in [2, 3]:
			for r in range(pr + 1, 16):
				if _cnt(g, r) == want:
					cands.append(g[r].slice(0, 2))
	elif t == "triple" or t == "triple_1" or t == "triple_2":
		for r in range(pr + 1, 16):
			if _cnt(g, r) == 3:
				var base = g[r].slice(0, 3)
				if t == "triple":
					cands.append(base)
				else:
					var kick = _kickers(g, [r], 1, 1 if t == "triple_1" else 2)
					if not kick.is_empty():
						cands.append(base + kick)
	elif t in ["straight", "pair_straight", "plane", "plane_1", "plane_2"]:
		var per = 1
		if t == "pair_straight":
			per = 2
		elif t.begins_with("plane"):
			per = 3
		for top in range(pr + 1, 15):
			var start = top - k + 1
			if start < 3:
				continue
			var ok = true
			var cards = []
			var used = []
			for r in range(start, top + 1):
				if _cnt(g, r) < per:
					ok = false
					break
				cards += g[r].slice(0, per)
				used.append(r)
			if not ok:
				continue
			if t == "plane_1" or t == "plane_2":
				var kick2 = _kickers(g, used, k, 1 if t == "plane_1" else 2)
				if kick2.is_empty():
					continue
				cards += kick2
			cands.append(cards)
	elif t == "four_2" or t == "four_22":
		for r in range(pr + 1, 16):
			if _cnt(g, r) == 4:
				var kick3 = _kickers(g, [r], 2, 1 if t == "four_2" else 2)
				if not kick3.is_empty():
					cands.append(g[r] + kick3)
	var lz = []
	if laizi > 0 and g.has(laizi):
		lz = g[laizi]
	if not lz.is_empty() and t in ["single", "pair", "triple"]:
		var need_n = {"single": 1, "pair": 2, "triple": 3}[t]
		for r in range(pr + 1, 16):
			if r == laizi:
				continue
			var nat = _cnt(g, r)
			var need = need_n - nat
			if nat >= 1 and need >= 1 and need <= lz.size():
				cands.append(g[r] + lz.slice(0, need))
	var bombs = []
	if t != "rocket":
		for r in range(3, 16):
			if _cnt(g, r) == 4:
				bombs.append(g[r].duplicate())
		if not lz.is_empty():
			for r in range(3, 16):
				if r == laizi:
					continue
				var nat2 = _cnt(g, r)
				if nat2 >= 1 and nat2 < 4 and nat2 + lz.size() >= 4:
					bombs.append(g[r] + lz.slice(0, 4 - nat2))
		if _cnt(g, 16) == 1 and _cnt(g, 17) == 1:
			bombs.append([g[16][0], g[17][0]])
	return _dedupe_valid(cands + bombs, laizi, prev)


static func lead_options(hand: Array, laizi: int) -> Array:
	var g = groups_of(hand)
	var opts = []
	opts.append(hand.duplicate())
	for start in range(3, 11):
		if _cnt(g, start - 1) >= 1 and _cnt(g, start - 1) < 4 and start > 3:
			continue
		var run = []
		var r = start
		while r <= 14 and _cnt(g, r) >= 1 and _cnt(g, r) < 4:
			run.append(g[r][0])
			r += 1
		if run.size() >= 5:
			opts.append(run)
	for start in range(3, 13):
		var run2 = []
		var r2 = start
		while r2 <= 14 and _cnt(g, r2) >= 2 and _cnt(g, r2) < 4:
			run2 += g[r2].slice(0, 2)
			r2 += 1
		if run2.size() >= 6:
			opts.append(run2)
	for start in range(3, 14):
		var used = []
		var r3 = start
		var cards = []
		while r3 <= 14 and _cnt(g, r3) == 3:
			used.append(r3)
			cards += g[r3]
			r3 += 1
		if used.size() >= 2:
			var k1 = _kickers(g, used, used.size(), 1)
			if not k1.is_empty():
				opts.append(cards + k1)
			var k2 = _kickers(g, used, used.size(), 2)
			if not k2.is_empty():
				opts.append(cards + k2)
			opts.append(cards)
	for r in range(3, 16):
		if _cnt(g, r) == 3:
			var base = g[r].duplicate()
			var s1 = _kickers(g, [r], 1, 1)
			if not s1.is_empty():
				opts.append(base + s1)
			var s2 = _kickers(g, [r], 1, 2)
			if not s2.is_empty():
				opts.append(base + s2)
			opts.append(base)
	for r in range(3, 18):
		var c = _cnt(g, r)
		if c >= 1 and c <= 2:
			opts.append(g[r].duplicate())
		if c >= 2:
			opts.append([g[r][0]])
	for r in range(3, 16):
		if _cnt(g, r) == 4:
			opts.append(g[r].duplicate())
	if _cnt(g, 16) == 1 and _cnt(g, 17) == 1:
		opts.append([g[16][0], g[17][0]])
	var out = _dedupe_valid(opts, laizi, {})
	if out.is_empty() and not hand.is_empty():
		var sh = sort_hand(hand)
		out.append([sh[sh.size() - 1]])
	return out


static func _min_rank(cards: Array) -> int:
	var m = 99
	for c in cards:
		m = mini(m, card_rank(int(c)))
	return m


## 电脑首家出牌：优先把最小的牌连同顺子/三带一起出掉
static func bot_lead(hand: Array, laizi: int, danger: bool) -> Array:
	var opts = lead_options(hand, laizi)
	if opts[0].size() == hand.size():
		return opts[0]
	var g = groups_of(hand)
	var low = -1
	for r in range(3, 18):
		var c = _cnt(g, r)
		if c >= 1 and c <= 3:
			low = r
			break
	if low == -1:
		return opts[0]
	var best = []
	for o in opts:
		var p = choose_pattern(o, laizi, {})
		if is_bomb(p):
			continue
		if _min_rank(o) != low:
			continue
		if o.size() > best.size():
			best = o
	if best.is_empty():
		return opts[0]
	if danger and best.size() == 1:
		for o in opts:
			if o.size() >= 2 and not is_bomb(choose_pattern(o, laizi, {})):
				return o
		var sh = sort_hand(hand)
		return [sh[0]]
	return best

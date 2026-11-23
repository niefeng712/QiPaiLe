extends RefCounted
## 升级（拖拉机）牌规则：全部是静态函数，房主端判定、电脑AI、客户端提示共用
## ctx = make_ctx(级牌点数, 主花色)；主花色 0..3 = ♠♥♣♦，-1 = 无主，-2 = 还没定主
## 牌编号 0..107（两副牌）：f = c % 54；f < 52 时点数 = f / 4 + 2（2..14，14 = A），花色 = f % 4；52 小王，53 大王
## 主牌从小到大：主花色 2..A（去掉级牌）< 副级牌 < 主级牌 < 小王 < 大王
## 对子 = 两张完全相同的牌；拖拉机 = 同一花色（或都是主牌）相邻的两个以上对子

const TRUMP = 4
const SUITS = ["♠", "♥", "♣", "♦"]
const SUIT_NAMES = ["黑桃", "红桃", "梅花", "方块"]


static func make_ctx(level: int, trump: int) -> Dictionary:
	return {"level": level, "trump": trump}


static func card_id(r: int, s: int, deck: int = 0) -> int:
	return (r - 2) * 4 + s + 54 * deck


static func rank(c: int) -> int:
	var f = c % 54
	if f == 52:
		return 15
	if f == 53:
		return 16
	return f / 4 + 2


static func suit(c: int) -> int:
	var f = c % 54
	if f >= 52:
		return -1
	return f % 4


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
			return "小王"
		16:
			return "大王"
	return str(r)


static func level_text(r: int) -> String:
	if r > 14:
		return "过A"
	return rank_text(r)


static func suit_label(e: int) -> String:
	if e == TRUMP:
		return "主牌"
	if e >= 0 and e < 4:
		return SUIT_NAMES[e]
	return "?"


static func trump_text(t: int) -> String:
	if t == -1:
		return "无主"
	if t >= 0 and t < 4:
		return SUITS[t] + SUIT_NAMES[t]
	return "未定"


static func points_of(c: int) -> int:
	var r = rank(c)
	if r == 5:
		return 5
	if r == 10 or r == 13:
		return 10
	return 0


static func sum_points(cards: Array) -> int:
	var t = 0
	for c in cards:
		t += points_of(int(c))
	return t


static func eff(c: int, ctx: Dictionary) -> int:
	var f = c % 54
	if f >= 52:
		return TRUMP
	if f / 4 + 2 == int(ctx["level"]):
		return TRUMP
	if f % 4 == int(ctx["trump"]):
		return TRUMP
	return f % 4


static func strength(c: int, ctx: Dictionary) -> int:
	var f = c % 54
	if f == 53:
		return 100
	if f == 52:
		return 99
	var r = f / 4 + 2
	if r == int(ctx["level"]):
		return 98 if f % 4 == int(ctx["trump"]) else 97
	return r


static func ord_list(e: int, ctx: Dictionary) -> Array:
	var key = "_ol%d" % e
	if ctx.has(key):
		return ctx[key]
	var out = []
	var lv = int(ctx["level"])
	var tr = int(ctx["trump"])
	if e != TRUMP or tr >= 0:
		for r in range(2, 15):
			if r != lv:
				out.append(r)
	if e == TRUMP:
		out.append(97)
		if tr >= 0:
			out.append(98)
		out.append(99)
		out.append(100)
	ctx[key] = out
	return out


static func idx(c: int, ctx: Dictionary) -> int:
	return ord_list(eff(c, ctx), ctx).find(strength(c, ctx))


static func suit_cards(cards: Array, e: int, ctx: Dictionary) -> Array:
	var out = []
	for c in cards:
		if eff(int(c), ctx) == e:
			out.append(int(c))
	return out


static func same_suit(cards: Array, ctx: Dictionary) -> bool:
	if cards.is_empty():
		return false
	var e = eff(int(cards[0]), ctx)
	for c in cards:
		if eff(int(c), ctx) != e:
			return false
	return true


# ---------------------------------------------------------------- 牌型拆分

## 把同一花色的牌拆成 拖拉机 / 对子 / 单张（优先拆出最长的拖拉机）
## 返回 {"tractors": [[对数, 顶端序号, 牌(从小到大)]], "pairs": [[序号, [牌,牌]]], "singles": [[序号, 牌]]}
static func decompose(cards: Array, ctx: Dictionary) -> Dictionary:
	var by_face = {}
	for c in cards:
		var f = int(c) % 54
		if not by_face.has(f):
			by_face[f] = []
		by_face[f].append(int(c))
	var pairs = []
	var singles = []
	for f in by_face:
		var arr = by_face[f]
		var i = idx(int(arr[0]), ctx)
		if arr.size() >= 2:
			pairs.append([i, [int(arr[0]), int(arr[1])]])
		else:
			singles.append([i, int(arr[0])])
	var used = []
	for k in pairs.size():
		used.append(false)
	var tractors = []
	while true:
		var present = {}
		for k in pairs.size():
			if not used[k]:
				var pv = int(pairs[k][0])
				if not present.has(pv):
					present[pv] = []
				present[pv].append(k)
		var best_start = -1
		var best_len = 1
		for pv in present:
			if present.has(pv - 1):
				continue
			var l = 1
			while present.has(pv + l):
				l += 1
			if l > best_len or (l == best_len and l >= 2 and pv > best_start):
				best_len = l
				best_start = pv
		if best_len < 2:
			break
		var tc = []
		for j in best_len:
			var k2 = int(present[best_start + j][0])
			used[k2] = true
			tc += pairs[k2][1]
		tractors.append([best_len, best_start + best_len - 1, tc])
	var rest = []
	for k in pairs.size():
		if not used[k]:
			rest.append(pairs[k])
	tractors.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	rest.sort_custom(func(a, b): return a[0] > b[0])
	singles.sort_custom(func(a, b): return a[0] > b[0])
	return {"tractors": tractors, "pairs": rest, "singles": singles}


static func total_pairs(d: Dictionary) -> int:
	var n = d["pairs"].size()
	for t in d["tractors"]:
		n += int(t[0])
	return n


static func max_tractor(d: Dictionary) -> int:
	if d["tractors"].is_empty():
		return 0
	return int(d["tractors"][0][0])


static func n_components(d: Dictionary) -> int:
	return d["tractors"].size() + d["pairs"].size() + d["singles"].size()


static func max_component_size(d: Dictionary) -> int:
	if not d["tractors"].is_empty():
		return 2 * int(d["tractors"][0][0])
	if not d["pairs"].is_empty():
		return 2
	return 1


static func pair_idxs(d: Dictionary) -> Array:
	var out = []
	for t in d["tractors"]:
		for j in int(t[0]):
			out.append(int(t[1]) - j)
	for p in d["pairs"]:
		out.append(int(p[0]))
	return out


static func describe(cards: Array, ctx: Dictionary) -> String:
	if cards.is_empty() or not same_suit(cards, ctx):
		return ""
	var d = decompose(cards, ctx)
	if n_components(d) > 1:
		return "甩牌"
	if not d["tractors"].is_empty():
		return "拖拉机"
	if not d["pairs"].is_empty():
		return "对子"
	return "单张"


# ---------------------------------------------------------------- 比大小

static func covers(d: Dictionary, ld: Dictionary) -> bool:
	return total_pairs(d) >= total_pairs(ld) and max_tractor(d) >= max_tractor(ld)


static func value_for(d: Dictionary, typ: String, l: int) -> int:
	var best = -1
	if typ == "tractor":
		for t in d["tractors"]:
			if int(t[0]) >= l:
				best = maxi(best, int(t[1]))
		return best
	for t in d["tractors"]:
		best = maxi(best, int(t[1]))
	for p in d["pairs"]:
		best = maxi(best, int(p[0]))
	if typ == "pair":
		return best
	for s in d["singles"]:
		best = maxi(best, int(s[0]))
	return best


## 这手牌在本轮的"大小"：[有效花色, 大小]；管不了的返回 [-1, -1]
static func play_value(play: Array, lead: Array, ctx: Dictionary) -> Array:
	if play.is_empty() or lead.is_empty():
		return [-1, -1]
	var s = eff(int(lead[0]), ctx)
	var e = eff(int(play[0]), ctx)
	for c in play:
		if eff(int(c), ctx) != e:
			return [-1, -1]
	if e != s and e != TRUMP:
		return [-1, -1]
	var ld = decompose(lead, ctx)
	var d = decompose(play, ctx)
	if not covers(d, ld):
		return [-1, -1]
	var l = max_tractor(ld)
	var typ = "single"
	if l >= 2:
		typ = "tractor"
	elif total_pairs(ld) > 0:
		typ = "pair"
	return [e, value_for(d, typ, l)]


static func better(a: Array, b: Array) -> bool:
	if int(a[0]) < 0:
		return false
	if int(b[0]) < 0:
		return true
	if int(a[0]) == TRUMP and int(b[0]) != TRUMP:
		return true
	return int(a[0]) == int(b[0]) and int(a[1]) > int(b[1])


# ---------------------------------------------------------------- 出牌合法性

## 跟牌检查：有同花色必须跟同花色；首家出对子/拖拉机时，有对子/拖拉机必须跟
static func check_follow(hand: Array, play: Array, lead: Array, ctx: Dictionary) -> String:
	var n = lead.size()
	if play.size() != n:
		return "这一轮要出 %d 张牌" % n
	var s = eff(int(lead[0]), ctx)
	var hs = suit_cards(hand, s, ctx)
	var ps = suit_cards(play, s, ctx)
	if ps.size() < mini(n, hs.size()):
		return "你还有%s，必须先出%s" % [suit_label(s), suit_label(s)]
	if hs.size() <= n:
		return ""
	var ld = decompose(lead, ctx)
	var hd = decompose(hs, ctx)
	var pd = decompose(ps, ctx)
	var lt = max_tractor(ld)
	if lt >= 2 and max_tractor(hd) >= lt and max_tractor(pd) < lt:
		return "你有拖拉机，必须跟拖拉机"
	if total_pairs(pd) < mini(total_pairs(ld), total_pairs(hd)):
		return "你有对子，必须跟对子"
	return ""


static func _has_chain(idxs: Array, l: int, above: int) -> bool:
	var seen = {}
	for x in idxs:
		seen[int(x)] = true
	for x in seen:
		if int(x) <= above:
			continue
		var ok = true
		for j in range(1, l):
			if not seen.has(int(x) - j):
				ok = false
				break
		if ok:
			return true
	return false


## 甩牌检查：每一部分都必须是其他三家管不上的；失败时返回要被迫打出的那一部分（最小的），成功返回 []
static func throw_fail(lead: Array, others: Array, ctx: Dictionary) -> Array:
	var d = decompose(lead, ctx)
	if n_components(d) <= 1:
		return []
	var s = eff(int(lead[0]), ctx)
	var fails = []
	for o in others:
		var oc = suit_cards(o, s, ctx)
		if oc.is_empty():
			continue
		var od = decompose(oc, ctx)
		var opairs = pair_idxs(od)
		var max_single = -1
		for c in oc:
			max_single = maxi(max_single, idx(int(c), ctx))
		for sg in d["singles"]:
			if max_single > int(sg[0]):
				fails.append([0, int(sg[0]), [int(sg[1])]])
		for p in d["pairs"]:
			for x in opairs:
				if int(x) > int(p[0]):
					fails.append([1, int(p[0]), p[1].duplicate()])
					break
		for t in d["tractors"]:
			if _has_chain(opairs, int(t[0]), int(t[1])):
				fails.append([2, int(t[1]), t[2].duplicate()])
	if fails.is_empty():
		return []
	fails.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return fails[0][2]


# ---------------------------------------------------------------- 提示 / 电脑AI

static func _face_counts(cards: Array) -> Dictionary:
	var cnt = {}
	for c in cards:
		var f = int(c) % 54
		cnt[f] = int(cnt.get(f, 0)) + 1
	return cnt


static func _pairs_in(cards: Array, ctx: Dictionary) -> Array:
	var by_face = {}
	for c in cards:
		var f = int(c) % 54
		if not by_face.has(f):
			by_face[f] = []
		by_face[f].append(int(c))
	var out = []
	for f in by_face:
		if by_face[f].size() >= 2:
			out.append([idx(int(by_face[f][0]), ctx), [by_face[f][0], by_face[f][1]]])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


static func _sorted_by(keyed: Array) -> Array:
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out = []
	for it in keyed:
		out.append(it[1])
	return out


## 同花色里挑单张的顺序：low = 小牌、非分、不拆对子优先；high = 大牌优先；feed = 分牌优先（给队友送分）
static func _single_order(cards: Array, ctx: Dictionary, mode: String) -> Array:
	var cnt = _face_counts(cards)
	var keyed = []
	for c in cards:
		var ci = int(c)
		var i = idx(ci, ctx)
		var p = points_of(ci)
		var pf = 1 if int(cnt[ci % 54]) >= 2 else 0
		var k = 0
		if mode == "high":
			k = -i * 10 + pf
		elif mode == "feed":
			k = (20 - p) * 10000 + pf * 1000 + i
		else:
			k = (1 if p > 0 else 0) * 10000 + pf * 1000 + i
		keyed.append([k, ci])
	return _sorted_by(keyed)


## 没有该花色时垫牌的顺序：副牌优先，主牌最后
static func _fill_order(cards: Array, ctx: Dictionary, mode: String) -> Array:
	var cnt = _face_counts(cards)
	var keyed = []
	for c in cards:
		var ci = int(c)
		var i = idx(ci, ctx)
		var p = points_of(ci)
		var pf = 1 if int(cnt[ci % 54]) >= 2 else 0
		var tf = 1 if eff(ci, ctx) == TRUMP else 0
		var k = 0
		if mode == "feed":
			k = tf * 1000000 + (20 - p) * 1000 + pf * 200 + i
		else:
			k = tf * 1000000 + (1 if p > 0 else 0) * 1000 + pf * 200 + i
		keyed.append([k, ci])
	return _sorted_by(keyed)


## 从同一花色的牌 pool 里挑出合法的跟牌（满足对子/拖拉机义务）
static func build_follow(pool: Array, lead: Array, ctx: Dictionary, mode: String) -> Array:
	var n = lead.size()
	if pool.size() <= n:
		return pool.duplicate()
	var ld = decompose(lead, ctx)
	var l = max_tractor(ld)
	var need_pairs = total_pairs(ld)
	var rem = pool.duplicate()
	var chosen = []
	var hi = mode == "high"
	if l >= 2:
		var pd = decompose(rem, ctx)
		var cand = []
		for t in pd["tractors"]:
			if int(t[0]) >= l:
				cand.append(t)
		if not cand.is_empty():
			cand.sort_custom(func(a, b): return a[1] < b[1])
			var t = cand[cand.size() - 1] if hi else cand[0]
			var tc = t[2]
			var m = int(t[0])
			var pick = tc.slice(2 * (m - l), 2 * m) if hi else tc.slice(0, 2 * l)
			for c in pick:
				chosen.append(int(c))
				rem.erase(int(c))
			need_pairs -= l
	if need_pairs > 0:
		var plist = _pairs_in(rem, ctx)
		if hi:
			plist.reverse()
		elif mode == "feed":
			plist.sort_custom(func(a, b): return sum_points(a[1]) > sum_points(b[1]) or (sum_points(a[1]) == sum_points(b[1]) and a[0] < b[0]))
		for p in plist:
			if need_pairs <= 0 or chosen.size() + 2 > n:
				break
			chosen += p[1]
			rem.erase(int(p[1][0]))
			rem.erase(int(p[1][1]))
			need_pairs -= 1
	var left = n - chosen.size()
	if left > 0:
		chosen += _single_order(rem, ctx, mode).slice(0, left)
	return chosen


## 完整的跟牌建议（包括没有该花色时垫牌）
static func follow_play(hand: Array, lead: Array, ctx: Dictionary, mode: String) -> Array:
	var n = lead.size()
	var s = eff(int(lead[0]), ctx)
	var hs = suit_cards(hand, s, ctx)
	if hs.size() >= n:
		return build_follow(hs, lead, ctx, mode)
	var others = []
	for c in hand:
		if not hs.has(int(c)):
			others.append(int(c))
	return hs + _fill_order(others, ctx, mode).slice(0, n - hs.size())


static func _plain_suits(ctx: Dictionary) -> Array:
	var out = []
	for s in 4:
		if s != int(ctx["trump"]):
			out.append(s)
	return out


## 首家出牌建议：副牌拖拉机 > 副牌A（或最大的牌）> 主多就出主 > 最短的副牌花色里的小牌
static func lead_suggest(hand: Array, ctx: Dictionary) -> Array:
	if hand.is_empty():
		return []
	var plain = _plain_suits(ctx)
	for e in plain:
		var d = decompose(suit_cards(hand, e, ctx), ctx)
		if not d["tractors"].is_empty():
			return d["tractors"][0][2].duplicate()
	for e in plain:
		var sc = suit_cards(hand, e, ctx)
		if sc.is_empty():
			continue
		var top = ord_list(e, ctx).size() - 1
		var d2 = decompose(sc, ctx)
		for p in d2["pairs"]:
			if int(p[0]) == top:
				return p[1].duplicate()
		for sg in d2["singles"]:
			if int(sg[0]) == top:
				return [int(sg[1])]
	var tr = suit_cards(hand, TRUMP, ctx)
	if tr.size() >= 12 or tr.size() == hand.size():
		var td = decompose(tr, ctx)
		if not td["tractors"].is_empty():
			return td["tractors"][0][2].duplicate()
		if not td["pairs"].is_empty():
			return td["pairs"][td["pairs"].size() - 1][1].duplicate()
		return [_single_order(tr, ctx, "low")[0]]
	var best_e = -1
	var best_n = 99
	for e in plain:
		var k = suit_cards(hand, e, ctx).size()
		if k > 0 and k < best_n:
			best_n = k
			best_e = e
	if best_e == -1:
		return [_single_order(tr, ctx, "low")[0]]
	return [_single_order(suit_cards(hand, best_e, ctx), ctx, "low")[0]]


## 扣底建议：扣短门的小副牌，尽量不扣分、不扣A、不拆对子，不扣主
static func bury_suggest(hand: Array, ctx: Dictionary) -> Array:
	var cnt = _face_counts(hand)
	var scount = {}
	for c in hand:
		var e = eff(int(c), ctx)
		scount[e] = int(scount.get(e, 0)) + 1
	var keyed = []
	for c in hand:
		var ci = int(c)
		var e = eff(ci, ctx)
		var i = idx(ci, ctx)
		var k = 0
		if e == TRUMP:
			k = 10000000 + i
		else:
			var top = ord_list(e, ctx).size() - 1
			k = (1 if points_of(ci) > 0 else 0) * 1000000 + (1 if i >= top - 1 else 0) * 500000
			k += (1 if int(cnt[ci % 54]) >= 2 else 0) * 100000 + int(scount[e]) * 1000 + i
		keyed.append([k, ci])
	return _sorted_by(keyed).slice(0, 8)


## 手牌显示顺序：主牌在左（从大到小），然后各门副牌
static func sort_display(cards: Array, ctx: Dictionary) -> Array:
	var tr = int(ctx["trump"])
	var order = [TRUMP]
	for s in 4:
		if s != tr:
			order.append(s)
	var keyed = []
	for c in cards:
		var ci = int(c)
		var g = order.find(eff(ci, ctx))
		var k = g * 1000000 + (500 - strength(ci, ctx)) * 100 + maxi(suit(ci), 0) * 10 + ci / 54
		keyed.append([k, ci])
	return _sorted_by(keyed)

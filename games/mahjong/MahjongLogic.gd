extends RefCounted
## 麻将（只在房主端运行），四人。三种玩法：
##   xuezhan 血战到底：108张（无字牌），不能吃，换三张（可关）、定缺，一家胡了其他人继续打，三家胡或摸完牌结束，摸完查花猪/查大叫
##   tuidao  广东推倒胡：136张，不能吃，可选只能自摸或可以点炮，抢杠胡，可选买马
##   dazhong 大众麻将：136张，能吃碰杠，可以点炮，有人胡就结束
## 计分：胡牌得 2^番 分（有封顶）；自摸每家付，点炮由放炮的人付
## 杠分立即结算：暗杠每家付2，补杠每家付1，直杠放杠的人付2

const M = preload("res://games/mahjong/MjRules.gd")
const MODE_NAMES = {"xuezhan": "血战到底", "tuidao": "广东推倒胡", "dazhong": "大众麻将"}

var rules = {}
var mode = "xuezhan"
var n_types = 27
var round_no = 1
var dealer = 0
var wall = []
var hands = []
var melds = []
var discards = []
var que = []
var won = []
var wins = []
var scores = []
var phase = "turn"
var turn = 0
var drawn = -1
var after_gang = false
var last_discard = {}
var claim_queue = []
var claim_opts = []
var claim_hu = []
var claim_ctx = {}
var exch_pick = []
var exch_dir = 0
var ma = []
var ma_hits = 0
var over = false
var cap_fan = 4
var allow_pao = true
var use_huan = false
var ma_n = 0
var checks = []
var event = ""
var _no_haidi = false


func _lbl(s: int) -> String:
	return "座位%d" % (s + 1)


func _four(v) -> Array:
	var a = []
	for i in 4:
		a.append(v.duplicate() if typeof(v) == TYPE_ARRAY else v)
	return a


func setup(_players: Array, game_rules: Dictionary, rn: int) -> void:
	rules = game_rules.duplicate(true)
	mode = str(rules.get("mode", "xuezhan"))
	if not MODE_NAMES.has(mode):
		mode = "xuezhan"
	n_types = 27 if mode == "xuezhan" else 34
	var cp = str(rules.get("cap", "4"))
	cap_fan = int(cp) if cp.is_valid_int() else 99
	allow_pao = mode != "tuidao" or str(rules.get("pao", "zimo")) == "pao"
	use_huan = mode == "xuezhan" and str(rules.get("huan", "on")) == "on"
	var mv = str(rules.get("ma", "0"))
	ma_n = int(mv) if mode == "tuidao" and mv.is_valid_int() else 0
	round_no = maxi(rn, 1)
	dealer = (round_no - 1) % 4
	wall = []
	for t in n_types:
		for k in 4:
			wall.append(t * 4 + k)
	wall.shuffle()
	hands = _four([])
	melds = _four([])
	discards = _four([])
	exch_pick = _four([])
	que = _four(-1)
	won = _four(false)
	scores = _four(0)
	wins = []
	checks = []
	ma = []
	ma_hits = 0
	over = false
	last_discard = {}
	after_gang = false
	drawn = -1
	_clear_claims()
	for r in 13:
		for k in 4:
			hands[(dealer + k) % 4].append(wall.pop_front())
	var extra = wall.pop_front()
	hands[dealer].append(extra)
	for s in 4:
		hands[s].sort()
	turn = dealer
	if use_huan:
		phase = "exchange"
		event = "发牌完成，请每人选3张同一花色的牌换出去（%s先选）" % _lbl(dealer)
	elif mode == "xuezhan":
		phase = "dingque"
		event = "发牌完成，请定缺"
	else:
		phase = "turn"
		drawn = extra
		event = "发牌完成，%s（庄家）先出牌" % _lbl(dealer)


func _clear_claims() -> void:
	claim_queue = []
	claim_opts = []
	claim_hu = []
	claim_ctx = {}


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	return turn


func bot_delay() -> float:
	return 0.5 if phase == "claim" else 0.7


# ---------------------------------------------------------------- 工具

func _cnt(s: int) -> Array:
	return M.counts_of(hands[s])


func _is_que_t(s: int, t: int) -> bool:
	return mode == "xuezhan" and int(que[s]) >= 0 and M.tsuit(t) == int(que[s])


func _has_que(s: int) -> bool:
	if mode != "xuezhan" or int(que[s]) < 0:
		return false
	for i in hands[s]:
		if M.tsuit(int(i) / 4) == int(que[s]):
			return true
	return false


func _can_win_with(s: int, t: int) -> bool:
	if won[s]:
		return false
	if mode == "xuezhan":
		if t >= 0 and _is_que_t(s, t):
			return false
		if _has_que(s):
			return false
	var c = _cnt(s)
	if t >= 0:
		c[t] += 1
	return M.is_win(c, melds[s].size(), true, mode != "xuezhan")


func _next_active(from: int) -> int:
	for k in range(1, 5):
		var s = (from + k) % 4
		if not won[s]:
			return s
	return from


func _others_alive(s: int) -> Array:
	var out = []
	for o in 4:
		if o != s and not won[o]:
			out.append(o)
	return out


func _pay(to: int, from: int, amount: int) -> void:
	scores[from] -= amount
	scores[to] += amount


func _take(s: int, t: int, n: int) -> Array:
	var out = []
	for i in range(hands[s].size() - 1, -1, -1):
		if out.size() >= n:
			break
		if int(hands[s][i]) / 4 == t:
			out.append(int(hands[s][i]))
	for i in out:
		hands[s].erase(i)
	return out


func _self_opts(s: int) -> Dictionary:
	var hu = hands[s].size() % 3 == 2 and _can_win_with(s, -1)
	var gangs = []
	if not wall.is_empty() and hands[s].size() % 3 == 2:
		var c = _cnt(s)
		for t in n_types:
			if int(c[t]) == 4 and not _is_que_t(s, t):
				gangs.append(t)
		for m in melds[s]:
			if str(m["k"]) == "peng":
				var t2 = int(m["tiles"][0]) / 4
				if int(c[t2]) >= 1 and not gangs.has(t2):
					gangs.append(t2)
	return {"hu": hu, "gangs": gangs}


func _discard_ok(s: int, id: int) -> bool:
	if not hands[s].has(id):
		return false
	if _has_que(s) and M.tsuit(id / 4) != int(que[s]):
		return false
	return true


# ---------------------------------------------------------------- 流程

func _start_turn(s: int, draw: bool) -> void:
	_clear_claims()
	phase = "turn"
	turn = s
	drawn = -1
	after_gang = false
	if draw:
		if wall.is_empty():
			_end_wall()
			return
		var tile = wall.pop_front()
		hands[s].append(tile)
		drawn = tile


func _gang_draw(s: int) -> void:
	_clear_claims()
	if wall.is_empty():
		_end_wall()
		return
	var tile = wall.pop_back()
	hands[s].append(tile)
	drawn = tile
	after_gang = true
	phase = "turn"
	turn = s


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	if seat != turn:
		return "还没轮到你"
	var t = str(a.get("type", ""))
	if phase == "exchange":
		if t != "exchange":
			return "请先选3张同一花色的牌换出去"
		return _apply_exchange(seat, a.get("tiles", []))
	if phase == "dingque":
		if t != "que":
			return "请先定缺"
		return _apply_que(seat, int(a.get("suit", -1)))
	if phase == "turn":
		if t == "hu":
			return _apply_zimo(seat)
		if t == "gang":
			return _apply_self_gang(seat, int(a.get("t", -1)))
		if t == "discard":
			return _apply_discard(seat, int(a.get("tile", -1)))
		return "现在请出牌"
	if phase == "claim":
		if t != "claim":
			return "请选择 碰/杠/胡/过"
		return _apply_claim(seat, a)
	return "无效操作"


func _apply_exchange(s: int, raw) -> String:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		return "请选3张牌"
	var ids = []
	var su = -1
	for i in raw:
		var id = int(i)
		if ids.has(id) or not hands[s].has(id):
			return "选的牌不对"
		var ts = M.tsuit(id / 4)
		if su == -1:
			su = ts
		elif ts != su:
			return "换三张必须是同一花色"
		ids.append(id)
	for id in ids:
		hands[s].erase(id)
	exch_pick[s] = ids
	event = "%s 选好了换三张" % _lbl(s)
	for o in 4:
		if exch_pick[o].size() != 3:
			turn = (s + 1) % 4
			return ""
	exch_dir = randi_range(1, 3)
	for o in 4:
		hands[(o + exch_dir) % 4] += exch_pick[o]
	for o in 4:
		hands[o].sort()
	var dn = {1: "换给下家", 2: "和对家互换", 3: "换给上家"}[exch_dir]
	phase = "dingque"
	turn = dealer
	event = "换三张完成（%s），请定缺" % dn
	return ""


func _apply_que(s: int, su: int) -> String:
	if su < 0 or su > 2:
		return "请选万、条或筒"
	que[s] = su
	for o in 4:
		if int(que[o]) < 0:
			turn = (s + 1) % 4
			event = "%s 定缺好了" % _lbl(s)
			return ""
	var parts = []
	for o in 4:
		parts.append("%s缺%s" % [_lbl(o), M.SUIT_CH[int(que[o])]])
	_start_turn(dealer, false)
	event = "定缺完成：%s。%s先出牌" % ["，".join(PackedStringArray(parts)), _lbl(dealer)]
	return ""


func _apply_zimo(s: int) -> String:
	if not _self_opts(s)["hu"]:
		return "现在还不能胡"
	var tile = drawn if drawn >= 0 and hands[s].has(drawn) else int(hands[s][hands[s].size() - 1])
	_record_win(s, tile, true, -1, false, false)
	_after_wins(s)
	return ""


func _apply_self_gang(s: int, t: int) -> String:
	if not _self_opts(s)["gangs"].has(t):
		return "不能杠这张牌"
	var c = _cnt(s)
	if int(c[t]) == 4:
		var ids = _take(s, t, 4)
		melds[s].append({"k": "agang", "tiles": ids, "from": s})
		for o in _others_alive(s):
			_pay(s, o, 2)
		event = "%s 暗杠" % _lbl(s)
		_gang_draw(s)
		return ""
	var id = M._id_of(hands[s], t)
	var robbers = []
	for k in range(1, 4):
		var o = (s + k) % 4
		if _can_win_with(o, t):
			robbers.append({"seat": o, "opts": [{"act": "hu"}]})
	if not robbers.is_empty():
		claim_ctx = {"kind": "rob", "seat": s, "tile": id, "t": t}
		claim_queue = robbers
		claim_hu = []
		phase = "claim"
		event = "%s 补杠 %s" % [_lbl(s), M.tname(t)]
		_ask_next()
		return ""
	_complete_bugang(s, id)
	return ""


func _complete_bugang(s: int, id: int) -> void:
	var t = id / 4
	hands[s].erase(id)
	for m in melds[s]:
		if str(m["k"]) == "peng" and int(m["tiles"][0]) / 4 == t:
			m["k"] = "bgang"
			m["tiles"].append(id)
			break
	for o in _others_alive(s):
		_pay(s, o, 1)
	event = "%s 补杠 %s" % [_lbl(s), M.tname(t)]
	_gang_draw(s)


func _apply_discard(s: int, id: int) -> String:
	if not hands[s].has(id):
		return "你没有这张牌"
	if not _discard_ok(s, id):
		return "要先把缺的那门（%s）打完" % M.SUIT_CH[int(que[s])]
	hands[s].erase(id)
	hands[s].sort()
	discards[s].append(id)
	last_discard = {"seat": s, "tile": id, "gang_pao": after_gang}
	after_gang = false
	drawn = -1
	event = "%s 打出 %s" % [_lbl(s), M.tname(id / 4)]
	_build_claims(s, id)
	return ""


func _build_claims(d: int, id: int) -> void:
	var t = id / 4
	var tier_hu = []
	var tier_pg = []
	var tier_chi = []
	for k in range(1, 4):
		var s = (d + k) % 4
		if won[s]:
			continue
		var opts = []
		var has_hu = allow_pao and _can_win_with(s, t)
		if has_hu:
			opts.append({"act": "hu"})
		var has_pg = false
		if not _is_que_t(s, t):
			var c = _cnt(s)
			if int(c[t]) >= 2:
				opts.append({"act": "peng"})
				has_pg = true
			if int(c[t]) >= 3 and not wall.is_empty():
				opts.append({"act": "gang"})
			if mode == "dazhong" and s == _next_active(d) and t < 27:
				var n = t % 9
				var combos = []
				if n >= 2:
					combos.append([t - 2, t - 1])
				if n >= 1 and n <= 7:
					combos.append([t - 1, t + 1])
				if n <= 6:
					combos.append([t + 1, t + 2])
				for cb in combos:
					if int(c[cb[0]]) > 0 and int(c[cb[1]]) > 0:
						opts.append({"act": "chi", "use": cb})
		if opts.is_empty():
			continue
		var e = {"seat": s, "opts": opts}
		if has_hu:
			tier_hu.append(e)
		elif has_pg:
			tier_pg.append(e)
		else:
			tier_chi.append(e)
	var q = tier_hu + tier_pg + tier_chi
	if q.is_empty():
		_start_turn(_next_active(d), true)
		return
	claim_ctx = {"kind": "discard", "seat": d, "tile": id, "t": t}
	claim_queue = q
	claim_hu = []
	phase = "claim"
	_ask_next()


func _ask_next() -> void:
	while not claim_queue.is_empty():
		var e = claim_queue.pop_front()
		var opts = e["opts"]
		if not claim_hu.is_empty():
			var only = []
			for o in opts:
				if str(o["act"]) == "hu":
					only.append(o)
			if only.is_empty():
				continue
			opts = only
		turn = int(e["seat"])
		claim_opts = opts
		return
	_resolve_claims()


func _resolve_claims() -> void:
	var ctx = claim_ctx
	if not claim_hu.is_empty():
		var hus = claim_hu.duplicate()
		var id = int(ctx["tile"])
		var from = int(ctx["seat"])
		var rob = str(ctx["kind"]) == "rob"
		var gp = not rob and bool(last_discard.get("gang_pao", false))
		for s in hus:
			_record_win(int(s), id, false, from, rob, gp)
		if rob:
			hands[from].erase(id)
		else:
			discards[from].erase(id)
		hands[int(hus[0])].append(id)
		_after_wins(int(hus[hus.size() - 1]))
		return
	if str(ctx.get("kind", "")) == "rob":
		_complete_bugang(int(ctx["seat"]), int(ctx["tile"]))
	else:
		_start_turn(_next_active(int(ctx["seat"])), true)


func _apply_claim(s: int, a: Dictionary) -> String:
	var act = str(a.get("act", ""))
	if act == "pass":
		_ask_next()
		return ""
	var ok = false
	for o in claim_opts:
		if str(o["act"]) != act:
			continue
		if act == "chi":
			var use = a.get("use", [])
			if typeof(use) == TYPE_ARRAY and use.size() == 2 and int(use[0]) == int(o["use"][0]) and int(use[1]) == int(o["use"][1]):
				ok = true
		else:
			ok = true
	if not ok:
		return "现在不能这样做"
	var t = int(claim_ctx["t"])
	var id = int(claim_ctx["tile"])
	var d = int(claim_ctx["seat"])
	if act == "hu":
		claim_hu.append(s)
		if mode != "xuezhan":
			claim_queue = []
		_ask_next()
		return ""
	if act == "peng":
		var ids = _take(s, t, 2)
		discards[d].erase(id)
		ids.append(id)
		melds[s].append({"k": "peng", "tiles": ids, "from": d})
		_start_turn(s, false)
		event = "%s 碰 %s" % [_lbl(s), M.tname(t)]
		return ""
	if act == "gang":
		var ids2 = _take(s, t, 3)
		discards[d].erase(id)
		ids2.append(id)
		melds[s].append({"k": "mgang", "tiles": ids2, "from": d})
		_pay(s, d, 2)
		event = "%s 杠 %s" % [_lbl(s), M.tname(t)]
		_gang_draw(s)
		return ""
	if act == "chi":
		var use2 = a["use"]
		var ids3 = _take(s, int(use2[0]), 1) + _take(s, int(use2[1]), 1)
		discards[d].erase(id)
		ids3.append(id)
		ids3.sort()
		melds[s].append({"k": "chi", "tiles": ids3, "from": d})
		_start_turn(s, false)
		event = "%s 吃 %s" % [_lbl(s), M.tname(t)]
		return ""
	return "无效操作"


# ---------------------------------------------------------------- 胡牌与计分

func _fans(s: int, c: Array, zimo: bool, rob: bool, gang_pao: bool, flower: bool) -> Array:
	var out = []
	var ms = melds[s]
	var ex = ms.size()
	var tot = c.duplicate()
	var open = false
	var all_pung = true
	for m in ms:
		var k = str(m["k"])
		for i in m["tiles"]:
			tot[int(i) / 4] += 1
		if k != "agang":
			open = true
		if k == "chi":
			all_pung = false
	var seven = false
	if ex == 0 and mode != "xuezhan" and M.is_kokushi(c):
		out.append(["十三幺", 5])
	elif ex == 0 and M.is_seven_pairs(c):
		seven = true
		var g4 = 0
		for v in c:
			if int(v) == 4:
				g4 += 1
		if g4 > 0:
			out.append(["龙七对", 3])
		else:
			out.append(["七对", 2])
	elif all_pung and M.is_all_triplets(c):
		out.append(["对对胡", 1])
	if mode == "xuezhan" and M.total(c) == 2:
		out.append(["金钩钓", 1])
	var suits = {}
	var honors = false
	for t in 34:
		if int(tot[t]) > 0:
			if t >= 27:
				honors = true
			else:
				suits[t / 9] = true
	if not out.is_empty() and str(out[0][0]) == "十三幺":
		pass
	elif suits.is_empty() and honors:
		out.append(["字一色", 3])
	elif suits.size() == 1 and not honors:
		out.append(["清一色", 2])
	elif suits.size() == 1 and honors:
		out.append(["混一色", 1])
	if mode == "xuezhan":
		var roots = 0
		for v in tot:
			if int(v) == 4:
				roots += 1
		if seven and roots > 0:
			roots -= 1
		if roots > 0:
			out.append(["根×%d" % roots, roots])
	if mode == "dazhong" and not open:
		out.append(["门清", 1])
	if flower:
		out.append(["杠上开花", 1])
	if gang_pao:
		out.append(["杠上炮", 1])
	if rob:
		out.append(["抢杠胡", 1])
	if wall.is_empty() and not _no_haidi:
		out.append(["海底捞月" if zimo else "海底炮", 1])
	if zimo and mode != "tuidao":
		out.append(["自摸", 1])
	if out.is_empty():
		out.append(["鸡胡" if mode == "tuidao" else "平胡", 0])
	return out


func _fan_total(fans: Array) -> int:
	var f = 0
	for x in fans:
		f += int(x[1])
	return mini(f, cap_fan)


func _record_win(s: int, id: int, zimo: bool, from: int, rob: bool, gang_pao: bool) -> void:
	var t = id / 4
	var c = _cnt(s)
	if not zimo:
		c[t] += 1
	var fans = _fans(s, c, zimo, rob, gang_pao, zimo and after_gang)
	var fan = _fan_total(fans)
	var pts = 1 << mini(fan, 20)
	var hits = 0
	var mtiles = []
	if ma_n > 0:
		for k in mini(ma_n, wall.size()):
			var m = int(wall.pop_back())
			mtiles.append(m)
			var mt = m / 4
			var v = (mt - 27) if mt >= 27 else (mt % 9)
			if v % 4 == 0:
				hits += 1
		ma += mtiles
		ma_hits += hits
	var mult = 1 + hits
	var payers = _others_alive(s) if zimo else [from]
	for p in payers:
		_pay(s, int(p), pts * mult)
	won[s] = true
	wins.append({"seat": s, "tile": t, "zimo": zimo, "from": from, "fans": fans, "fan": fan, "pts": pts * mult, "payers": payers.size(), "ma": mtiles, "hits": hits, "order": wins.size() + 1})
	var names = []
	for x in fans:
		names.append(str(x[0]))
	var how = "自摸" if zimo else "胡了%s打出的" % _lbl(from)
	if rob:
		how = "抢%s的杠" % _lbl(from)
	event = "%s %s%s！%s，%d番" % [_lbl(s), how, M.tname(t), "、".join(PackedStringArray(names)), fan]
	if ma_n > 0:
		event += "，买马中%d匹" % hits


func _after_wins(last: int) -> void:
	_clear_claims()
	if mode != "xuezhan":
		_end_round()
		return
	var alive = 0
	for s in 4:
		if not won[s]:
			alive += 1
	if alive <= 1:
		_end_round()
		return
	var ev = event
	_start_turn(_next_active(last), true)
	if not over:
		event = ev


func _end_wall() -> void:
	if mode == "xuezhan":
		_cha_jiao()
	_end_round()


func _cha_jiao() -> void:
	var alive = []
	for s in 4:
		if not won[s]:
			alive.append(s)
	if alive.size() < 2:
		return
	var hz = []
	var ting = {}
	_no_haidi = true
	for s in alive:
		if _has_que(s):
			hz.append(s)
			continue
		var bestf = -1
		var c = _cnt(s)
		for t in n_types:
			if _can_win_with(s, t):
				c[t] += 1
				bestf = maxi(bestf, _fan_total(_fans(s, c, false, false, false, false)))
				c[t] -= 1
		if bestf >= 0:
			ting[s] = bestf
	_no_haidi = false
	var cap_pts = 1 << mini(cap_fan, 6)
	for h in hz:
		for o in alive:
			if o != h and not hz.has(o):
				_pay(o, h, cap_pts)
		checks.append("%s 是花猪（还有缺门的牌），赔每家%d分" % [_lbl(h), cap_pts])
	for s in alive:
		if hz.has(s) or ting.has(s):
			continue
		for o in ting:
			_pay(int(o), s, 1 << int(ting[o]))
		if not ting.is_empty():
			checks.append("%s 没听牌，被查大叫" % _lbl(s))
	for o in ting:
		checks.append("%s 听牌" % _lbl(int(o)))


func _end_round() -> void:
	over = true
	phase = "done"
	turn = -1
	_clear_claims()
	if wins.is_empty():
		event = "流局：牌摸完了，没有人胡"
	else:
		var parts = []
		for w in wins:
			parts.append("%s%s胡（%d番）" % [_lbl(int(w["seat"])), "自摸" if bool(w["zimo"]) else "", int(w["fan"])])
		event = "本局结束：" + "，".join(PackedStringArray(parts))
	if not checks.is_empty():
		event += "。" + "；".join(PackedStringArray(checks))


func winners() -> Array:
	var out = []
	for w in wins:
		out.append(int(w["seat"]))
	return out


func round_scores() -> Array:
	return scores.duplicate()


# ---------------------------------------------------------------- 状态

func get_state() -> Dictionary:
	return get_state_for(-1)


func _sorted(ids: Array) -> Array:
	var a = ids.duplicate()
	a.sort()
	return a


func get_state_for(v: int) -> Dictionary:
	var counts = []
	for s in 4:
		counts.append(hands[s].size())
	var my = []
	var my_drawn = -1
	if v >= 0 and v < 4:
		my = _sorted(hands[v])
		if v == turn and phase == "turn" and drawn >= 0 and my.has(drawn):
			my.erase(drawn)
			my_drawn = drawn
	var shown_que = que.duplicate()
	if phase == "dingque":
		for s in 4:
			if s != v:
				shown_que[s] = -1 if int(que[s]) < 0 else -2
	var reveal = []
	for s in 4:
		if over or (mode == "xuezhan" and won[s]):
			reveal.append(_sorted(hands[s]))
		else:
			reveal.append([])
	var opts = {}
	var copts = []
	var cur = current_seat()
	if v >= 0 and v == turn and not over:
		if phase == "turn":
			opts = _self_opts(v)
		elif phase == "claim":
			copts = claim_opts.duplicate(true)
	if phase == "claim" and v != turn:
		cur = -1
	var ting = []
	if v >= 0 and v < 4 and not won[v] and hands[v].size() % 3 == 1 and (phase == "turn" or phase == "claim"):
		for t in n_types:
			if _can_win_with(v, t):
				ting.append(t)
	return {
		"mode": mode,
		"mode_name": MODE_NAMES[mode],
		"phase": phase,
		"current_seat": cur,
		"dealer": dealer,
		"wall": wall.size(),
		"counts": counts,
		"my_hand": my,
		"drawn": my_drawn,
		"melds": melds.duplicate(true),
		"discards": discards.duplicate(true),
		"last_discard": last_discard.duplicate(),
		"que": shown_que,
		"won": won.duplicate(),
		"wins": wins.duplicate(true),
		"reveal": reveal,
		"opts": opts,
		"claim": copts,
		"claim_tile": int(claim_ctx.get("t", -1)) if phase == "claim" and v == turn else -1,
		"claim_from": int(claim_ctx.get("seat", -1)) if phase == "claim" and v == turn else -1,
		"claim_kind": str(claim_ctx.get("kind", "")) if phase == "claim" and v == turn else "",
		"picked": v >= 0 and v < 4 and exch_pick[v].size() == 3,
		"ting": ting,
		"scores": scores.duplicate(),
		"checks": checks.duplicate(),
		"ma": ma.duplicate(),
		"ma_hits": ma_hits,
		"over": over,
		"winners": winners(),
		"event": event,
	}


# ---------------------------------------------------------------- 电脑 AI / 超时

func _ai_counts(s: int) -> Array:
	var c = _cnt(s)
	if mode == "xuezhan" and int(que[s]) >= 0:
		var q = int(que[s])
		for t in range(q * 9, q * 9 + 9):
			c[t] = 0
	return c


func timeout_action(s: int) -> Dictionary:
	if phase == "claim":
		for o in claim_opts:
			if str(o["act"]) == "hu":
				return {"type": "claim", "act": "hu"}
		return {"type": "claim", "act": "pass"}
	if phase == "turn":
		if _self_opts(s)["hu"]:
			return {"type": "hu"}
		if drawn >= 0 and _discard_ok(s, drawn):
			return {"type": "discard", "tile": drawn}
	return {}


func bot_action(s: int) -> Dictionary:
	if over:
		return {}
	if phase == "exchange":
		return {"type": "exchange", "tiles": M.suggest_exchange(hands[s])}
	if phase == "dingque":
		return {"type": "que", "suit": M.suggest_que(hands[s])}
	var ex = melds[s].size()
	if phase == "claim":
		var acts = {}
		for o in claim_opts:
			acts[str(o["act"])] = true
		if acts.has("hu"):
			return {"type": "claim", "act": "hu"}
		var c = _ai_counts(s)
		var cur = M.shanten(c, ex, ex == 0)
		var t = int(claim_ctx["t"])
		if acts.has("gang"):
			c[t] -= 3
			var sg = M.shanten(c, ex + 1, false)
			c[t] += 3
			if sg <= cur:
				return {"type": "claim", "act": "gang"}
		if acts.has("peng"):
			c[t] -= 2
			var sp = M.shanten(c, ex + 1, false)
			c[t] += 2
			if sp < cur or (sp == cur and t >= 27):
				return {"type": "claim", "act": "peng"}
		for o in claim_opts:
			if str(o["act"]) == "chi":
				var u = o["use"]
				c[int(u[0])] -= 1
				c[int(u[1])] -= 1
				var sc = M.shanten(c, ex + 1, false)
				c[int(u[0])] += 1
				c[int(u[1])] += 1
				if sc < cur:
					return {"type": "claim", "act": "chi", "use": [int(u[0]), int(u[1])]}
		return {"type": "claim", "act": "pass"}
	if phase == "turn":
		var so = _self_opts(s)
		if so["hu"]:
			return {"type": "hu"}
		var c2 = _ai_counts(s)
		var base = M.shanten(c2, ex, ex == 0)
		for g in so["gangs"]:
			var gt = int(g)
			if int(c2[gt]) >= 4:
				c2[gt] -= 4
				var s4 = M.shanten(c2, ex + 1, false)
				c2[gt] += 4
				if s4 <= base:
					return {"type": "gang", "t": gt}
			else:
				return {"type": "gang", "t": gt}
		var q = int(que[s]) if mode == "xuezhan" else -1
		var id = M.suggest_discard(hands[s], ex, q, n_types)
		return {"type": "discard", "tile": id}
	return {}

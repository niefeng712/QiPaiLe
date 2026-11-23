extends RefCounted
## 中国象棋（只在房主端运行）：红先黑后；对方无棋可走（被将死或困毙）就输；超过 MAX_PLIES 步判和
## 玩法开关：first 谁执红（每局轮换/座位1/随机）；level 电脑难度 easy/normal/hard

const X = preload("res://games/xiangqi/XqRules.gd")
const MAX_PLIES = 300
const LEVELS = {"easy": [2, 2000], "normal": [3, 7000], "hard": [4, 18000]}

var board = []
var red_seat = 0
var black_seat = 1
var side = 1
var plies = 0
var last = []
var check = false
var over = false
var draw = false
var winner = -1
var resigned = false
var captured = {"1": [], "-1": []}
var level = "normal"
var event = ""


func setup(players: Array, rules: Dictionary, rn: int) -> void:
	var a = int(players[0])
	var b = int(players[1])
	var first = str(rules.get("first", "alternate"))
	var swap = false
	if first == "random":
		swap = randi() % 2 == 1
	elif first == "alternate":
		swap = rn % 2 == 0
	red_seat = b if swap else a
	black_seat = a if swap else b
	level = str(rules.get("level", "normal"))
	if not LEVELS.has(level):
		level = "normal"
	board = X.initial()
	side = 1
	plies = 0
	last = []
	check = false
	over = false
	draw = false
	winner = -1
	resigned = false
	captured = {"1": [], "-1": []}
	event = "游戏开始，红方先走"


func _seat_of(sg: int) -> int:
	return red_seat if sg > 0 else black_seat


func _side_of(seat: int) -> int:
	if seat == red_seat:
		return 1
	if seat == black_seat:
		return -1
	return 0


func is_over() -> bool:
	return over


func current_seat() -> int:
	if over:
		return -1
	return _seat_of(side)


func bot_delay() -> float:
	return 0.3


func apply(seat: int, a: Dictionary) -> String:
	if over:
		return "本局已结束"
	var t = str(a.get("type", ""))
	if t == "resign":
		var sg = _side_of(seat)
		if sg == 0:
			return "你不在对局中"
		over = true
		resigned = true
		winner = _seat_of(-sg)
		event = "%s认输，%s获胜" % ["红方" if sg > 0 else "黑方", "黑方" if sg > 0 else "红方"]
		return ""
	if seat != current_seat():
		return "还没轮到你"
	if t != "move":
		return "无效操作"
	var f = int(a.get("from", -1))
	var to = int(a.get("to", -1))
	if f < 0 or f >= 90 or to < 0 or to >= 90:
		return "位置无效"
	var p = int(board[f])
	if p == 0 or (p > 0) != (side > 0):
		return "请选择自己的棋子"
	if not X.legal_from(board, side, f).has(to):
		return "这步棋不合规则（可能会被将军）"
	var cap = int(board[to])
	board[to] = p
	board[f] = 0
	last = [f, to]
	plies += 1
	var who = "红方" if side > 0 else "黑方"
	event = "%s %s" % [who, X.piece_name(p)]
	if cap != 0:
		captured[str(side)].append(cap)
		event += " 吃 %s" % X.piece_name(cap)
	side = -side
	check = X.in_check(board, side)
	if X.legal(board, side).is_empty():
		over = true
		winner = _seat_of(-side)
		event += "，%s！%s获胜" % ["绝杀" if check else "困毙（无棋可走）", who]
		return ""
	if check:
		event += "，将军！"
	if plies >= MAX_PLIES:
		over = true
		draw = true
		event += "。已走满%d回合，判和棋" % (MAX_PLIES / 2)
	return ""


func get_state() -> Dictionary:
	return {
		"board": board.duplicate(),
		"red_seat": red_seat,
		"black_seat": black_seat,
		"side": side,
		"current_seat": current_seat(),
		"last": last.duplicate(),
		"check": check,
		"plies": plies,
		"captured": captured.duplicate(true),
		"over": over,
		"draw": draw,
		"winners": [winner] if winner >= 0 else [],
		"event": event,
	}


func bot_action(seat: int) -> Dictionary:
	if over:
		return {}
	var lv = LEVELS[level]
	var m = X.best_move(board, side, int(lv[0]), int(lv[1]))
	if m.is_empty():
		return {}
	return {"type": "move", "from": int(m[0]), "to": int(m[1])}

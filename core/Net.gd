extends Node
## 棋牌乐 网络与房间核心（自动加载单例 Net）
## - 局域网 UDP 广播：房主每秒广播房间信息，大厅监听后自动显示房间列表（免输IP）
## - ENet 房间连接：房主兼做服务器，所有规则判定都在房主端完成（状态同步）
## - 单机模式：不开网络，在本机跑同一套房间/规则逻辑，空位由电脑补齐
## - 掉线托管：游戏中有人掉线由电脑接管，用同一昵称重新加入即可继续

const Registry = preload("res://core/GameRegistry.gd")

const PROTOCOL = 1
const DISCOVERY_PORT = 47800
const GAME_PORT = 47801
const MAGIC = "QIPAILE1"
const MAX_CLIENTS = 8

signal rooms_updated(found_rooms)
signal room_changed(new_room)
signal state_changed(new_state)
signal toast(text)
signal left_room(reason)

var mode = "none"  # none / offline / host / client
var my_peer = 0
var player_name = "玩家"
var room = {}
var state = {}

var _logic = null
var _round = 0
var _tallied = false
var _timeouts = {}
var _bot_token = 0
var _enet = null
var _reject_reason = ""

var _listen_udp = null
var _bc_udp = null
var _bc_accum = 0.0
var _found = {}
var _found_accum = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_poll_discovery(delta)
	if mode == "host" and _bc_udp != null:
		_bc_accum += delta
		if _bc_accum >= 1.0:
			_bc_accum = 0.0
			_send_beacon()


# ---------------------------------------------------------------- 工具

func local_ipv4() -> Array:
	var out = []
	for a in IP.get_local_addresses():
		var s = str(a)
		if s.find(":") != -1:
			continue
		if s.begins_with("127.") or s.begins_with("169.254.") or s == "0.0.0.0":
			continue
		if not out.has(s):
			out.append(s)
	return out


func is_host() -> bool:
	return mode == "host" or mode == "offline"


func my_seat() -> int:
	var seats = room.get("seats", [])
	for i in seats.size():
		if str(seats[i]["kind"]) == "human" and int(seats[i]["peer"]) == my_peer:
			return i
	return -1


func seat_names() -> Array:
	var out = []
	for s in room.get("seats", []):
		if str(s["kind"]) == "empty":
			out.append("空位")
		else:
			out.append(str(s["name"]))
	return out


func _empty_seat() -> Dictionary:
	return {"kind": "empty", "peer": 0, "name": "", "away": ""}


func _bot_seat(i: int) -> Dictionary:
	return {"kind": "bot", "peer": 0, "name": "电脑%d" % (i + 1), "away": ""}


func _filled_count() -> int:
	var n = 0
	for s in room.get("seats", []):
		if str(s["kind"]) != "empty":
			n += 1
	return n


# ---------------------------------------------------------------- 局域网房间发现

func start_discovery() -> void:
	if _listen_udp != null:
		return
	_listen_udp = PacketPeerUDP.new()
	var err = _listen_udp.bind(DISCOVERY_PORT)
	if err != OK:
		_listen_udp = null
		toast.emit("无法监听局域网房间广播（端口 %d 被占用），可以用IP直接加入" % DISCOVERY_PORT)
		return
	_found.clear()
	_found_accum = 1.0


func stop_discovery() -> void:
	if _listen_udp != null:
		_listen_udp.close()
		_listen_udp = null
	_found.clear()


func _poll_discovery(delta: float) -> void:
	if _listen_udp == null:
		return
	while _listen_udp.get_available_packet_count() > 0:
		var pkt = _listen_udp.get_packet()
		var ip = _listen_udp.get_packet_ip()
		var data = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY and str(data.get("magic", "")) == MAGIC:
			data["ip"] = ip
			data["seen"] = Time.get_ticks_msec()
			_found[ip + ":" + str(int(data.get("port", GAME_PORT)))] = data
	_found_accum += delta
	if _found_accum >= 1.0:
		_found_accum = 0.0
		var now = Time.get_ticks_msec()
		for k in _found.keys():
			if now - int(_found[k]["seen"]) > 4000:
				_found.erase(k)
		rooms_updated.emit(_found.values())


func _broadcast_targets() -> Array:
	var t = ["255.255.255.255"]
	for a in local_ipv4():
		var p = str(a).split(".")
		if p.size() == 4:
			var b = "%s.%s.%s.255" % [p[0], p[1], p[2]]
			if not t.has(b):
				t.append(b)
	return t


func _send_beacon() -> void:
	if _bc_udp == null or room.is_empty():
		return
	var g = Registry.get_game(str(room["game_id"]))
	var info = {
		"magic": MAGIC,
		"ver": PROTOCOL,
		"room": str(room.get("title", "")),
		"game_id": str(room["game_id"]),
		"game_name": str(g.get("name", "")),
		"host": player_name,
		"port": GAME_PORT,
		"players": _filled_count(),
		"seats": room["seats"].size(),
		"playing": bool(room.get("playing", false)),
	}
	var bytes = JSON.stringify(info).to_utf8_buffer()
	for addr in _broadcast_targets():
		_bc_udp.set_dest_address(str(addr), DISCOVERY_PORT)
		_bc_udp.put_packet(bytes)


# ---------------------------------------------------------------- 建房 / 加入 / 离开

func host_room(game_id: String, rules: Dictionary, offline: bool) -> bool:
	_reset()
	var g = Registry.get_game(game_id)
	if g.is_empty() or not bool(g.get("ready", false)):
		toast.emit("这个游戏还没上线")
		return false
	if offline:
		mode = "offline"
	else:
		_enet = ENetMultiplayerPeer.new()
		var err = _enet.create_server(GAME_PORT, MAX_CLIENTS)
		if err != OK:
			_enet = null
			toast.emit("创建房间失败（端口 %d 可能被占用）" % GAME_PORT)
			return false
		multiplayer.multiplayer_peer = _enet
		mode = "host"
		_bc_udp = PacketPeerUDP.new()
		_bc_udp.set_broadcast_enabled(true)
	my_peer = 1
	_round = 0
	var seats = []
	for i in int(g["seats"]):
		if i == 0:
			seats.append({"kind": "human", "peer": 1, "name": player_name, "away": ""})
		elif offline:
			seats.append(_bot_seat(i))
		else:
			seats.append(_empty_seat())
	room = {
		"game_id": game_id,
		"title": "%s的%s" % [player_name, str(g["name"])],
		"host": player_name,
		"rules": rules.duplicate(true),
		"seats": seats,
		"playing": false,
		"scores": {},
	}
	_broadcast_room()
	if mode == "host":
		_send_beacon()
	return true


func join_room(ip: String, port: int = GAME_PORT) -> void:
	_reset()
	_enet = ENetMultiplayerPeer.new()
	var err = _enet.create_client(ip, port)
	if err != OK:
		_enet = null
		toast.emit("无法连接 %s" % ip)
		return
	multiplayer.multiplayer_peer = _enet
	mode = "client"
	toast.emit("正在连接 %s ..." % ip)


func leave_room() -> void:
	var was = mode
	_reset()
	if was != "none":
		left_room.emit("")


func _reset() -> void:
	_bot_token += 1
	if _enet != null:
		_enet.close()
	_enet = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _bc_udp != null:
		_bc_udp.close()
		_bc_udp = null
	mode = "none"
	my_peer = 0
	room = {}
	state = {}
	_logic = null
	_reject_reason = ""


func _on_connected_to_server() -> void:
	if mode != "client":
		return
	my_peer = multiplayer.get_unique_id()
	_rpc_to_host.rpc_id(1, {"t": "hello", "name": player_name, "ver": PROTOCOL})


func _on_connection_failed() -> void:
	if mode != "client":
		return
	_reset()
	left_room.emit("连接失败：请确认两台设备在同一个WiFi，且房主的防火墙已允许棋牌乐")


func _on_server_disconnected() -> void:
	if mode != "client":
		return
	var reason = _reject_reason
	if reason == "":
		reason = "与房主的连接已断开"
	_reset()
	left_room.emit(reason)


# ---------------------------------------------------------------- 消息收发

@rpc("any_peer", "call_remote", "reliable")
func _rpc_to_host(msg: Dictionary) -> void:
	if mode != "host":
		return
	_host_handle(multiplayer.get_remote_sender_id(), msg)


@rpc("authority", "call_remote", "reliable")
func _rpc_to_client(msg: Dictionary) -> void:
	if mode != "client":
		return
	_client_handle(msg)


func send(msg: Dictionary) -> void:
	if mode == "host" or mode == "offline":
		_host_handle(1, msg)
	elif mode == "client":
		_rpc_to_host.rpc_id(1, msg)


func send_action(action: Dictionary) -> void:
	send({"t": "action", "a": action})


func set_seat_kind(seat: int, kind: String) -> void:
	send({"t": "seat", "seat": seat, "kind": kind})


func set_rule(key: String, value: String) -> void:
	send({"t": "rule", "key": key, "value": value})


func start_game() -> void:
	send({"t": "start"})


func back_to_room() -> void:
	send({"t": "to_room"})


func set_auto(on: bool) -> void:
	send({"t": "auto", "on": on})


func seat_auto(i: int) -> bool:
	var seats = room.get("seats", [])
	if i < 0 or i >= seats.size():
		return false
	return bool(seats[i].get("auto", false))


func _turn_time() -> int:
	var v = str(room.get("rules", {}).get("timer", "off"))
	if not v.is_valid_int():
		return 0
	return int(v)


func _to_peer(peer: int, msg: Dictionary) -> void:
	if peer == 1:
		_client_handle(msg)
	elif mode == "host":
		_rpc_to_client.rpc_id(peer, msg)


func _to_all(msg: Dictionary) -> void:
	if mode == "host":
		for p in multiplayer.get_peers():
			_rpc_to_client.rpc_id(p, msg)
	_client_handle(msg)


func _toast_all(text: String) -> void:
	_to_all({"t": "toast", "text": text})


func _broadcast_room() -> void:
	_to_all({"t": "room", "room": room.duplicate(true)})


func _broadcast_state() -> void:
	if _logic == null:
		return
	_maybe_tally()
	if _logic.has_method("get_state_for"):
		# 每个人只收到自己的手牌（斗地主等牌类游戏）
		if mode == "host":
			for p in multiplayer.get_peers():
				_rpc_to_client.rpc_id(p, {"t": "state", "state": _public_state_for(_seat_of_peer(p))})
		_client_handle({"t": "state", "state": _public_state_for(_seat_of_peer(1))})
	else:
		_to_all({"t": "state", "state": _public_state()})
	_schedule_bot()


func _public_state_for(seat: int) -> Dictionary:
	var s = _logic.get_state_for(seat)
	s["game_id"] = str(room["game_id"])
	s["round"] = _round
	s["turn_time"] = _turn_time()
	return s


func _maybe_tally() -> void:
	if _logic == null or _tallied or not _logic.is_over():
		return
	if not _logic.has_method("round_scores"):
		return
	_tallied = true
	var sc = _logic.round_scores()
	var tot = room.get("scores", {})
	for i in sc.size():
		var k = str(i)
		tot[k] = int(tot.get(k, 0)) + int(sc[i])
	room["scores"] = tot
	_broadcast_room()


func _public_state() -> Dictionary:
	var s = _logic.get_state()
	s["game_id"] = str(room["game_id"])
	s["round"] = _round
	s["turn_time"] = _turn_time()
	return s


# ---------------------------------------------------------------- 客户端处理（房主本机也走这里）

func _client_handle(msg: Dictionary) -> void:
	var t = str(msg.get("t", ""))
	if t == "welcome":
		my_peer = int(msg["peer"])
	elif t == "room":
		room = msg["room"]
		room_changed.emit(room)
	elif t == "state":
		state = msg["state"]
		state_changed.emit(state)
	elif t == "toast":
		toast.emit(str(msg["text"]))
	elif t == "reject":
		_reject_reason = str(msg["reason"])
		toast.emit(_reject_reason)


# ---------------------------------------------------------------- 房主处理

func _host_handle(sender: int, msg: Dictionary) -> void:
	if room.is_empty():
		return
	var t = str(msg.get("t", ""))
	if t == "hello":
		_h_hello(sender, msg)
	elif t == "action":
		_h_action(sender, msg.get("a", {}))
	elif t == "auto":
		_h_auto(sender, bool(msg.get("on", false)))
	elif t == "seat" and sender == 1:
		_h_seat(int(msg.get("seat", -1)), str(msg.get("kind", "")))
	elif t == "rule" and sender == 1:
		if not bool(room["playing"]):
			room["rules"][str(msg.get("key", ""))] = str(msg.get("value", ""))
			_broadcast_room()
	elif t == "start" and sender == 1:
		_host_start()
	elif t == "to_room" and sender == 1:
		_bot_token += 1
		room["playing"] = false
		_logic = null
		state = {}
		_broadcast_room()


func _h_hello(sender: int, msg: Dictionary) -> void:
	var pname = str(msg.get("name", "玩家")).strip_edges().substr(0, 12)
	if pname == "":
		pname = "玩家"
	if int(msg.get("ver", 0)) != PROTOCOL:
		_reject(sender, "版本不一致，请双方都更新到最新版棋牌乐")
		return
	var seats = room["seats"]
	var idx = -1
	if bool(room["playing"]):
		for i in seats.size():
			if str(seats[i]["kind"]) == "bot" and str(seats[i]["away"]) == pname:
				idx = i
				break
		if idx == -1:
			_reject(sender, "游戏进行中，请等这一局结束再加入")
			return
	else:
		for i in seats.size():
			if str(seats[i]["kind"]) == "empty":
				idx = i
				break
		if idx == -1:
			_reject(sender, "房间已满")
			return
	seats[idx] = {"kind": "human", "peer": sender, "name": pname, "away": ""}
	_to_peer(sender, {"t": "welcome", "peer": sender, "seat": idx})
	_broadcast_room()
	if bool(room["playing"]):
		_toast_all("%s 回来了，继续游戏" % pname)
		_broadcast_state()
	else:
		_toast_all("%s 加入了房间" % pname)


func _reject(peer: int, reason: String) -> void:
	_to_peer(peer, {"t": "reject", "reason": reason})
	await get_tree().create_timer(0.6).timeout
	if mode == "host" and _enet != null:
		_enet.disconnect_peer(peer)


func _h_seat(i: int, kind: String) -> void:
	var seats = room["seats"]
	if i <= 0 or i >= seats.size() or bool(room["playing"]):
		return
	var cur = seats[i]
	if str(cur["kind"]) == "human" and int(cur["peer"]) != 1:
		_reject(int(cur["peer"]), "你被房主移出了房间")
	if kind == "bot":
		seats[i] = _bot_seat(i)
	else:
		seats[i] = _empty_seat()
	_broadcast_room()


func _seat_of_peer(peer: int) -> int:
	var seats = room.get("seats", [])
	for i in seats.size():
		if str(seats[i]["kind"]) == "human" and int(seats[i]["peer"]) == peer:
			return i
	return -1


func _host_start() -> void:
	var g = Registry.get_game(str(room["game_id"]))
	var seats = room["seats"]
	var filled = 0
	for i in seats.size():
		if str(seats[i]["kind"]) != "empty":
			filled += 1
	var auto_bots = 0
	for i in seats.size():
		if filled >= int(g["min_players"]):
			break
		if str(seats[i]["kind"]) == "empty":
			seats[i] = _bot_seat(i)
			filled += 1
			auto_bots += 1
	if auto_bots > 0:
		_toast_all("人数不够，已自动补了 %d 个电脑" % auto_bots)
	var players = []
	for i in seats.size():
		if str(seats[i]["kind"]) != "empty":
			players.append(i)
	if players.size() < int(g["min_players"]):
		_to_peer(1, {"t": "toast", "text": "人数不足：至少需要 %d 人（可以把空位设为电脑）" % int(g["min_players"])})
		return
	var logic_script = load(str(g["logic"]))
	_logic = logic_script.new()
	for s in seats:
		if str(s["kind"]) == "human":
			s["auto"] = false
	_timeouts = {}
	_round += 1
	_tallied = false
	_logic.setup(players, room["rules"], _round)
	room["playing"] = true
	_broadcast_room()
	_broadcast_state()


func _h_action(sender: int, a) -> void:
	if _logic == null or not bool(room["playing"]):
		return
	if typeof(a) != TYPE_DICTIONARY:
		return
	var seat = _seat_of_peer(sender)
	if seat == -1:
		return
	var res = _logic.apply(seat, a)
	if res != "":
		_to_peer(sender, {"t": "toast", "text": res})
		return
	_timeouts.erase(seat)
	_broadcast_state()


func _h_auto(sender: int, on: bool) -> void:
	var i = _seat_of_peer(sender)
	if i == -1:
		return
	room["seats"][i]["auto"] = on
	_timeouts.erase(i)
	_broadcast_room()
	if bool(room.get("playing", false)) and _logic != null:
		_schedule_bot()


func _schedule_bot() -> void:
	## 电脑座位 / 托管座位：自动出手；真人座位：开了倒计时就计时，超时自动处理，连续2次超时自动托管
	_bot_token += 1
	if _logic == null or _logic.is_over():
		return
	var seat = _logic.current_seat()
	if seat < 0 or seat >= room["seats"].size():
		return
	var sd = room["seats"][seat]
	var is_bot = str(sd["kind"]) == "bot"
	var is_auto = bool(sd.get("auto", false))
	var token = _bot_token
	if is_bot or is_auto:
		var d = _logic.bot_delay() if is_bot else 0.6
		await get_tree().create_timer(d).timeout
		if token != _bot_token or _logic == null:
			return
		_run_auto(seat, false)
		return
	var tl = _turn_time()
	if tl <= 0 or str(sd["kind"]) != "human":
		return
	await get_tree().create_timer(float(tl) + 0.3).timeout
	if token != _bot_token or _logic == null or _logic.current_seat() != seat:
		return
	var cnt = int(_timeouts.get(seat, 0)) + 1
	_timeouts[seat] = cnt
	if cnt >= 2:
		room["seats"][seat]["auto"] = true
		_toast_all("%s 连续超时，已自动托管（点「取消托管」可恢复）" % str(sd["name"]))
		_broadcast_room()
	else:
		_toast_all("%s 超时，已自动处理" % str(sd["name"]))
	_run_auto(seat, true)


func _run_auto(seat: int, timed_out: bool) -> void:
	var a = {}
	if timed_out and _logic.has_method("timeout_action"):
		a = _logic.timeout_action(seat)
	if a.is_empty():
		a = _logic.bot_action(seat)
	if a.is_empty():
		return
	var res = _logic.apply(seat, a)
	if res != "" and timed_out:
		a = _logic.bot_action(seat)
		if a.is_empty():
			return
		res = _logic.apply(seat, a)
	if res == "":
		_broadcast_state()


func _on_peer_disconnected(id: int) -> void:
	if mode != "host" or room.is_empty():
		return
	var i = _seat_of_peer(id)
	if i == -1:
		return
	var nm = str(room["seats"][i]["name"])
	if bool(room["playing"]):
		room["seats"][i] = {"kind": "bot", "peer": 0, "name": nm + "(托管)", "away": nm}
		_toast_all("%s 掉线了，电脑暂时托管；用同一昵称重新加入可继续" % nm)
		_broadcast_room()
		_broadcast_state()
	else:
		room["seats"][i] = _empty_seat()
		_toast_all("%s 离开了房间" % nm)
		_broadcast_room()

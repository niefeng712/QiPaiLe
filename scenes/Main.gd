extends Control
## 棋牌乐 主界面：大厅 / 房间 / 游戏 三个画面，全部用代码生成

const Registry = preload("res://core/GameRegistry.gd")
const SETTINGS_PATH = "user://settings.cfg"

var selected_game = "gomoku"
var current_screen = ""

var hall_root: Control
var room_root: Control
var game_root: Control

var name_edit: LineEdit
var ip_label: Label
var game_buttons = {}
var game_desc_label: Label
var room_list_box: VBoxContainer
var ip_edit: LineEdit
var _rooms_sig = "-"

var room_title: Label
var room_info: Label
var seats_box: VBoxContainer
var rules_box: VBoxContainer
var room_desc: Label
var start_btn: Button

var game_title: Label
var game_status: Label
var game_holder: Control
var game_view = null
var game_view_id = ""
var btn_again: Button
var btn_to_room: Button
var btn_auto: Button
var timer_label: Label
var _turn_ms = 0

var toast_panel: PanelContainer
var toast_label: Label
var _toast_token = 0


func _ready() -> void:
	_setup_theme()
	var bg = ColorRect.new()
	bg.color = Color("#1f5e3b")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_hall()
	_build_room()
	_build_game()
	_build_toast()
	Net.rooms_updated.connect(_on_rooms_updated)
	Net.room_changed.connect(_on_room_changed)
	Net.state_changed.connect(_on_state_changed)
	Net.toast.connect(show_toast)
	Net.left_room.connect(_on_left_room)
	_load_settings()
	_select_game(selected_game)
	_show("hall")
	_on_rooms_updated([])
	_refresh_ip_label()
	if OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()


func _setup_theme() -> void:
	var th = Theme.new()
	var f = SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei", "Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC", "Droid Sans Fallback", "sans-serif"])
	th.default_font = f
	th.default_font_size = 22
	theme = th


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if current_screen == "hall":
			get_tree().quit()
		else:
			Net.leave_room()


# ---------------------------------------------------------------- 小工具

func _make_screen() -> MarginContainer:
	var m = MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	add_child(m)
	return m


func _label(text: String, fsize: int = 22) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	return l


func _btn(text: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.pressed.connect(cb)
	return b


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _show(screen: String) -> void:
	current_screen = screen
	hall_root.visible = screen == "hall"
	room_root.visible = screen == "room"
	game_root.visible = screen == "game"
	if screen == "hall":
		Net.start_discovery()
		_refresh_ip_label()
	else:
		Net.stop_discovery()


func show_toast(text: String) -> void:
	toast_label.text = text
	toast_panel.visible = true
	_toast_token += 1
	var t = _toast_token
	await get_tree().create_timer(3.0).timeout
	if t == _toast_token:
		toast_panel.visible = false


# ---------------------------------------------------------------- 大厅

func _build_hall() -> void:
	hall_root = _make_screen()
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	hall_root.add_child(v)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var title = _label("棋牌乐", 44)
	title.add_theme_color_override("font_color", Color("#ffe066"))
	top.add_child(title)
	top.add_child(_label("  单机 + 同WiFi联机", 20))
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_label("昵称：", 22))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(200, 50)
	name_edit.max_length = 12
	name_edit.text_changed.connect(_on_name_changed)
	top.add_child(name_edit)

	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	v.add_child(body)

	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.3
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	left.add_child(_label("选择游戏", 26))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for g in Registry.GAMES:
		var b = Button.new()
		var gid = str(g["id"])
		var is_ready = bool(g.get("ready", false))
		b.text = str(g["name"]) if is_ready else str(g["name"]) + "\n(即将上线)"
		b.custom_minimum_size = Vector2(170, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.disabled = not is_ready
		b.add_theme_font_size_override("font_size", 24 if is_ready else 18)
		b.pressed.connect(func(): _select_game(gid))
		grid.add_child(b)
		game_buttons[gid] = b
	game_desc_label = _label("", 20)
	game_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_desc_label.custom_minimum_size = Vector2(300, 60)
	left.add_child(game_desc_label)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	left.add_child(actions)
	var b1 = _btn("单机游戏（和电脑玩）", _on_offline)
	b1.custom_minimum_size = Vector2(260, 64)
	actions.add_child(b1)
	var b2 = _btn("创建局域网房间", _on_host)
	b2.custom_minimum_size = Vector2(240, 64)
	actions.add_child(b2)

	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	right.add_child(_label("同一WiFi下的房间", 26))
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	room_list_box = VBoxContainer.new()
	room_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_list_box.add_theme_constant_override("separation", 8)
	sc.add_child(room_list_box)
	var iprow = HBoxContainer.new()
	iprow.add_theme_constant_override("separation", 8)
	right.add_child(iprow)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "房主IP，如 192.168.1.5"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.custom_minimum_size = Vector2(0, 50)
	iprow.add_child(ip_edit)
	iprow.add_child(_btn("按IP加入", _on_join_ip))
	ip_label = _label("", 18)
	ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(ip_label)
	var hint = _label("提示：Windows 首次运行时会弹出防火墙提示，请勾选“专用网络”并允许。", 16)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.75)
	right.add_child(hint)


func _refresh_ip_label() -> void:
	if ip_label == null:
		return
	var ips = Net.local_ipv4()
	if ips.is_empty():
		ip_label.text = "本机IP：未连接网络"
	else:
		ip_label.text = "本机IP：" + "、".join(PackedStringArray(ips))


func _select_game(id: String) -> void:
	selected_game = id
	for k in game_buttons:
		game_buttons[k].button_pressed = (k == id)
	var g = Registry.get_game(id)
	if not g.is_empty():
		game_desc_label.text = "【%s】%s" % [str(g["name"]), str(g.get("desc", ""))]
	_save_settings()


func _on_offline() -> void:
	Net.host_room(selected_game, Registry.default_rules(selected_game), true)


func _on_host() -> void:
	Net.host_room(selected_game, Registry.default_rules(selected_game), false)


func _on_join_ip() -> void:
	var ip = ip_edit.text.strip_edges()
	if not ip.is_valid_ip_address():
		show_toast("请输入正确的IP地址，例如 192.168.1.5")
		return
	Net.join_room(ip, Net.GAME_PORT)


func _on_rooms_updated(rooms: Array) -> void:
	if room_list_box == null:
		return
	var sig = ""
	for r in rooms:
		sig += "%s|%s|%s|%s|%s;" % [str(r.get("ip", "")), str(r.get("room", "")), str(r.get("players", "")), str(r.get("seats", "")), str(r.get("playing", ""))]
	if sig == _rooms_sig:
		return
	_rooms_sig = sig
	_clear(room_list_box)
	if rooms.is_empty():
		var l = _label("正在搜索同一WiFi下的房间…\n（让另一台设备点「创建局域网房间」）", 20)
		l.modulate = Color(1, 1, 1, 0.7)
		room_list_box.add_child(l)
		return
	for r in rooms:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var playing = "（游戏中）" if bool(r.get("playing", false)) else ""
		var info = "%s\n%s · %d/%d 人%s · %s" % [str(r.get("room", "")), str(r.get("game_name", "")), int(r.get("players", 0)), int(r.get("seats", 0)), playing, str(r.get("ip", ""))]
		var l = _label(info, 19)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var ip = str(r.get("ip", ""))
		var port = int(r.get("port", Net.GAME_PORT))
		var jb = _btn("加入", func(): Net.join_room(ip, port))
		jb.custom_minimum_size = Vector2(100, 54)
		row.add_child(jb)
		room_list_box.add_child(row)


func _on_name_changed(t: String) -> void:
	var nm = t.strip_edges()
	if nm == "":
		nm = "玩家"
	Net.player_name = nm
	_save_settings()


func _load_settings() -> void:
	var cf = ConfigFile.new()
	var nm = ""
	if cf.load(SETTINGS_PATH) == OK:
		nm = str(cf.get_value("player", "name", ""))
		var g = str(cf.get_value("player", "game", "gomoku"))
		var info = Registry.get_game(g)
		if not info.is_empty() and bool(info.get("ready", false)):
			selected_game = g
	if nm == "":
		nm = "玩家%d" % (randi() % 900 + 100)
	name_edit.text = nm
	Net.player_name = nm


func _save_settings() -> void:
	if name_edit == null:
		return
	var cf = ConfigFile.new()
	cf.set_value("player", "name", Net.player_name)
	cf.set_value("player", "game", selected_game)
	cf.save(SETTINGS_PATH)


# ---------------------------------------------------------------- 房间

func _build_room() -> void:
	room_root = _make_screen()
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	room_root.add_child(v)
	room_title = _label("", 34)
	room_title.add_theme_color_override("font_color", Color("#ffe066"))
	v.add_child(room_title)
	room_info = _label("", 20)
	room_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(room_info)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 30)
	v.add_child(body)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	left.add_child(_label("座位", 26))
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 8)
	left.add_child(seats_box)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	right.add_child(_label("玩法规则", 26))
	var rsc = ScrollContainer.new()
	rsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rsc)
	rules_box = VBoxContainer.new()
	rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_box.add_theme_constant_override("separation", 8)
	rsc.add_child(rules_box)
	room_desc = _label("", 18)
	room_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_desc.modulate = Color(1, 1, 1, 0.8)
	right.add_child(room_desc)
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	v.add_child(bar)
	start_btn = _btn("开始游戏", func(): Net.start_game())
	start_btn.custom_minimum_size = Vector2(240, 64)
	bar.add_child(start_btn)
	var lb = _btn("离开房间", func(): Net.leave_room())
	lb.custom_minimum_size = Vector2(200, 64)
	bar.add_child(lb)


func _refresh_room() -> void:
	var room = Net.room
	if room.is_empty():
		return
	var g = Registry.get_game(str(room.get("game_id", "")))
	var host = Net.is_host()
	room_title.text = str(room.get("title", ""))
	room_desc.text = str(g.get("desc", ""))
	if Net.mode == "offline":
		room_info.text = "单机模式：空位可以设为电脑，选好玩法后点「开始游戏」。"
	elif Net.mode == "host":
		var ips = "、".join(PackedStringArray(Net.local_ipv4()))
		room_info.text = "你是房主。其他设备连同一个WiFi、打开棋牌乐，在大厅就能看到这个房间。\n本机IP：%s（大厅里找不到房间时，可在对方大厅输入这个IP加入）" % ips
	else:
		room_info.text = "已加入房间，等待房主开始游戏…"

	_clear(seats_box)
	var seats = room.get("seats", [])
	var me = Net.my_seat()
	for i in seats.size():
		var s = seats[i]
		var kind = str(s["kind"])
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l1 = _label("座位%d" % (i + 1), 22)
		l1.custom_minimum_size = Vector2(80, 0)
		row.add_child(l1)
		var txt = ""
		if kind == "human":
			txt = str(s["name"])
			if i == 0:
				txt += "（房主）"
			if i == me:
				txt += "（你）"
		elif kind == "bot":
			txt = "[电脑] " + str(s["name"])
		else:
			txt = "空位（等待加入）"
		var l2 = _label(txt, 22)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if kind == "empty":
			l2.modulate = Color(1, 1, 1, 0.6)
		row.add_child(l2)
		if host and i > 0:
			var idx = i
			if kind != "bot":
				row.add_child(_btn("设为电脑", func(): Net.set_seat_kind.call_deferred(idx, "bot")))
			if kind != "empty":
				var t = "移出" if kind == "human" else "设为空位"
				row.add_child(_btn(t, func(): Net.set_seat_kind.call_deferred(idx, "empty")))
		seats_box.add_child(row)

	_clear(rules_box)
	var rules = room.get("rules", {})
	for r in g.get("rules", []):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lab = _label(str(r["label"]) + "：", 22)
		lab.custom_minimum_size = Vector2(130, 0)
		row.add_child(lab)
		var ob = OptionButton.new()
		ob.custom_minimum_size = Vector2(280, 50)
		var opts = r["options"]
		var key = str(r["key"])
		var cur = str(rules.get(key, r["default"]))
		for k in opts.size():
			ob.add_item(str(opts[k][1]), k)
			if str(opts[k][0]) == cur:
				ob.select(k)
		ob.disabled = not host
		ob.item_selected.connect(func(index): Net.set_rule.call_deferred(key, str(opts[index][0])))
		row.add_child(ob)
		rules_box.add_child(row)
	start_btn.visible = host


# ---------------------------------------------------------------- 游戏

func _build_game() -> void:
	game_root = _make_screen()
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	game_root.add_child(v)
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	v.add_child(bar)
	game_title = _label("", 30)
	game_title.add_theme_color_override("font_color", Color("#ffe066"))
	bar.add_child(game_title)
	game_status = _label("", 21)
	game_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(game_status)
	timer_label = _label("", 26)
	timer_label.custom_minimum_size = Vector2(110, 0)
	bar.add_child(timer_label)
	btn_auto = _btn("托管", func(): Net.set_auto(not Net.seat_auto(Net.my_seat())))
	bar.add_child(btn_auto)
	btn_again = _btn("再来一局", func(): Net.start_game())
	bar.add_child(btn_again)
	btn_to_room = _btn("返回房间", func(): Net.back_to_room())
	bar.add_child(btn_to_room)
	bar.add_child(_btn("离开", func(): Net.leave_room()))
	game_holder = Control.new()
	game_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(game_holder)


func _ensure_view(id: String) -> void:
	if id == game_view_id and game_view != null:
		return
	if game_view != null:
		game_view.queue_free()
		game_view = null
	var g = Registry.get_game(id)
	if g.is_empty() or not g.has("view"):
		return
	var view_script = load(str(g["view"]))
	game_view = view_script.new()
	game_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_holder.add_child(game_view)
	game_view_id = id


func _refresh_game_bar() -> void:
	var st = Net.state
	var g = Registry.get_game(str(Net.room.get("game_id", "")))
	game_title.text = str(g.get("name", ""))
	var me = Net.my_seat()
	var is_auto = Net.seat_auto(me)
	if game_view != null and not st.is_empty():
		game_status.text = ("[托管中] " if is_auto else "") + game_view.status_text(st, me, Net.seat_names())
	var over = bool(st.get("over", false))
	btn_auto.visible = me >= 0 and not over and not st.is_empty()
	btn_auto.text = "取消托管" if is_auto else "托管"
	btn_again.visible = Net.is_host() and over
	btn_to_room.visible = Net.is_host() and over


func _on_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		return
	if bool(room.get("playing", false)):
		if current_screen != "game":
			_show("game")
		_turn_ms = Time.get_ticks_msec()
		_refresh_game_bar()
	else:
		if current_screen != "room":
			_show("room")
		_refresh_room()


func _on_state_changed(st: Dictionary) -> void:
	if st.is_empty():
		return
	_turn_ms = Time.get_ticks_msec()
	_ensure_view(str(st.get("game_id", "")))
	if game_view != null:
		game_view.update_state(st, Net.my_seat(), Net.seat_names())
	_refresh_game_bar()


func _process(_delta: float) -> void:
	if current_screen != "game" or timer_label == null:
		return
	var st = Net.state
	var tt = int(st.get("turn_time", 0))
	var cur = int(st.get("current_seat", -1))
	var vis = tt > 0 and cur >= 0 and not bool(st.get("over", false))
	if vis:
		var seats = Net.room.get("seats", [])
		if cur >= seats.size() or str(seats[cur]["kind"]) != "human" or bool(seats[cur].get("auto", false)):
			vis = false
	if not vis:
		timer_label.text = ""
		return
	var left = maxi(0, int(ceil(tt - (Time.get_ticks_msec() - _turn_ms) / 1000.0)))
	timer_label.text = "倒计时%d" % left
	var red = cur == Net.my_seat() and left <= 5
	timer_label.add_theme_color_override("font_color", Color("#ff6b6b") if red else Color.WHITE)


func _on_left_room(reason: String) -> void:
	_show("hall")
	if reason != "":
		show_toast(reason)


# ---------------------------------------------------------------- 自动化自检（GitHub Actions 里运行）

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_top = 1.0
	toast_panel.anchor_bottom = 1.0
	toast_panel.offset_left = -420
	toast_panel.offset_right = 420
	toast_panel.offset_top = -120
	toast_panel.offset_bottom = -40
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.78)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	toast_panel.add_theme_stylebox_override("panel", sb)
	toast_label = _label("", 22)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	add_child(toast_panel)


func _run_selftest() -> void:
	print("SELFTEST start")
	await get_tree().create_timer(0.5).timeout
	for g in Registry.GAMES:
		if not bool(g.get("ready", false)):
			continue
		var gid = str(g["id"])
		print("SELFTEST game: ", gid)
		if not Net.host_room(gid, Registry.default_rules(gid), true):
			printerr("SELFTEST FAIL: host_room offline ", gid)
			get_tree().quit(1)
			return
		_refresh_room()
		Net.start_game()
		await get_tree().create_timer(3.0).timeout
		if Net.state.is_empty() or game_view == null:
			printerr("SELFTEST FAIL: no state for ", gid)
			get_tree().quit(1)
			return
		print("SELFTEST status: ", game_status.text)
		Net.leave_room()
		await get_tree().create_timer(0.3).timeout
	if Net.host_room("ludo", Registry.default_rules("ludo"), false):
		_refresh_room()
		await get_tree().create_timer(1.5).timeout
		print("SELFTEST lan host ok, ips: ", Net.local_ipv4())
		Net.leave_room()
	print("SELFTEST OK")
	get_tree().quit(0)

extends Control
## 棋牌乐 主界面：大厅 / 房间 / 游戏 三个画面，全部用代码生成

const Registry = preload("res://core/GameRegistry.gd")
const SETTINGS_PATH = "user://settings.cfg"
const STATS_PATH = "user://stats.cfg"
const GameCard = preload("res://ui/GameCard.gd")
const FxLayer = preload("res://ui/FxLayer.gd")

var selected_game = "gomoku"
var current_screen = ""

var hall_root: Control
var room_root: Control
var game_root: Control

var name_edit: LineEdit
var ip_label: Label
var game_buttons = {}
var game_desc_label: Label
var detail_title: Label
var detail_stat: Label
var detail_icon: Control
var hall_grid: GridContainer
var hall_scroll: ScrollContainer
var total_stat_label: Label
var stats_popup: PopupPanel
var stats_box: GridContainer
var stats = {}
var current_cat = "全部"
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

var sfx_toggle: CheckButton
var music_toggle: CheckButton
var fx = null
var _banner_last = 0
var chat_popup: PopupPanel
var chat_edit: LineEdit
var chat_box: VBoxContainer
var _last_round = -1
var _last_over = false
var _last_cur = -2
var _last_event = ""
var _last_tick = -1

var toast_panel: PanelContainer
var toast_label: Label
var _toast_token = 0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_setup_theme()
	var grad = Gradient.new()
	grad.set_color(0, Color("#1d7148"))
	grad.set_color(1, Color("#052417"))
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.25)
	gt.fill_to = Vector2(1.25, 1.2)
	gt.width = 128
	gt.height = 128
	var bg = TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_load_stats()
	_build_hall()
	_build_room()
	_build_game()
	_build_toast()
	_build_chat()
	fx = FxLayer.new()
	add_child(fx)
	Net.chat_received.connect(_on_chat)
	Net.rooms_updated.connect(_on_rooms_updated)
	Net.room_changed.connect(_on_room_changed)
	Net.state_changed.connect(_on_state_changed)
	Net.toast.connect(show_toast)
	Net.left_room.connect(_on_left_room)
	_load_settings()
	_select_game(selected_game)
	_show("hall")
	_relayout_grid.call_deferred()
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
	th.set_stylebox("normal", "Button", _sb(Color("#2b7a4f"), 10))
	th.set_stylebox("hover", "Button", _sb(Color("#35935f"), 10))
	th.set_stylebox("pressed", "Button", _sb(Color("#d9a521"), 10))
	th.set_stylebox("hover_pressed", "Button", _sb(Color("#e8b632"), 10))
	th.set_stylebox("disabled", "Button", _sb(Color(0.18, 0.28, 0.23, 0.75), 10))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_pressed_color", "Button", Color("#2b1d00"))
	th.set_color("font_hover_pressed_color", "Button", Color("#2b1d00"))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))
	th.set_stylebox("pressed", "CheckButton", _sb(Color("#2b7a4f"), 10))
	th.set_stylebox("hover_pressed", "CheckButton", _sb(Color("#35935f"), 10))
	th.set_color("font_pressed_color", "CheckButton", Color.WHITE)
	th.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	th.set_stylebox("panel", "PanelContainer", _sb(Color(0, 0, 0, 0.26), 16, Color(1, 1, 1, 0.08), 1, 14))
	th.set_stylebox("normal", "LineEdit", _sb(Color(0, 0, 0, 0.35), 8, Color(1, 1, 1, 0.25), 1))
	th.set_stylebox("focus", "LineEdit", _sb(Color(0, 0, 0, 0.45), 8, Color("#ffe066"), 2))
	th.set_stylebox("panel", "PopupPanel", _sb(Color("#103a27"), 16, Color("#d9a521"), 2, 18))
	th.set_stylebox("panel", "PopupMenu", _sb(Color("#103a27"), 8, Color("#d9a521"), 1))
	th.set_color("font_hover_color", "PopupMenu", Color("#ffe066"))
	theme = th


func _sb(col: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0, margin: int = 12) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = 6 if margin <= 12 else margin
	sb.content_margin_bottom = 6 if margin <= 12 else margin
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb


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
	var changed = current_screen != screen
	current_screen = screen
	hall_root.visible = screen == "hall"
	room_root.visible = screen == "room"
	game_root.visible = screen == "game"
	Music.play_track("game" if screen == "game" else "hall")
	if changed:
		var root = hall_root if screen == "hall" else (room_root if screen == "room" else game_root)
		root.modulate.a = 0.0
		create_tween().tween_property(root, "modulate:a", 1.0, 0.25)
		if screen == "hall":
			_animate_cards()
	if screen == "hall":
		Net.start_discovery()
		_refresh_ip_label()
		_refresh_stats_ui()
	else:
		Net.stop_discovery()


func show_toast(text: String) -> void:
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 0.0
	create_tween().tween_property(toast_panel, "modulate:a", 1.0, 0.18)
	_toast_token += 1
	var t = _toast_token
	await get_tree().create_timer(3.0).timeout
	if t == _toast_token:
		toast_panel.visible = false


# ---------------------------------------------------------------- 大厅

func _build_hall() -> void:
	hall_root = _make_screen()
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	hall_root.add_child(v)

	# 顶部：logo、标题、战绩、音效、昵称
	var head = PanelContainer.new()
	v.add_child(head)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	head.add_child(top)
	var logo = TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(64, 64)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(logo)
	var tv = VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	top.add_child(tv)
	var title = _label("棋牌乐", 40)
	title.add_theme_color_override("font_color", Color("#ffe066"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 3)
	tv.add_child(title)
	var subt = _label("单机 + 同WiFi联机 · %d 款游戏 · v%s" % [Registry.ready_count(), str(ProjectSettings.get_setting("application/config/version", "1.0.0"))], 17)
	subt.modulate = Color(1, 1, 1, 0.8)
	tv.add_child(subt)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	total_stat_label = _label("", 18)
	total_stat_label.modulate = Color(1, 1, 1, 0.85)
	top.add_child(total_stat_label)
	var sb_btn = _btn("我的战绩", _open_stats)
	sb_btn.custom_minimum_size = Vector2(130, 50)
	top.add_child(sb_btn)
	sfx_toggle = CheckButton.new()
	sfx_toggle.text = "音效"
	sfx_toggle.button_pressed = true
	sfx_toggle.toggled.connect(_on_sfx_toggled)
	top.add_child(sfx_toggle)
	music_toggle = CheckButton.new()
	music_toggle.text = "音乐"
	music_toggle.button_pressed = true
	music_toggle.toggled.connect(_on_music_toggled)
	top.add_child(music_toggle)
	top.add_child(_label("昵称", 20))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(180, 48)
	name_edit.max_length = 12
	name_edit.text_changed.connect(_on_name_changed)
	top.add_child(name_edit)

	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)

	# 左边：分类、游戏卡片、选中游戏的介绍
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.8
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	left.add_child(tabs)
	var group = ButtonGroup.new()
	for c in Registry.CATS:
		var cat = str(c)
		var tb = Button.new()
		tb.text = cat
		tb.toggle_mode = true
		tb.button_group = group
		tb.button_pressed = cat == "全部"
		tb.custom_minimum_size = Vector2(96, 46)
		tb.add_theme_font_size_override("font_size", 20)
		tb.pressed.connect(func(): _apply_filter(cat))
		tabs.add_child(tb)
	hall_scroll = ScrollContainer.new()
	hall_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hall_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(hall_scroll)
	hall_grid = GridContainer.new()
	hall_grid.columns = 5
	hall_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hall_grid.add_theme_constant_override("h_separation", 10)
	hall_grid.add_theme_constant_override("v_separation", 10)
	hall_scroll.add_child(hall_grid)
	hall_scroll.resized.connect(_relayout_grid)
	for g in Registry.GAMES:
		var gid = str(g["id"])
		var card = GameCard.new()
		card.setup(g, Registry.icon(gid), _stat_text(gid))
		card.pressed.connect(func(): _select_game(gid))
		hall_grid.add_child(card)
		game_buttons[gid] = card

	var detail = PanelContainer.new()
	left.add_child(detail)
	var dh = HBoxContainer.new()
	dh.add_theme_constant_override("separation", 14)
	detail.add_child(dh)
	var dv = VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", 4)
	dh.add_child(dv)
	var dt_row = HBoxContainer.new()
	dt_row.add_theme_constant_override("separation", 14)
	dv.add_child(dt_row)
	detail_title = _label("", 26)
	detail_title.add_theme_color_override("font_color", Color("#ffe066"))
	dt_row.add_child(detail_title)
	detail_stat = _label("", 17)
	detail_stat.modulate = Color(1, 1, 1, 0.85)
	dt_row.add_child(detail_stat)
	game_desc_label = _label("", 17)
	game_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_desc_label.custom_minimum_size = Vector2(300, 0)
	game_desc_label.max_lines_visible = 4
	dv.add_child(game_desc_label)
	var actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	dh.add_child(actions)
	var b1 = _btn("单机游戏（和电脑玩）", _on_offline)
	b1.custom_minimum_size = Vector2(250, 56)
	actions.add_child(b1)
	var b2 = _btn("创建局域网房间", _on_host)
	b2.custom_minimum_size = Vector2(250, 56)
	b2.add_theme_stylebox_override("normal", _sb(Color("#c27c0e"), 10))
	b2.add_theme_stylebox_override("hover", _sb(Color("#d98e1a"), 10))
	actions.add_child(b2)

	# 右边：局域网房间
	var rp = PanelContainer.new()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rp)
	var right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	rp.add_child(right)
	var rt = _label("同一WiFi下的房间", 24)
	rt.add_theme_color_override("font_color", Color("#ffe066"))
	right.add_child(rt)
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
	ip_label = _label("", 17)
	ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(ip_label)
	var hint = _label("提示：Windows 首次运行时会弹出防火墙提示，请勾选“专用网络”并允许。", 15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.7)
	right.add_child(hint)
	_build_stats_popup()


func _relayout_grid() -> void:
	if hall_grid == null or hall_scroll == null:
		return
	hall_grid.columns = clampi(int(hall_scroll.size.x / 165.0), 2, 8)


func _apply_filter(cat: String) -> void:
	current_cat = cat
	for gid in game_buttons:
		var card = game_buttons[gid]
		card.visible = cat == "全部" or str(card.cat) == cat
	hall_scroll.scroll_vertical = 0
	_animate_cards()


func _animate_cards() -> void:
	var i = 0
	for gid in game_buttons:
		var card = game_buttons[gid]
		if not card.visible:
			continue
		card.modulate.a = 0.0
		var tw = create_tween()
		tw.tween_interval(0.025 * i)
		tw.tween_property(card, "modulate:a", 1.0, 0.22)
		i += 1


# ---------------------------------------------------------------- 战绩

func _load_stats() -> void:
	stats = {}
	var cf = ConfigFile.new()
	if cf.load(STATS_PATH) != OK:
		return
	for gid in cf.get_sections():
		stats[gid] = [int(cf.get_value(gid, "played", 0)), int(cf.get_value(gid, "won", 0))]


func _save_stats() -> void:
	var cf = ConfigFile.new()
	for gid in stats:
		cf.set_value(gid, "played", int(stats[gid][0]))
		cf.set_value(gid, "won", int(stats[gid][1]))
	cf.save(STATS_PATH)


func _stat_text(gid: String) -> String:
	var v = stats.get(gid, [0, 0])
	if int(v[0]) == 0:
		return "还没玩过"
	return "玩%d局 赢%d局" % [int(v[0]), int(v[1])]


func _refresh_stats_ui() -> void:
	var tp = 0
	var tw = 0
	for gid in stats:
		tp += int(stats[gid][0])
		tw += int(stats[gid][1])
	if total_stat_label != null:
		total_stat_label.text = "总战绩：%d局 胜%d局" % [tp, tw] if tp > 0 else "还没有战绩"
	for gid in game_buttons:
		game_buttons[gid].set_stat(_stat_text(gid))
	if detail_stat != null:
		var v = stats.get(selected_game, [0, 0])
		detail_stat.text = "战绩：%d局 胜%d局（胜率%d%%）" % [int(v[0]), int(v[1]), int(round(100.0 * int(v[1]) / maxi(int(v[0]), 1)))] if int(v[0]) > 0 else "还没玩过，来一局吧"


func _on_game_finished(st: Dictionary) -> void:
	var me = Net.my_seat()
	var gid = str(st.get("game_id", ""))
	if me < 0 or gid == "":
		return
	var v = stats.get(gid, [0, 0])
	v[0] = int(v[0]) + 1
	if st.get("winners", []).has(me):
		v[1] = int(v[1]) + 1
	stats[gid] = v
	_save_stats()
	_refresh_stats_ui()


func _build_stats_popup() -> void:
	stats_popup = PopupPanel.new()
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	stats_popup.add_child(v)
	var t = _label("我的战绩", 26)
	t.add_theme_color_override("font_color", Color("#ffe066"))
	v.add_child(t)
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 380)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	stats_box = GridContainer.new()
	stats_box.columns = 4
	stats_box.add_theme_constant_override("h_separation", 30)
	stats_box.add_theme_constant_override("v_separation", 6)
	sc.add_child(stats_box)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_btn("清空战绩", _clear_stats))
	row.add_child(_btn("关闭", func(): stats_popup.hide()))
	add_child(stats_popup)


func _open_stats() -> void:
	_clear(stats_box)
	for h in ["游戏", "局数", "胜", "胜率"]:
		var l = _label(h, 19)
		l.add_theme_color_override("font_color", Color("#ffe066"))
		stats_box.add_child(l)
	var any = false
	for g in Registry.GAMES:
		var gid = str(g["id"])
		var v = stats.get(gid, [0, 0])
		if int(v[0]) == 0:
			continue
		any = true
		stats_box.add_child(_label(str(g["name"]), 19))
		stats_box.add_child(_label(str(int(v[0])), 19))
		stats_box.add_child(_label(str(int(v[1])), 19))
		stats_box.add_child(_label("%d%%" % int(round(100.0 * int(v[1]) / maxi(int(v[0]), 1))), 19))
	if not any:
		stats_box.add_child(_label("还没有战绩，去玩一局吧", 19))
	stats_popup.popup_centered(Vector2i(600, 0))


func _clear_stats() -> void:
	stats = {}
	_save_stats()
	_refresh_stats_ui()
	stats_popup.hide()
	show_toast("战绩已清空")


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
		game_buttons[k].queue_redraw()
	var g = Registry.get_game(id)
	if not g.is_empty():
		var n = int(g.get("seats", 0))
		var mn = int(g.get("min_players", n))
		var people = "%d人" % n if mn == n else "%d~%d人" % [mn, n]
		detail_title.text = "%s  ·  %s" % [str(g["name"]), people]
		game_desc_label.text = str(g.get("desc", ""))
	_refresh_stats_ui()
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
		Sfx.enabled = bool(cf.get_value("player", "sfx", true))
		Music.set_enabled(bool(cf.get_value("player", "music", true)))
		var g = str(cf.get_value("player", "game", "gomoku"))
		var info = Registry.get_game(g)
		if not info.is_empty() and bool(info.get("ready", false)):
			selected_game = g
	if nm == "":
		nm = "玩家%d" % (randi() % 900 + 100)
	name_edit.text = nm
	Net.player_name = nm
	sfx_toggle.set_pressed_no_signal(Sfx.enabled)
	music_toggle.set_pressed_no_signal(Music.enabled)


func _save_settings() -> void:
	if name_edit == null:
		return
	var cf = ConfigFile.new()
	cf.set_value("player", "name", Net.player_name)
	cf.set_value("player", "game", selected_game)
	cf.set_value("player", "sfx", Sfx.enabled)
	cf.set_value("player", "music", Music.enabled)
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
	var lp = PanelContainer.new()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(lp)
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	lp.add_child(left)
	left.add_child(_label("座位", 26))
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 8)
	left.add_child(seats_box)
	var rpn = PanelContainer.new()
	rpn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rpn)
	var right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	rpn.add_child(right)
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
	var cb = _btn("快捷聊天", _open_chat)
	cb.custom_minimum_size = Vector2(170, 64)
	bar.add_child(cb)


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
	var bp = PanelContainer.new()
	bp.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.32), 14, Color(1, 1, 1, 0.08), 1, 8))
	v.add_child(bp)
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bp.add_child(bar)
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
	bar.add_child(_btn("聊天", _open_chat))
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
	_play_state_sound(st)
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
	if red and left > 0 and left != _last_tick:
		Sfx.play("tick")
	_last_tick = left
	timer_label.add_theme_color_override("font_color", Color("#ff6b6b") if red else Color.WHITE)


# ---------------------------------------------------------------- 音效 / 快捷聊天

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n is CheckButton):
		n.pressed.connect(func(): Sfx.play("click"))


func _on_music_toggled(on: bool) -> void:
	Music.set_enabled(on)
	_save_settings()


func _on_sfx_toggled(on: bool) -> void:
	Sfx.enabled = on
	_save_settings()
	if on:
		Sfx.play("start")


func _play_state_sound(st: Dictionary) -> void:
	var rd = int(st.get("round", 0))
	var over = bool(st.get("over", false))
	var cur = int(st.get("current_seat", -1))
	var me = Net.my_seat()
	var ev = str(st.get("event", ""))
	if rd != _last_round:
		_last_round = rd
		_last_over = over
		_last_cur = cur
		_last_event = ev
		Sfx.play("turn" if cur == me and me >= 0 else "start")
		if cur == me and me >= 0:
			_turn_banner()
		return
	if over and not _last_over:
		var w = st.get("winners", [])
		if me >= 0 and w.has(me):
			Sfx.play("win")
			fx.celebrate(true, "胜利！")
		elif me >= 0 and not w.is_empty():
			Sfx.play("lose")
			fx.celebrate(false, "再接再厉")
		else:
			Sfx.play("end")
			fx.celebrate(false, "游戏结束")
		_on_game_finished(st)
	elif not over and cur == me and me >= 0 and _last_cur != me:
		Sfx.play("turn")
		_turn_banner()
	elif ev != _last_event:
		Sfx.play("card")
	_last_over = over
	_last_cur = cur
	_last_event = ev


func _turn_banner() -> void:
	var now = Time.get_ticks_msec()
	if now - _banner_last < 2500:
		return
	_banner_last = now
	var seats = Net.room.get("seats", [])
	var humans = 0
	for sd in seats:
		if str(sd["kind"]) != "empty":
			humans += 1
	if humans >= 2:
		fx.banner("轮到你了！")


func _build_chat() -> void:
	chat_box = VBoxContainer.new()
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_box.anchor_left = 1.0
	chat_box.anchor_right = 1.0
	chat_box.offset_left = -470
	chat_box.offset_right = -16
	chat_box.offset_top = 86
	chat_box.offset_bottom = 420
	chat_box.add_theme_constant_override("separation", 6)
	add_child(chat_box)
	chat_popup = PopupPanel.new()
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	chat_popup.add_child(v)
	v.add_child(_label("快捷聊天", 24))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for ph in Net.CHAT_PHRASES:
		var t = str(ph)
		var b = _btn(t, func(): _send_chat.call_deferred(t))
		b.custom_minimum_size = Vector2(320, 48)
		b.add_theme_font_size_override("font_size", 18)
		grid.add_child(b)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "自己输入（最多30个字）"
	chat_edit.max_length = 30
	chat_edit.custom_minimum_size = Vector2(0, 50)
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_edit.text_submitted.connect(func(t): _send_chat(t))
	row.add_child(chat_edit)
	row.add_child(_btn("发送", func(): _send_chat.call_deferred(chat_edit.text)))
	add_child(chat_popup)


func _open_chat() -> void:
	if Net.mode == "none":
		return
	chat_popup.popup_centered(Vector2i(680, 0))


func _send_chat(t: String) -> void:
	t = t.strip_edges()
	if t == "":
		return
	Net.send_chat(t)
	chat_edit.text = ""
	chat_popup.hide()


func _on_chat(_seat: int, sender: String, text: String) -> void:
	Sfx.play("chat")
	var p = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.08, 0.82)
	sb.border_color = Color("#ffe066")
	sb.border_width_left = 4
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var l = _label("%s：%s" % [sender, text], 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	chat_box.add_child(p)
	p.modulate.a = 0.0
	create_tween().tween_property(p, "modulate:a", 1.0, 0.2)
	while chat_box.get_child_count() > 5:
		var old = chat_box.get_child(0)
		chat_box.remove_child(old)
		old.queue_free()
	await get_tree().create_timer(5.6, true, false, true).timeout
	if is_instance_valid(p):
		var tw = create_tween()
		tw.tween_property(p, "modulate:a", 0.0, 0.4)
		tw.tween_callback(p.queue_free)


func _on_left_room(reason: String) -> void:
	if game_view != null:
		game_view.queue_free()
		game_view = null
		game_view_id = ""
	_last_round = -1
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


func _wait_real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


## 自动化自检（GitHub Actions 里运行）：把每款游戏用"托管"从头打到尾，检查界面、动画、音效、聊天、战绩都不报错
func _run_selftest() -> void:
	print("SELFTEST start")
	await _wait_real(0.5)
	var mt = 0.0
	while not Music.loaded and mt < 60.0:
		await _wait_real(0.25)
		mt += 0.25
	if not Music.loaded:
		printerr("SELFTEST FAIL: background music not generated")
		get_tree().quit(1)
		return
	print("SELFTEST music ok (%.1fs)" % mt)
	Engine.time_scale = 30.0
	for g in Registry.GAMES:
		if not bool(g.get("ready", false)):
			continue
		var gid = str(g["id"])
		var rules = Registry.default_rules(gid)
		if gid == "xiangqi":
			rules["level"] = "easy"
		if not Net.host_room(gid, rules, true):
			printerr("SELFTEST FAIL: host_room offline ", gid)
			get_tree().quit(1)
			return
		_refresh_room()
		Net.start_game()
		await _wait_real(0.05)
		Net.set_auto(true)
		var t0 = Time.get_ticks_msec()
		var cap_ms = 60000 if gid == "ludo" else 12000
		while not bool(Net.state.get("over", false)) and Time.get_ticks_msec() - t0 < cap_ms:
			await _wait_real(0.05)
		if Net.state.is_empty() or game_view == null:
			printerr("SELFTEST FAIL: no state for ", gid)
			get_tree().quit(1)
			return
		var done = bool(Net.state.get("over", false))
		if not done and gid != "xiangqi":
			printerr("SELFTEST FAIL: %s did not finish within %ds" % [gid, cap_ms / 1000])
			get_tree().quit(1)
			return
		print("SELFTEST game %s: %s in %.1fs ｜ %s" % [gid, "finished" if done else "still running (time cap)", (Time.get_ticks_msec() - t0) / 1000.0, game_status.text.left(70)])
		if done:
			var r1 = int(Net.state.get("round", 0))
			Net.start_game()
			await _wait_real(0.05)
			Net.set_auto(true)
			await _wait_real(0.4)
			if int(Net.state.get("round", 0)) != r1 + 1:
				printerr("SELFTEST FAIL: next round did not start for ", gid)
				get_tree().quit(1)
				return
		Net.send_chat("再来一局！")
		await _wait_real(0.1)
		if chat_box.get_child_count() == 0:
			printerr("SELFTEST FAIL: chat message not shown for ", gid)
			get_tree().quit(1)
			return
		Net.leave_room()
		await _wait_real(0.1)
	Engine.time_scale = 1.0
	if Net.host_room("ludo", Registry.default_rules("ludo"), false):
		_refresh_room()
		await _wait_real(1.0)
		print("SELFTEST lan host ok, ips: ", Net.local_ipv4())
		Net.leave_room()
	for snd in ["click", "card", "turn", "win", "lose", "chat", "tick", "start", "end"]:
		if not Sfx.has_sound(snd):
			printerr("SELFTEST FAIL: missing sound ", snd)
			get_tree().quit(1)
			return
		Sfx.play(snd)
	print("SELFTEST sounds ok")
	fx.celebrate(true, "胜利！")
	fx.banner("轮到你了！")
	await _wait_real(0.5)
	_open_stats()
	await _wait_real(0.2)
	stats_popup.hide()
	for c in Registry.CATS:
		_apply_filter(str(c))
	_apply_filter("全部")
	await _wait_real(0.5)
	print("SELFTEST hall ok, cards: ", game_buttons.size())
	print("SELFTEST OK")
	get_tree().quit(0)

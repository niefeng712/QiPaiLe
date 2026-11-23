extends Control
## 五子棋界面：画棋盘、棋子，点击落子

var st = {}
var my_seat = -1
var names = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func update_state(s: Dictionary, seat: int, seat_names: Array) -> void:
	st = s
	my_seat = seat
	names = seat_names
	queue_redraw()


func _nm(n: Array, i: int) -> String:
	if i >= 0 and i < n.size():
		return str(n[i])
	return "?"


func status_text(s: Dictionary, seat: int, n: Array) -> String:
	var bs = int(s.get("black_seat", 0))
	var ws = int(s.get("white_seat", 1))
	var head = "黑：%s　白：%s　　" % [_nm(n, bs), _nm(n, ws)]
	if bool(s.get("over", false)):
		if bool(s.get("draw", false)):
			return head + "平局！"
		var w = int(s["winners"][0])
		if w == seat:
			return head + "你赢了！"
		return head + "%s 获胜！" % _nm(n, w)
	var cur = int(s.get("current_seat", -1))
	var color = "黑" if cur == bs else "白"
	if cur == seat:
		return head + "轮到你落子（%s棋）" % color
	return head + "等待 %s 落子（%s棋）…" % [_nm(n, cur), color]


func _geom() -> Array:
	var n = int(st.get("size", 15))
	var side = min(size.x, size.y) - 20.0
	if side < 50.0:
		side = 50.0
	var cell = side / float(n)
	var origin = Vector2((size.x - side) / 2.0, (size.y - side) / 2.0) + Vector2(cell / 2.0, cell / 2.0)
	return [origin, cell]


func _draw() -> void:
	if st.is_empty():
		return
	var n = int(st["size"])
	var g = _geom()
	var o: Vector2 = g[0]
	var c: float = g[1]
	var board_rect = Rect2(o - Vector2(c / 2.0, c / 2.0), Vector2(c * n, c * n))
	draw_rect(board_rect.grow(8.0), Color("#8a5a2b"))
	draw_rect(board_rect, Color("#e3b870"))
	var line_col = Color(0.25, 0.17, 0.08)
	for i in n:
		draw_line(o + Vector2(0, i * c), o + Vector2((n - 1) * c, i * c), line_col, 1.5)
		draw_line(o + Vector2(i * c, 0), o + Vector2(i * c, (n - 1) * c), line_col, 1.5)
	for p in [[3, 3], [11, 3], [7, 7], [3, 11], [11, 11]]:
		draw_circle(o + Vector2(p[0] * c, p[1] * c), c * 0.1, line_col)
	var b = st["board"]
	for y in n:
		for x in n:
			var v = int(b[y * n + x])
			if v == -1:
				continue
			var pos = o + Vector2(x * c, y * c)
			draw_circle(pos + Vector2(2, 2), c * 0.43, Color(0, 0, 0, 0.3))
			if v == 0:
				draw_circle(pos, c * 0.43, Color(0.08, 0.08, 0.08))
			else:
				draw_circle(pos, c * 0.43, Color(0.97, 0.97, 0.94))
	var last = st.get("last", [])
	if last.size() == 2:
		draw_circle(o + Vector2(int(last[0]) * c, int(last[1]) * c), c * 0.12, Color("#e74c3c"))
	var wl = st.get("win_line", [])
	if wl.size() == 4:
		var p1 = o + Vector2(int(wl[0]) * c, int(wl[1]) * c)
		var p2 = o + Vector2(int(wl[2]) * c, int(wl[3]) * c)
		draw_line(p1, p2, Color("#e74c3c"), 5.0)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if st.is_empty() or bool(st.get("over", false)):
		return
	if int(st.get("current_seat", -1)) != my_seat:
		return
	var g = _geom()
	var o: Vector2 = g[0]
	var c: float = g[1]
	var n = int(st["size"])
	var x = int(round((mb.position.x - o.x) / c))
	var y = int(round((mb.position.y - o.y) / c))
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	if int(st["board"][y * n + x]) != -1:
		return
	Net.send_action({"type": "place", "x": x, "y": y})

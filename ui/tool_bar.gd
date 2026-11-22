extends Control
# ToolBar (Feature D: Minimalist Tool & Upgrade Hotbar - phong cách Mini Motorways)
# Hiển thị các công cụ: Vẽ đường (hình thoi), Đặt Phà / Cầu (hình tròn), Đèn giao thông, Bùng binh.
# Khi rê chuột vào: biểu tượng nổi lên (nền trắng kem, icon tối màu).
# Khi không rê chuột: trở lại bình thường (nền tối, icon sáng màu).

const COLOR_DARK := Color("#23272b")
const COLOR_LIGHT := Color("#f5f6f0")
const COLOR_BORDER := Color("#3e464d")
const COLOR_MUTED := Color("#5a6b77")
const COLOR_BADGE_BG := Color("#ffffff")
const COLOR_BADGE_FG := Color("#1a1d20")
const COLOR_BADGE_DARK_BG := Color("#202428")
const COLOR_BADGE_DARK_FG := Color("#ffffff")
const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.35)

var _tex_road: Texture2D
var _tex_ferry: Texture2D
var _tex_traffic: Texture2D
var _tex_roundabout: Texture2D

var active_tool: int = 0  # 0: ROAD, 1: FERRY
var hovered_slot: int = -1 # -1: none, 0: ROUNDABOUT, 1: TRAFFIC, 2: ROAD, 3: FERRY

var roads_left: int = 50
var ferries_available: int = 1
var ferries_total: int = 1
var traffic_count: int = 1
var roundabout_count: int = 2

# Vị trí các slot trung tâm (X, Y)
const POS_ROUNDABOUT := Vector2(26, 28)
const POS_TRAFFIC := Vector2(72, 28)
const POS_ROAD := Vector2(126, 28)
const POS_FERRY := Vector2(184, 28)

func _ready() -> void:
	custom_minimum_size = Vector2(216, 56)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP

	if ResourceLoader.exists("res://assets/icons/tool_road.svg"):
		_tex_road = load("res://assets/icons/tool_road.svg")
	if ResourceLoader.exists("res://assets/icons/tool_ferry.svg"):
		_tex_ferry = load("res://assets/icons/tool_ferry.svg")
	if ResourceLoader.exists("res://assets/icons/tool_traffic_light.svg"):
		_tex_traffic = load("res://assets/icons/tool_traffic_light.svg")
	if ResourceLoader.exists("res://assets/icons/tool_roundabout.svg"):
		_tex_roundabout = load("res://assets/icons/tool_roundabout.svg")

	EventBus.edge_budget_changed.connect(_on_budget_changed)
	EventBus.ferry_inventory_changed.connect(_on_ferry_inventory)
	EventBus.ferry_routes_changed.connect(_on_ferry_routes)
	EventBus.active_tool_changed.connect(_on_tool_changed)
	EventBus.game_started.connect(_on_game_started)

	mouse_exited.connect(func() -> void:
		hovered_slot = -1
		queue_redraw()
	)

func _on_game_started() -> void:
	if has_node("/root/GraphManager"):
		ferries_available = GraphManager.get_ferries_available()
		ferries_total = GraphManager.get_ferries_total()
	active_tool = 0
	queue_redraw()

func _on_budget_changed(used: int, limit: int) -> void:
	roads_left = maxi(0, limit - used)
	queue_redraw()

func _on_ferry_inventory(available: int, total: int) -> void:
	ferries_available = available
	ferries_total = total
	queue_redraw()

func _on_ferry_routes() -> void:
	if has_node("/root/GraphManager"):
		ferries_available = GraphManager.get_ferries_available()
		ferries_total = GraphManager.get_ferries_total()
	queue_redraw()

func _on_tool_changed(tool_id: int) -> void:
	active_tool = tool_id
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var slot := _slot_at(event.position)
		if slot != hovered_slot:
			hovered_slot = slot
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var slot := _slot_at(event.position)
		if slot == 2:  # Road
			EventBus.active_tool_changed.emit(0)
			accept_event()
		elif slot == 3:  # Ferry
			if ferries_available > 0:
				EventBus.active_tool_changed.emit(1)
				accept_event()

func _slot_at(pos: Vector2) -> int:
	if pos.distance_to(POS_ROUNDABOUT) <= 20.0:
		return 0
	if pos.distance_to(POS_TRAFFIC) <= 20.0:
		return 1
	if pos.distance_to(POS_ROAD) <= 24.0:
		return 2
	if pos.distance_to(POS_FERRY) <= 20.0:
		return 3
	return -1

func _draw() -> void:
	# 1. Roundabout (Bùng binh - slot 0)
	_draw_circle_tool(POS_ROUNDABOUT, 19.0, _tex_roundabout, roundabout_count, hovered_slot == 0, false, false, true)

	# 2. Traffic Light (Đèn giao thông - slot 1)
	_draw_circle_tool(POS_TRAFFIC, 19.0, _tex_traffic, traffic_count, hovered_slot == 1, false, false, true)

	# 3. Road (Đường hình thoi diamond - slot 2)
	_draw_road_diamond(POS_ROAD, 19.0, _tex_road, roads_left, hovered_slot == 2, active_tool == 0)

	# 4. Ferry / Bridge (Bến Phà Phao / Cầu - slot 3)
	var ferry_disabled: bool = (ferries_available <= 0 and active_tool != 1)
	_draw_circle_tool(POS_FERRY, 19.5, _tex_ferry, ferries_available, hovered_slot == 3, active_tool == 1, ferry_disabled, false)

func _draw_road_diamond(center: Vector2, half_size: float, tex: Texture2D, count: int, hovered: bool, active: bool) -> void:
	var highlight: bool = (hovered or active)
	var bg_col: Color = COLOR_LIGHT if highlight else COLOR_DARK
	var fg_col: Color = COLOR_DARK if highlight else COLOR_LIGHT
	var s := half_size * 1.05

	# Vẽ hình thoi xoay 45 độ (Diamond)
	var pts := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s, 0),
		center + Vector2(0, s),
		center + Vector2(-s, 0)
	])

	# Đổ bóng
	var shadow_pts := PackedVector2Array([
		center + Vector2(0, -s + 2.5),
		center + Vector2(s, 2.5),
		center + Vector2(0, s + 2.5),
		center + Vector2(-s, 2.5)
	])
	draw_colored_polygon(shadow_pts, COLOR_SHADOW)

	# Nền diamond
	draw_colored_polygon(pts, bg_col)
	if highlight:
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#ffffff"), 2.0)
	else:
		draw_polyline(pts + PackedVector2Array([pts[0]]), COLOR_BORDER, 1.2)

	# Icon bên trong
	if tex != null:
		var tex_size := Vector2(26, 26)
		draw_texture_rect(tex, Rect2(center - tex_size / 2.0, tex_size), false, fg_col)

	# Badge số lượng đường còn lại (góc trên bên phải)
	_draw_badge(center + Vector2(16, -10), count, true)

func _draw_circle_tool(center: Vector2, radius: float, tex: Texture2D, count: int, hovered: bool, active: bool, disabled: bool, badge_left: bool) -> void:
	var highlight: bool = (hovered or active) and not disabled

	# Đổ bóng
	if not disabled:
		draw_circle(center + Vector2(0, 2), radius, COLOR_SHADOW)

	if disabled:
		# Trạng thái hết lượt / viền rỗng mờ
		draw_arc(center, radius, 0.0, TAU, 32, COLOR_MUTED, 2.0)
		if tex != null:
			var tex_size := Vector2(24, 24)
			draw_texture_rect(tex, Rect2(center - tex_size / 2.0, tex_size), false, COLOR_MUTED * 0.8)
		return

	var bg_col: Color = COLOR_LIGHT if highlight else COLOR_DARK
	var fg_col: Color = COLOR_DARK if highlight else COLOR_LIGHT

	draw_circle(center, radius, bg_col)
	if highlight:
		draw_arc(center, radius, 0.0, TAU, 32, Color("#ffffff"), 2.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 32, COLOR_BORDER, 1.2)

	if tex != null:
		var tex_size := Vector2(24, 24)
		draw_texture_rect(tex, Rect2(center - tex_size / 2.0, tex_size), false, fg_col)

	# Badge số lượng
	var badge_offset: Vector2 = Vector2(-14, -10) if badge_left else Vector2(14, -10)
	var badge_pos: Vector2 = center + badge_offset
	_draw_badge(badge_pos, count, not badge_left)

func _draw_badge(pos: Vector2, count: int, white_badge: bool) -> void:
	var r := 10.5
	var bg: Color = COLOR_BADGE_BG if white_badge else COLOR_BADGE_DARK_BG
	var fg: Color = COLOR_BADGE_FG if white_badge else COLOR_BADGE_DARK_FG

	# Viền badge
	draw_circle(pos + Vector2(0, 1), r, COLOR_SHADOW)
	draw_circle(pos, r, bg)
	draw_arc(pos, r, 0.0, TAU, 24, COLOR_BORDER if white_badge else Color("#ffffff", 0.3), 1.0)

	# Số lượng
	var font := ThemeDB.fallback_font
	var text := str(count)
	var font_size: int = 11 if count < 100 else 10
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos: Vector2 = pos + Vector2(-text_size.x / 2.0, text_size.y * 0.35)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, fg)

extends Control
## Toolbar vật phẩm ở chính giữa cạnh dưới (Owner: B).
## - Tự hiện khi con trỏ vào vùng đáy giữa; tự ẩn khi rời vùng.
## - Không tự ẩn khi đang đặt vật phẩm (Ferry/Traffic Light/Roundabout/Highway) hoặc đang chọn card draft.
## - Đọc ngân sách đường từ GraphManager.get_edge_budget() + EventBus.edge_budget_changed(used, limit).
## - Đọc 4 token đặt được từ GameManager.get_inventory(reward_id) + EventBus.inventory_changed(reward_id, available).
## - Disable item khi count == 0; UI không tự trừ/refund count.

# Hợp đồng ID dùng chung (docs/endless_gameplay_team_assignments.md mục 2)
const TOOL_ROAD := Types.ToolId.ROAD
const TOOL_FERRY := Types.ToolId.FERRY
const TOOL_TRAFFIC_LIGHT := Types.ToolId.TRAFFIC_LIGHT
const TOOL_ROUNDABOUT := Types.ToolId.ROUNDABOUT
const TOOL_HIGHWAY := Types.ToolId.HIGHWAY
const TOOL_ERASE := Types.ToolId.ERASE

const REWARD_TRAFFIC_LIGHT := Types.Reward.TRAFFIC_LIGHT
const REWARD_ROUNDABOUT := Types.Reward.ROUNDABOUT
const REWARD_HIGHWAY := Types.Reward.HIGHWAY
const REWARD_FERRY := Types.Reward.FERRY

# Bảng màu đồng bộ với Card Draft (Owner: E)
const COLOR_BG := Color("#121e2b")
const COLOR_BG_HOVER := Color("#1a2b3d")
const COLOR_BG_SELECTED := Color("#192d40")
const COLOR_BG_DISABLED := Color("#0c141d")
const COLOR_BORDER := Color("#2a4259")
const COLOR_BORDER_DISABLED := Color("#1e2e3d")
const COLOR_INK := Color("#f2f8ff")
const COLOR_MUTED := Color("#8ea8be")
const COLOR_GOLD := Color("#ffd23f")
const COLOR_CYAN := Color("#4fd3ec")
const COLOR_MINT := Color("#5ee3b0")
const COLOR_BLUE := Color("#7cb8ff")
const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.42)

const BAR_SIZE := Vector2(344, 68)
const HANDLE_SIZE := Vector2(72, 6)
const HOVER_ZONE_HEIGHT := 98.0
const HOVER_ZONE_PAD_X := 44.0
const SHOWN_MARGIN_BOTTOM := 14.0
const HIDDEN_OFFSET_Y := 60.0
const SLIDE_DURATION := 0.16

const SLOT_RADIUS := 21.0
const SLOT_DEFS := [
	{"tool": TOOL_ROUNDABOUT, "reward": REWARD_ROUNDABOUT, "pos": Vector2(44, 34), "accent": COLOR_MINT, "label": "Vòng xoay", "diamond": false},
	{"tool": TOOL_TRAFFIC_LIGHT, "reward": REWARD_TRAFFIC_LIGHT, "pos": Vector2(104, 34), "accent": COLOR_MINT, "label": "Đèn giao thông", "diamond": false},
	{"tool": TOOL_ROAD, "reward": -1, "pos": Vector2(172, 34), "accent": COLOR_GOLD, "label": "Đường", "diamond": true},
	{"tool": TOOL_FERRY, "reward": REWARD_FERRY, "pos": Vector2(240, 34), "accent": COLOR_CYAN, "label": "Phà vượt sông", "diamond": false},
	{"tool": TOOL_HIGHWAY, "reward": REWARD_HIGHWAY, "pos": Vector2(300, 34), "accent": COLOR_BLUE, "label": "Đường cao tốc", "diamond": false},
]

var _tex_road: Texture2D
var _tex_ferry: Texture2D
var _tex_traffic: Texture2D
var _tex_roundabout: Texture2D
var _tex_highway: Texture2D
var _font_bold: Font

var active_tool: int = TOOL_ROAD
var hovered_slot: int = -1
var draft_open: bool = false

var roads_left: int = Config.EDGE_LIMIT_START
var counts := {
	REWARD_TRAFFIC_LIGHT: 0,
	REWARD_ROUNDABOUT: 0,
	REWARD_HIGHWAY: 0,
	REWARD_FERRY: 0,
}

var _bar_shown := false
var _slide_tween: Tween = null
var _tooltip_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = BAR_SIZE
	size = BAR_SIZE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -BAR_SIZE.x / 2.0
	offset_right = BAR_SIZE.x / 2.0
	_apply_slide_offsets(HIDDEN_OFFSET_Y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_load_assets()
	_build_tooltip()
	_connect_signals()
	_refresh_all_counts()
	_update_auto_hide(true)


func _load_assets() -> void:
	if ResourceLoader.exists("res://assets/icons/tool_road.svg"):
		_tex_road = load("res://assets/icons/tool_road.svg")
	if ResourceLoader.exists("res://assets/icons/tool_ferry.svg"):
		_tex_ferry = load("res://assets/icons/tool_ferry.svg")
	if ResourceLoader.exists("res://assets/icons/tool_traffic_light.svg"):
		_tex_traffic = load("res://assets/icons/tool_traffic_light.svg")
	if ResourceLoader.exists("res://assets/icons/tool_roundabout.svg"):
		_tex_roundabout = load("res://assets/icons/tool_roundabout.svg")
	if ResourceLoader.exists("res://assets/icons/tool_highway.svg"):
		_tex_highway = load("res://assets/icons/tool_highway.svg")
	if ResourceLoader.exists("res://assets/fonts/BeVietnamPro-Bold.ttf"):
		_font_bold = load("res://assets/fonts/BeVietnamPro-Bold.ttf")


func _build_tooltip() -> void:
	_tooltip_label = Label.new()
	add_child(_tooltip_label)
	_tooltip_label.position = Vector2(0, -24)
	_tooltip_label.size = Vector2(BAR_SIZE.x, 20)
	_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tooltip_label.add_theme_font_size_override("font_size", 12)
	_tooltip_label.add_theme_color_override("font_color", COLOR_INK)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.visible = false


func _connect_signals() -> void:
	EventBus.edge_budget_changed.connect(_on_budget_changed)
	EventBus.active_tool_changed.connect(_on_tool_changed)
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	if EventBus.has_signal("inventory_changed"):
		EventBus.connect("inventory_changed", _on_inventory_changed)
	if EventBus.has_signal("ferry_inventory_changed"):
		EventBus.ferry_inventory_changed.connect(_on_ferry_inventory_legacy)
	if EventBus.has_signal("ferry_routes_changed"):
		EventBus.ferry_routes_changed.connect(_on_ferry_routes_legacy)
	mouse_exited.connect(func() -> void:
		hovered_slot = -1
		_tooltip_label.visible = false
		queue_redraw()
	)


func _on_game_started() -> void:
	active_tool = TOOL_ROAD
	draft_open = false
	_refresh_all_counts()
	_update_auto_hide(true)
	queue_redraw()


func _on_game_state_changed(state: int) -> void:
	# Types.GameState.CARD_DRAFT có thể được C thêm ở giá trị >= 6
	var is_draft := false
	if "CARD_DRAFT" in Types.GameState:
		is_draft = (state == Types.GameState.get("CARD_DRAFT"))
	draft_open = is_draft
	_update_auto_hide(false)


func set_draft_open(open: bool) -> void:
	if draft_open == open:
		return
	draft_open = open
	_update_auto_hide(false)


func _refresh_all_counts() -> void:
	# 1. Road budget snapshot từ GraphManager (không đọc inventory token)
	if has_node("/root/GraphManager"):
		if GraphManager.has_method("get_edge_budget"):
			var b: Dictionary = GraphManager.call("get_edge_budget")
			roads_left = maxi(0, int(b.get("limit", Config.EDGE_LIMIT_START)) - int(b.get("used", 0)))
		else:
			roads_left = Config.EDGE_LIMIT_START

	# 2. Inventory 4 token đặt được từ GameManager.get_inventory(reward_id)
	var use_gm_inv := has_node("/root/GameManager") and GameManager.has_method("get_inventory")
	for rid in counts.keys():
		if use_gm_inv:
			counts[rid] = maxi(0, int(GameManager.call("get_inventory", rid)))
		elif rid == REWARD_FERRY and has_node("/root/GraphManager") and GraphManager.has_method("get_ferries_available"):
			counts[rid] = maxi(0, int(GraphManager.get_ferries_available()))
		else:
			counts[rid] = 0
	queue_redraw()


func _on_budget_changed(used: int, limit: int) -> void:
	roads_left = maxi(0, limit - used)
	queue_redraw()


func _on_inventory_changed(reward_id: int, available: int) -> void:
	if counts.has(reward_id):
		counts[reward_id] = maxi(0, available)
		queue_redraw()


func _on_ferry_inventory_legacy(available: int, _total: int) -> void:
	if has_node("/root/GameManager") and GameManager.has_method("get_inventory"):
		return
	counts[REWARD_FERRY] = maxi(0, available)
	queue_redraw()


func _on_ferry_routes_legacy() -> void:
	if has_node("/root/GameManager") and GameManager.has_method("get_inventory"):
		return
	if has_node("/root/GraphManager") and GraphManager.has_method("get_ferries_available"):
		counts[REWARD_FERRY] = maxi(0, int(GraphManager.get_ferries_available()))
		queue_redraw()


func _on_tool_changed(tool_id: int) -> void:
	active_tool = tool_id
	_update_auto_hide(false)
	queue_redraw()


func _is_placing_item() -> bool:
	return active_tool in [TOOL_FERRY, TOOL_TRAFFIC_LIGHT, TOOL_ROUNDABOUT, TOOL_HIGHWAY]


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_update_auto_hide(false)


func _cursor_in_reveal_zone() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var vp_size := vp.get_visible_rect().size
	var mp := vp.get_mouse_position()
	var zone_w := BAR_SIZE.x + HOVER_ZONE_PAD_X * 2.0
	var left := (vp_size.x - zone_w) * 0.5
	var top := vp_size.y - HOVER_ZONE_HEIGHT
	return mp.x >= left and mp.x <= left + zone_w and mp.y >= top and mp.y <= vp_size.y


func _update_auto_hide(immediate: bool) -> void:
	var want_show: bool = draft_open or _is_placing_item() or _cursor_in_reveal_zone()
	if want_show == _bar_shown and not immediate:
		return
	_bar_shown = want_show
	if not _bar_shown:
		hovered_slot = -1
		if _tooltip_label != null:
			_tooltip_label.visible = false
	var target_y := -SHOWN_MARGIN_BOTTOM if _bar_shown else HIDDEN_OFFSET_Y
	if immediate or not is_inside_tree():
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		_apply_slide_offsets(target_y)
		queue_redraw()
		return
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(self, "offset_top", target_y - BAR_SIZE.y, SLIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(self, "offset_bottom", target_y, SLIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _apply_slide_offsets(bottom_offset: float) -> void:
	offset_top = bottom_offset - BAR_SIZE.y
	offset_bottom = bottom_offset


func _count_for_slot(idx: int) -> int:
	var def: Dictionary = SLOT_DEFS[idx]
	if def.tool == TOOL_ROAD:
		return roads_left
	return int(counts.get(def.reward, 0))


func _slot_disabled(idx: int) -> bool:
	var def: Dictionary = SLOT_DEFS[idx]
	if def.tool == TOOL_ROAD:
		return false
	return _count_for_slot(idx) <= 0 and active_tool != def.tool


func _slot_at(pos: Vector2) -> int:
	for i in SLOT_DEFS.size():
		var def: Dictionary = SLOT_DEFS[i]
		var r := 24.0 if def.diamond else 22.0
		if pos.distance_to(def.pos) <= r:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var slot := _slot_at(event.position)
		if slot != hovered_slot:
			hovered_slot = slot
			_update_tooltip()
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var slot := _slot_at(event.position)
		if slot == -1:
			accept_event()
			return
		if _slot_disabled(slot):
			accept_event()
			return
		var tool_id: int = SLOT_DEFS[slot].tool
		if active_tool == tool_id and tool_id != TOOL_ROAD:
			EventBus.active_tool_changed.emit(TOOL_ROAD)
		else:
			EventBus.active_tool_changed.emit(tool_id)
		accept_event()


func _update_tooltip() -> void:
	if _tooltip_label == null:
		return
	if hovered_slot < 0 or not _bar_shown:
		_tooltip_label.visible = false
		return
	var def: Dictionary = SLOT_DEFS[hovered_slot]
	var cnt := _count_for_slot(hovered_slot)
	_tooltip_label.text = "%s (%d)" % [def.label, cnt]
	_tooltip_label.visible = true


func _draw() -> void:
	# Thanh tay cầm nhỏ phía trên mép (vẫn thấy gọn khi toolbar trượt ẩn)
	var handle_pos := Vector2((BAR_SIZE.x - HANDLE_SIZE.x) * 0.5, -10.0)
	var handle_col := COLOR_CYAN if _bar_shown else COLOR_BORDER
	draw_rect(Rect2(handle_pos, HANDLE_SIZE), handle_col, true)

	# Nền thanh toolbar bo tròn tối màu đồng bộ với E
	var pill_rect := Rect2(Vector2.ZERO, BAR_SIZE)
	_draw_rounded_panel(pill_rect, 20.0, COLOR_BG, COLOR_BORDER)

	# Vẽ 5 công cụ
	for i in SLOT_DEFS.size():
		var def: Dictionary = SLOT_DEFS[i]
		var tool_id: int = int(def.tool)
		var cnt: int = _count_for_slot(i)
		var is_hover: bool = (hovered_slot == i)
		var is_active: bool = (active_tool == tool_id)
		var is_disabled: bool = _slot_disabled(i)
		var accent: Color = def.accent
		if bool(def.diamond):
			_draw_road_diamond(def.pos, 21.0, _tex_road, cnt, is_hover, is_active, accent)
		else:
			var tex := _texture_for_tool(tool_id)
			_draw_circle_tool(def.pos, SLOT_RADIUS, tool_id, tex, cnt, is_hover, is_active, is_disabled, accent)


func _texture_for_tool(tool_id: int) -> Texture2D:
	match tool_id:
		TOOL_ROAD: return _tex_road
		TOOL_FERRY: return _tex_ferry
		TOOL_TRAFFIC_LIGHT: return _tex_traffic
		TOOL_ROUNDABOUT: return _tex_roundabout
		TOOL_HIGHWAY: return _tex_highway
	return null


func _draw_rounded_panel(rect: Rect2, radius: float, fill: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	sb.shadow_color = COLOR_SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, rect)


func _draw_road_diamond(center: Vector2, half_size: float, tex: Texture2D, count: int, hovered: bool, active: bool, accent: Color) -> void:
	var s := half_size * 1.08
	var pts := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s, 0),
		center + Vector2(0, s),
		center + Vector2(-s, 0),
	])
	var shadow_pts := PackedVector2Array([
		center + Vector2(0, -s + 2.5),
		center + Vector2(s, 2.5),
		center + Vector2(0, s + 2.5),
		center + Vector2(-s, 2.5),
	])
	draw_colored_polygon(shadow_pts, COLOR_SHADOW)

	var bg_col := COLOR_BG_SELECTED if active else (COLOR_BG_HOVER if hovered else Color("#182838"))
	var border_col := accent if active else (COLOR_INK if hovered else COLOR_BORDER)
	var fg_col := accent if active else COLOR_INK

	draw_colored_polygon(pts, bg_col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), border_col, 2.2 if (active or hovered) else 1.2)

	if tex != null:
		var tex_size := Vector2(24, 24)
		draw_texture_rect(tex, Rect2(center - tex_size * 0.5, tex_size), false, fg_col)

	_draw_badge(center + Vector2(16, -13), count, active, false, accent)


func _draw_circle_tool(center: Vector2, radius: float, tool_id: int, tex: Texture2D, count: int, hovered: bool, active: bool, disabled: bool, accent: Color) -> void:
	if not disabled:
		draw_circle(center + Vector2(0, 2), radius, COLOR_SHADOW)

	var bg_col := COLOR_BG_DISABLED if disabled else (COLOR_BG_SELECTED if active else (COLOR_BG_HOVER if hovered else Color("#162535")))
	var border_col := COLOR_BORDER_DISABLED if disabled else (accent if active else (COLOR_INK if hovered else COLOR_BORDER))
	var fg_col := COLOR_MUTED * Color(1, 1, 1, 0.45) if disabled else (accent if active else COLOR_INK)

	draw_circle(center, radius, bg_col)
	draw_arc(center, radius, 0.0, TAU, 32, border_col, 2.2 if (active or hovered) and not disabled else 1.2)

	if tex != null:
		var tex_size := Vector2(22, 22)
		draw_texture_rect(tex, Rect2(center - tex_size * 0.5, tex_size), false, fg_col)
	elif tool_id == TOOL_HIGHWAY:
		_draw_highway_vector_icon(center, fg_col)

	_draw_badge(center + Vector2(14, -14), count, active, disabled, accent)


func _draw_highway_vector_icon(center: Vector2, col: Color) -> void:
	# Biểu tượng đường cao tốc 2 làn cong đồng bộ style vector phẳng
	var p0 := center + Vector2(-9, 6)
	var p1 := center + Vector2(-2, -6)
	var p2 := center + Vector2(9, -6)
	draw_polyline(PackedVector2Array([p0, p1, p2]), col, 2.6, true)
	draw_polyline(PackedVector2Array([p0 + Vector2(3, 3), p1 + Vector2(2, 3), p2 + Vector2(0, 3)]), col, 2.6, true)
	draw_line(center + Vector2(-4, 7), center + Vector2(-4, 10), col, 2.0)
	draw_line(center + Vector2(5, -2), center + Vector2(5, 3), col, 2.0)


func _draw_badge(pos: Vector2, count: int, active: bool, disabled: bool, accent: Color) -> void:
	var r := 10.0
	var bg := COLOR_BG_DISABLED if disabled else (accent if active else Color("#0c1520"))
	var fg := COLOR_MUTED * Color(1, 1, 1, 0.55) if disabled else (Color("#0c1520") if active else COLOR_INK)
	var border := COLOR_BORDER_DISABLED if disabled else (accent if active else COLOR_BORDER)

	draw_circle(pos + Vector2(0, 1), r, COLOR_SHADOW)
	draw_circle(pos, r, bg)
	draw_arc(pos, r, 0.0, TAU, 24, border, 1.2)

	var font: Font = _font_bold if _font_bold != null else ThemeDB.fallback_font
	var text := str(count)
	var font_size: int = 11 if count < 100 else 9
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos: Vector2 = pos + Vector2(-text_size.x * 0.5, text_size.y * 0.34)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, fg)

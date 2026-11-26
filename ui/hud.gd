extends Control
## Gameplay HUD tối giản, tối màu, icon-first (Owner: B).
## - Responsive theo viewport 16:10 (1920×1200 / 1280×800) và 16:9 (1280×720), không kéo giãn map.
## - Điểm +1 mỗi SOS; bỏ quỹ/shop, số wave, số SOS thất bại dạng số; dùng tối đa 3 chấm thất bại (pips).
## - Cụm đồng hồ góc trên phải gom Pause/Play + tốc độ x1/x2/x3 (vẫn dùng được khi pause).
## - Nút mũi tên góc trên trái mở menu gọn (Chơi lại / Menu chính).
## - Cạnh phải giữa có nút Vẽ và Xóa (click/kéo; giữ chuột phải làm shortcut).
## - Giữa cạnh dưới là ToolBar vật phẩm tự ẩn/hiện khi hover.
## - Bỏ banner dài thường; cảnh báo lũ/rút nước/phà dùng chip icon ngắn gọn.

signal pause_pressed

const Style = preload("res://ui/style.gd")
const ToolBarScript = preload("res://ui/tool_bar.gd")

# Hợp đồng ToolId (docs/endless_gameplay_team_assignments.md mục 2)
const TOOL_ROAD := 0
const TOOL_FERRY := 1
const TOOL_TRAFFIC_LIGHT := 2
const TOOL_ROUNDABOUT := 3
const TOOL_HIGHWAY := 4
const TOOL_ERASE := 5

# Bảng màu tối đồng bộ với Card Draft (Owner: E)
const COLOR_BG := Color("#121e2b")
const COLOR_BG_HOVER := Color("#1a2b3d")
const COLOR_BG_SELECTED := Color("#192d40")
const COLOR_INNER := Color("#0c1520")
const COLOR_BORDER := Color("#2a4259")
const COLOR_INK := Color("#f2f8ff")
const COLOR_MUTED := Color("#8ea8be")
const COLOR_GOLD := Color("#ffd23f")
const COLOR_CYAN := Color("#4fd3ec")
const COLOR_MINT := Color("#5ee3b0")
const COLOR_WARN := Color("#ff8a3d")
const COLOR_DANGER := Color("#ff6b6b")

const BADGE_SIZE := Vector2(96, 24)
const BADGE_OFFSET := 52.0
const RECEDE_CHIP_TIME := 3.0
const FERRY_CHIP_TIME := 2.8

const FPS_WINDOW := 0.5
const FPS_LOG_EVERY := 5.0
const SLOW_FRAME_MS := 50.0


# 3 chấm trạng thái thất bại: phân biệt rõ chưa dùng / đã dùng (có dấu X) / gần thua (nhấp nháy) / thua.
class FailurePips extends Control:
	var failed_count := 0
	var max_failed := Config.MAX_FAILED
	var _pulse := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(58, 22)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_failed(count: int, maximum: int) -> void:
		failed_count = clampi(count, 0, maxi(1, maximum))
		max_failed = clampi(maximum, 1, 3)
		queue_redraw()

	func _process(delta: float) -> void:
		if failed_count == max_failed - 1 and failed_count > 0:
			_pulse += delta * 5.0
			queue_redraw()
		elif _pulse != 0.0:
			_pulse = 0.0

	func _draw() -> void:
		var n := mini(max_failed, 3)
		var spacing := 18.0
		var start_x := (size.x - spacing * float(n - 1)) * 0.5
		var cy := size.y * 0.5
		var r := 6.0
		var near_loss := (failed_count == n - 1 and failed_count > 0)
		var is_lost := (failed_count >= n)
		for i in n:
			var center := Vector2(start_x + float(i) * spacing, cy)
			if i < failed_count:
				# Đã dùng (SOS thất bại): lõi đỏ + dấu X sáng (không chỉ dựa vào màu)
				draw_circle(center, r, COLOR_DANGER)
				draw_arc(center, r, 0.0, TAU, 20, COLOR_INK if is_lost else Color("#ffb3b3"), 1.4)
				var d := 2.8
				draw_line(center + Vector2(-d, -d), center + Vector2(d, d), COLOR_INNER, 1.8, true)
				draw_line(center + Vector2(d, -d), center + Vector2(-d, d), COLOR_INNER, 1.8, true)
			else:
				# Chưa dùng: lõi tối, viền sáng; nếu là chấm cuối cùng sắp thua thì nhấp nháy cam
				var border_col := COLOR_BORDER.lightened(0.25)
				var width := 1.5
				if near_loss and i == n - 1:
					var t := 0.5 + 0.5 * sin(_pulse)
					border_col = COLOR_WARN.lerp(COLOR_INK, t * 0.45)
					width = 2.0
				draw_circle(center, r, COLOR_INNER)
				draw_arc(center, r, 0.0, TAU, 20, border_col, width)


var score_label: Label
var failure_pips: FailurePips
var water_label: Label
var time_label: Label
var pause_btn: Button
var speed_buttons: Dictionary = {}  # speed (1/2/3) -> Button
var menu_arrow_btn: Button
var menu_dropdown: PanelContainer
var draw_mode_btn: Button
var erase_mode_btn: Button
var alert_chip: PanelContainer
var alert_icon_label: Label
var alert_text_label: Label
var tool_bar: Control

var fps_label: Label
var _fps_last_us := 0
var _fps_frames := 0
var _fps_time := 0.0
var _fps_worst := 0.0
var _fps_log := false
var _log_frames := 0
var _log_time := 0.0
var _log_worst := 0.0
var _log_min := INF

var countdown: float = Config.WAVE_DURATION
var enabled: bool = false
var badges: Dictionary = {}  # hub_id -> [food Label, medical Label]

var _active_tool: int = TOOL_ROAD
var _last_draw_tool: int = TOOL_ROAD
var _last_level := 0.0
var _receding := false
var _warn_time := 0.0
var _recede_time := 0.0
var _ferry_time := 0.0
var _prev_routes_count := 0
var _last_paused := false
var _last_speed := 1
var _alert_mode := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_left_menu()
	_build_fps()
	_build_top_center_status()
	_build_alert_chip()
	_build_clock_controls()
	_build_right_mode_dock()
	_build_tool_bar()
	_connect_signals()
	_sync_mode_buttons()
	_sync_clock_buttons(true)


func _style_pill(bg: Color, border: Color, radius: int = 12, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = bw
	sb.border_width_right = bw
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	return sb


func _make_icon_button(caption: String, min_size: Vector2, font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_color_override("font_hover_color", COLOR_INK)
	b.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	b.add_theme_stylebox_override("normal", _style_pill(COLOR_BG, COLOR_BORDER, 10, 1))
	b.add_theme_stylebox_override("hover", _style_pill(COLOR_BG_HOVER, COLOR_CYAN, 10, 1))
	b.add_theme_stylebox_override("pressed", _style_pill(COLOR_BG_SELECTED, COLOR_GOLD, 10, 2))
	return b


# 1. Mũi tên góc trên trái mở Chơi lại / Menu chính
func _build_top_left_menu() -> void:
	menu_arrow_btn = _make_icon_button("‹", Vector2(38, 38), 22)
	add_child(menu_arrow_btn)
	menu_arrow_btn.anchor_left = 0.0
	menu_arrow_btn.anchor_top = 0.0
	menu_arrow_btn.offset_left = 14
	menu_arrow_btn.offset_top = 12
	menu_arrow_btn.offset_right = 52
	menu_arrow_btn.offset_bottom = 50
	menu_arrow_btn.tooltip_text = "Tùy chọn ván chơi"
	menu_arrow_btn.pressed.connect(_toggle_menu_dropdown)

	menu_dropdown = PanelContainer.new()
	add_child(menu_dropdown)
	menu_dropdown.anchor_left = 0.0
	menu_dropdown.anchor_top = 0.0
	menu_dropdown.offset_left = 14
	menu_dropdown.offset_top = 56
	menu_dropdown.offset_right = 172
	menu_dropdown.offset_bottom = 148
	menu_dropdown.add_theme_stylebox_override("panel", _style_pill(COLOR_BG, COLOR_BORDER, 12, 1))
	menu_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_dropdown.visible = false

	var margin := MarginContainer.new()
	menu_dropdown.add_child(margin)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	vbox.add_theme_constant_override("separation", 6)

	var restart_btn := _make_icon_button("↻  Chơi lại", Vector2(140, 34), 14)
	restart_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	restart_btn.pressed.connect(func() -> void:
		menu_dropdown.visible = false
		GameManager.restart()
	)
	vbox.add_child(restart_btn)

	var menu_btn := _make_icon_button("⌂  Menu chính", Vector2(140, 34), 14)
	menu_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu_btn.pressed.connect(func() -> void:
		menu_dropdown.visible = false
		GameManager.exit_to_menu()
	)
	vbox.add_child(menu_btn)


func _toggle_menu_dropdown() -> void:
	menu_dropdown.visible = not menu_dropdown.visible
	menu_arrow_btn.text = "⌄" if menu_dropdown.visible else "‹"


func _build_fps() -> void:
	fps_label = Label.new()
	add_child(fps_label)
	fps_label.anchor_left = 0.0
	fps_label.anchor_top = 0.0
	fps_label.offset_left = 60
	fps_label.offset_top = 20
	fps_label.offset_right = 170
	fps_label.offset_bottom = 42
	fps_label.text = ""
	fps_label.add_theme_font_size_override("font_size", 11)
	fps_label.add_theme_color_override("font_color", COLOR_MUTED)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_last_us = Time.get_ticks_usec()
	_fps_log = OS.is_debug_build()
	if OS.has_feature("web"):
		_fps_log = _fps_log or bool(JavaScriptBridge.eval("location.search.indexOf('fpslog') >= 0", true))
	fps_label.visible = _fps_log


# 2. Cụm trạng thái giữa trên: Điểm (+1/SOS), 3 chấm thất bại, mực nước gọn
func _build_top_center_status() -> void:
	var pill := PanelContainer.new()
	add_child(pill)
	pill.anchor_left = 0.5
	pill.anchor_right = 0.5
	pill.anchor_top = 0.0
	pill.offset_left = -132
	pill.offset_right = 132
	pill.offset_top = 12
	pill.offset_bottom = 50
	pill.add_theme_stylebox_override("panel", _style_pill(Color(0.07, 0.12, 0.17, 0.92), COLOR_BORDER, 19, 1))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	pill.add_child(margin)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	margin.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	score_label = Label.new()
	row.add_child(score_label)
	score_label.text = "★ 0"
	score_label.add_theme_font_size_override("font_size", 17)
	score_label.add_theme_color_override("font_color", COLOR_GOLD)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(_make_vsep())

	failure_pips = FailurePips.new()
	row.add_child(failure_pips)

	row.add_child(_make_vsep())

	water_label = Label.new()
	row.add_child(water_label)
	water_label.text = "≈ 0%"
	water_label.add_theme_font_size_override("font_size", 15)
	water_label.add_theme_color_override("font_color", COLOR_CYAN)
	water_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	water_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_vsep() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(1, 18)
	sep.color = COLOR_BORDER
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


# 3. Chip cảnh báo gọn (thay thế banner dài cũ, có cả icon + chữ ngắn)
func _build_alert_chip() -> void:
	alert_chip = PanelContainer.new()
	add_child(alert_chip)
	alert_chip.anchor_left = 0.5
	alert_chip.anchor_right = 0.5
	alert_chip.anchor_top = 0.0
	alert_chip.offset_left = -84
	alert_chip.offset_right = 84
	alert_chip.offset_top = 58
	alert_chip.offset_bottom = 86
	alert_chip.add_theme_stylebox_override("panel", _style_pill(COLOR_BG, COLOR_WARN, 14, 1))
	alert_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_chip.visible = false

	var margin := MarginContainer.new()
	alert_chip.add_child(margin)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	margin.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	alert_icon_label = Label.new()
	row.add_child(alert_icon_label)
	alert_icon_label.text = "▲"
	alert_icon_label.add_theme_font_size_override("font_size", 13)
	alert_icon_label.add_theme_color_override("font_color", COLOR_WARN)
	alert_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	alert_text_label = Label.new()
	row.add_child(alert_text_label)
	alert_text_label.text = "SẮP NGẬP"
	alert_text_label.add_theme_font_size_override("font_size", 13)
	alert_text_label.add_theme_color_override("font_color", COLOR_INK)
	alert_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


# 4. Cụm đồng hồ gọn góc trên phải: MM:SS + Pause/Play + x1 / x2 / x3
func _build_clock_controls() -> void:
	var dock := PanelContainer.new()
	add_child(dock)
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.0
	dock.offset_left = -258
	dock.offset_right = -14
	dock.offset_top = 12
	dock.offset_bottom = 50
	dock.add_theme_stylebox_override("panel", _style_pill(Color(0.07, 0.12, 0.17, 0.92), COLOR_BORDER, 19, 1))
	dock.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	dock.add_child(margin)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	var row := HBoxContainer.new()
	margin.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)

	time_label = Label.new()
	row.add_child(time_label)
	time_label.custom_minimum_size = Vector2(48, 0)
	time_label.text = "02:00"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", COLOR_INK)
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	pause_btn = _make_icon_button("II", Vector2(32, 28), 13)
	pause_btn.tooltip_text = "Tạm dừng / Tiếp tục (Space)"
	pause_btn.pressed.connect(_on_pause_toggle)
	row.add_child(pause_btn)

	for spd in [1, 2, 3]:
		var btn := _make_icon_button("x%d" % spd, Vector2(34, 28), 13)
		btn.tooltip_text = "Tốc độ x%d (F)" % spd
		var target_spd: int = spd
		btn.pressed.connect(func() -> void: _select_speed(target_spd))
		row.add_child(btn)
		speed_buttons[spd] = btn


func _on_pause_toggle() -> void:
	if GameManager.state == Types.GameState.PAUSED:
		GameManager.resume_game()
	else:
		# Gọi API công khai; giữ pause_pressed để tương thích ui_root hiện tại
		GameManager.pause_game()
		if GameManager.state != Types.GameState.PAUSED:
			pause_pressed.emit()
	_sync_clock_buttons(true)


func _select_speed(target_speed: int) -> void:
	if GameManager.state == Types.GameState.PAUSED:
		GameManager.resume_game()
	for _i in 4:
		if GameManager.game_speed == target_speed:
			break
		GameManager.cycle_speed()
	_sync_clock_buttons(true)


func _sync_clock_buttons(force: bool = false) -> void:
	var is_paused: bool = GameManager.state == Types.GameState.PAUSED
	var cur_speed: int = GameManager.game_speed
	if not force and is_paused == _last_paused and cur_speed == _last_speed:
		return
	_last_paused = is_paused
	_last_speed = cur_speed

	if pause_btn != null:
		pause_btn.text = "▶" if is_paused else "II"
		var p_bg := COLOR_BG_SELECTED if is_paused else COLOR_INNER
		var p_border := COLOR_GOLD if is_paused else COLOR_BORDER
		pause_btn.add_theme_stylebox_override("normal", _style_pill(p_bg, p_border, 8, 2 if is_paused else 1))
		pause_btn.add_theme_color_override("font_color", COLOR_GOLD if is_paused else COLOR_INK)

	for spd in speed_buttons:
		var btn: Button = speed_buttons[spd]
		var active: bool = (not is_paused) and (cur_speed == spd)
		var bg := COLOR_BG_SELECTED if active else COLOR_INNER
		var border := COLOR_CYAN if active else COLOR_BORDER
		btn.add_theme_stylebox_override("normal", _style_pill(bg, border, 8, 2 if active else 1))
		btn.add_theme_color_override("font_color", COLOR_GOLD if active else COLOR_MUTED)


# 5. Lựa chọn Vẽ / Xóa ở cạnh phải giữa
func _build_right_mode_dock() -> void:
	var dock := PanelContainer.new()
	add_child(dock)
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.5
	dock.anchor_bottom = 0.5
	dock.offset_left = -64
	dock.offset_right = -14
	dock.offset_top = -54
	dock.offset_bottom = 54
	dock.add_theme_stylebox_override("panel", _style_pill(Color(0.07, 0.12, 0.17, 0.92), COLOR_BORDER, 16, 1))
	dock.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	dock.add_child(margin)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)

	draw_mode_btn = _make_icon_button("✎", Vector2(38, 40), 18)
	draw_mode_btn.tooltip_text = "Chế độ Vẽ (Chuột trái)"
	draw_mode_btn.pressed.connect(func() -> void:
		EventBus.active_tool_changed.emit(_last_draw_tool)
	)
	vbox.add_child(draw_mode_btn)

	erase_mode_btn = _make_icon_button("✕", Vector2(38, 40), 17)
	erase_mode_btn.tooltip_text = "Chế độ Xóa (Click/kéo hoặc giữ Chuột phải)"
	erase_mode_btn.pressed.connect(func() -> void:
		EventBus.active_tool_changed.emit(TOOL_ERASE)
	)
	vbox.add_child(erase_mode_btn)


func _sync_mode_buttons() -> void:
	var is_erase := (_active_tool == TOOL_ERASE)
	if draw_mode_btn != null:
		var draw_active := not is_erase
		draw_mode_btn.add_theme_stylebox_override(
			"normal",
			_style_pill(COLOR_BG_SELECTED if draw_active else COLOR_INNER, COLOR_GOLD if draw_active else COLOR_BORDER, 10, 2 if draw_active else 1)
		)
		draw_mode_btn.add_theme_color_override("font_color", COLOR_GOLD if draw_active else COLOR_MUTED)
	if erase_mode_btn != null:
		erase_mode_btn.add_theme_stylebox_override(
			"normal",
			_style_pill(Color(0.28, 0.10, 0.12, 0.95) if is_erase else COLOR_INNER, COLOR_DANGER if is_erase else COLOR_BORDER, 10, 2 if is_erase else 1)
		)
		erase_mode_btn.add_theme_color_override("font_color", COLOR_DANGER if is_erase else COLOR_MUTED)


# 6. Toolbar vật phẩm tự ẩn ở giữa cạnh dưới
func _build_tool_bar() -> void:
	tool_bar = ToolBarScript.new()
	tool_bar.name = "ToolBar"
	add_child(tool_bar)


func _connect_signals() -> void:
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.score_changed.connect(_on_score)
	EventBus.failed_changed.connect(_on_failed)
	EventBus.wave_started.connect(_on_wave)
	EventBus.break_started.connect(_on_break)
	EventBus.water_level_changed.connect(_on_water)
	EventBus.stock_changed.connect(_on_stock)
	EventBus.flood_warning.connect(_on_warning)
	EventBus.active_tool_changed.connect(_on_tool_changed)
	if EventBus.has_signal("ferry_routes_changed"):
		EventBus.ferry_routes_changed.connect(_on_ferry_routes)


func _on_game_started() -> void:
	menu_dropdown.visible = false
	menu_arrow_btn.text = "‹"
	_active_tool = TOOL_ROAD
	_last_draw_tool = TOOL_ROAD
	_warn_time = 0.0
	_recede_time = 0.0
	_ferry_time = 0.0
	_last_level = 0.0
	_receding = false
	_prev_routes_count = 0
	failure_pips.set_failed(0, Config.MAX_FAILED)
	score_label.text = "★ 0"
	_sync_mode_buttons()
	_sync_clock_buttons(true)
	_build_badges()


func _on_game_state_changed(state: int) -> void:
	if state == Types.GameState.MENU:
		menu_dropdown.visible = false
		menu_arrow_btn.text = "‹"
	_sync_clock_buttons(true)


func _on_tool_changed(tool_id: int) -> void:
	_active_tool = tool_id
	if tool_id != TOOL_ERASE:
		_last_draw_tool = tool_id
	_sync_mode_buttons()


# Nhãn tồn kho gọn dưới mỗi Kho trên bản đồ
func _build_badges() -> void:
	for pair in badges.values():
		if is_instance_valid(pair[0].get_parent()):
			pair[0].get_parent().queue_free()
	badges.clear()
	for id in GraphManager.get_node_ids():
		var n = GraphManager.get_map_node(id)
		if n == null or n.kind != Types.NodeKind.HUB:
			continue
		var at: Vector2 = n.pos + Vector2(-BADGE_SIZE.x / 2.0, BADGE_OFFSET)
		var pill := Style.rect(self, at.x, at.y, BADGE_SIZE.x, BADGE_SIZE.y, Color(0.07, 0.12, 0.17, 0.90), COLOR_BORDER, 12)
		var food := Style.text(pill, "", 6, 0, 42, BADGE_SIZE.y, 13, COLOR_GOLD, true)
		var med := Style.text(pill, "", 48, 0, 42, BADGE_SIZE.y, 13, COLOR_CYAN, true)
		food.autowrap_mode = TextServer.AUTOWRAP_OFF
		med.autowrap_mode = TextServer.AUTOWRAP_OFF
		badges[id] = [food, med]
		pill.set_meta("anchor", n.pos + Vector2(0.0, BADGE_OFFSET))
		for supply in [Types.SupplyType.FOOD, Types.SupplyType.MEDICAL]:
			_on_stock(id, supply, RescueManager.get_stock(id, supply))


func _tick_fps() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _fps_last_us) / 1000.0
	_fps_last_us = now
	if _fps_log and ms > SLOW_FRAME_MS:
		print("[FPS] khung chậm %.0f ms ở giây %.1f" % [ms, now / 1000000.0])
	_fps_frames += 1
	_fps_time += ms / 1000.0
	_fps_worst = maxf(_fps_worst, ms)
	if _fps_time < FPS_WINDOW:
		return
	var fps := _fps_frames / _fps_time
	if fps_label.visible:
		fps_label.text = "%d FPS" % roundi(fps)
		fps_label.add_theme_color_override("font_color", COLOR_MUTED if fps >= 50.0 else (COLOR_GOLD if fps >= 30.0 else COLOR_WARN))
	if _fps_log:
		_log_frames += _fps_frames
		_log_time += _fps_time
		_log_worst = maxf(_log_worst, _fps_worst)
		_log_min = minf(_log_min, fps)
		if _log_time >= FPS_LOG_EVERY:
			print("[FPS] giây %.0f: trung bình %.1f, thấp nhất %.1f, khung lâu nhất %.0f ms" % [now / 1000000.0, _log_frames / _log_time, _log_min, _log_worst])
			_log_frames = 0
			_log_time = 0.0
			_log_worst = 0.0
			_log_min = INF
	_fps_frames = 0
	_fps_time = 0.0
	_fps_worst = 0.0


func _process(delta: float) -> void:
	var xf := get_viewport().get_canvas_transform()
	for pair in badges.values():
		var pill: Control = pair[0].get_parent()
		if is_instance_valid(pill):
			pill.position = xf * (pill.get_meta("anchor") as Vector2) - Vector2(BADGE_SIZE.x * 0.5, 0.0)
	_tick_fps()
	_sync_clock_buttons(false)

	if not enabled or GameManager.state == Types.GameState.PAUSED:
		return
	if countdown > 0.0:
		countdown = maxf(0.0, countdown - delta)
	var sec := int(ceil(countdown))
	time_label.text = "%02d:%02d" % [int(sec / 60), sec % 60]

	if _warn_time > 0.0:
		_warn_time = maxf(0.0, _warn_time - delta)
	if _recede_time > 0.0:
		_recede_time = maxf(0.0, _recede_time - delta)
	if _ferry_time > 0.0:
		_ferry_time = maxf(0.0, _ferry_time - delta)
	_update_alert_chip()


func _update_alert_chip() -> void:
	if _warn_time > 0.0:
		alert_chip.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.55) < 0.40
		if _alert_mode != "warn":
			_alert_mode = "warn"
			alert_icon_label.text = "▲"
			alert_icon_label.add_theme_color_override("font_color", COLOR_WARN)
			alert_text_label.text = "SẮP NGẬP"
			alert_chip.add_theme_stylebox_override("panel", _style_pill(Color(0.28, 0.08, 0.06, 0.94), COLOR_WARN, 14, 1))
	elif _recede_time > 0.0:
		alert_chip.visible = true
		if _alert_mode != "recede":
			_alert_mode = "recede"
			alert_icon_label.text = "↓"
			alert_icon_label.add_theme_color_override("font_color", COLOR_MINT)
			alert_text_label.text = "NƯỚC RÚT"
			alert_chip.add_theme_stylebox_override("panel", _style_pill(Color(0.06, 0.20, 0.18, 0.92), COLOR_MINT, 14, 1))
	elif _ferry_time > 0.0:
		alert_chip.visible = true
		if _alert_mode != "ferry":
			_alert_mode = "ferry"
			alert_icon_label.text = "◆"
			alert_icon_label.add_theme_color_override("font_color", COLOR_CYAN)
			alert_text_label.text = "PHÀ MỚI"
			alert_chip.add_theme_stylebox_override("panel", _style_pill(Color(0.06, 0.18, 0.25, 0.92), COLOR_CYAN, 14, 1))
	else:
		alert_chip.visible = false
		_alert_mode = ""


func _on_ferry_routes() -> void:
	if not has_node("/root/GraphManager"):
		return
	var count: int = GraphManager.get_ferry_routes().size()
	if count > _prev_routes_count:
		_ferry_time = FERRY_CHIP_TIME
	_prev_routes_count = count


func _on_score(value: int) -> void:
	score_label.text = "★ %d" % value
	score_label.pivot_offset = score_label.size * 0.5
	var tw := score_label.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	score_label.scale = Vector2(1.22, 1.22)
	tw.tween_property(score_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_failed(count: int, maximum: int) -> void:
	failure_pips.set_failed(count, maximum)


func _on_wave(_index: int) -> void:
	countdown = Config.WAVE_DURATION


func _on_break(seconds: float) -> void:
	countdown = seconds


func _on_water(level: float) -> void:
	if level < _last_level - 0.0001 and not _receding:
		_receding = true
		_recede_time = RECEDE_CHIP_TIME
	elif level > _last_level + 0.0001 or level <= 0.0:
		_receding = false
	_last_level = level
	var prefix := "↓ " if _receding else "≈ "
	water_label.text = "%s%d%%" % [prefix, int(round(level))]
	var col := COLOR_MINT if _receding else (COLOR_WARN if level >= 65.0 else COLOR_CYAN)
	water_label.add_theme_color_override("font_color", col)


func _on_stock(hub_id: int, supply: int, qty: int) -> void:
	if not badges.has(hub_id):
		return
	if supply == Types.SupplyType.FOOD:
		badges[hub_id][0].text = "LT %d" % qty
	else:
		badges[hub_id][1].text = "YT %d" % qty


func _on_warning(_edge_id: int, _seconds_left: float) -> void:
	_warn_time = 2.2

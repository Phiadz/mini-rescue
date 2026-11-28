extends Control
## Gameplay HUD tối giản, tối màu, icon-first (Owner: B).
## - Tỉ lệ chuẩn cho viewport 16:10 (1920×1200, thu nhỏ mượt ở 1280×800 và 1280×720).
## - Dùng icon vector sắc nét (HudIcon) + font BeVietnamPro (MSDF), không dùng ký tự Unicode dễ vỡ font.
## - Điểm +1 mỗi SOS; bỏ quỹ/shop, số wave, số SOS thất bại dạng số; dùng tối đa 3 chấm thất bại (pips).
## - Cụm đồng hồ góc trên phải gom Pause/Play + tốc độ x1/x2/x3 (hoạt động cả khi pause).
## - Nút mũi tên góc trên trái mở menu gọn (Chơi lại / Menu chính).
## - Cạnh phải giữa có nút Vẽ và Xóa (click/kéo; giữ chuột phải làm shortcut).
## - Giữa cạnh dưới là ToolBar vật phẩm tự ẩn/hiện khi hover.

signal pause_pressed

const Style = preload("res://ui/style.gd")
const ToolBarScript = preload("res://ui/tool_bar.gd")
const FONT_BOLD = preload("res://assets/fonts/BeVietnamPro-Bold.ttf")

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

const BADGE_SIZE := Vector2(138, 34)
const BADGE_OFFSET := 56.0
const RECEDE_CHIP_TIME := 3.0
const FERRY_CHIP_TIME := 2.8

const FPS_WINDOW := 0.5
const FPS_LOG_EVERY := 5.0
const SLOW_FRAME_MS := 50.0


# Biểu tượng vector sắc nét ở mọi độ phân giải, tránh lỗi rơi về fallback font.
class HudIcon extends Control:
	var kind: StringName = &""
	var color: Color = COLOR_INK

	func _init(p_kind: StringName = &"", p_size: Vector2 = Vector2(22, 22), p_color: Color = COLOR_INK) -> void:
		kind = p_kind
		color = p_color
		custom_minimum_size = p_size
		size = p_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_icon(p_kind: StringName, p_color: Color) -> void:
		if kind == p_kind and color == p_color:
			return
		kind = p_kind
		color = p_color
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.5
		match kind:
			&"chevron_left":
				var pts := PackedVector2Array([
					c + Vector2(s * 0.28, -s * 0.62),
					c + Vector2(-s * 0.34, 0.0),
					c + Vector2(s * 0.28, s * 0.62),
				])
				draw_polyline(pts, color, 2.8, true)
			&"chevron_down":
				var pts := PackedVector2Array([
					c + Vector2(-s * 0.58, -s * 0.24),
					c + Vector2(0.0, s * 0.36),
					c + Vector2(s * 0.58, -s * 0.24),
				])
				draw_polyline(pts, color, 2.8, true)
			&"restart":
				draw_arc(c, s * 0.64, -PI * 0.72, PI * 0.85, 24, color, 2.4, true)
				var tip := c + Vector2(-s * 0.44, -s * 0.54)
				draw_colored_polygon(PackedVector2Array([
					tip,
					tip + Vector2(s * 0.42, -s * 0.08),
					tip + Vector2(s * 0.12, s * 0.38),
				]), color)
			&"home":
				var roof := PackedVector2Array([
					c + Vector2(-s * 0.72, -s * 0.04),
					c + Vector2(0.0, -s * 0.72),
					c + Vector2(s * 0.72, -s * 0.04),
				])
				draw_polyline(roof, color, 2.4, true)
				var body := PackedVector2Array([
					c + Vector2(-s * 0.48, -s * 0.08),
					c + Vector2(-s * 0.48, s * 0.64),
					c + Vector2(s * 0.48, s * 0.64),
					c + Vector2(s * 0.48, -s * 0.08),
				])
				draw_polyline(body, color, 2.2, true)
			&"star":
				var pts := PackedVector2Array()
				for i in 10:
					var ang := -PI * 0.5 + float(i) * PI / 5.0
					var rad := s * (0.86 if i % 2 == 0 else 0.38)
					pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
				draw_colored_polygon(pts, color)
			&"wave":
				for row_y in [-s * 0.28, s * 0.28]:
					var pts := PackedVector2Array([
						c + Vector2(-s * 0.76, row_y + s * 0.10),
						c + Vector2(-s * 0.28, row_y - s * 0.16),
						c + Vector2(s * 0.28, row_y + s * 0.16),
						c + Vector2(s * 0.76, row_y - s * 0.10),
					])
					draw_polyline(pts, color, 2.4, true)
			&"arrow_down":
				draw_line(c + Vector2(0.0, -s * 0.68), c + Vector2(0.0, s * 0.56), color, 2.6, true)
				draw_polyline(PackedVector2Array([
					c + Vector2(-s * 0.46, s * 0.14),
					c + Vector2(0.0, s * 0.64),
					c + Vector2(s * 0.46, s * 0.14),
				]), color, 2.6, true)
			&"pause":
				var w := s * 0.30
				var h := s * 1.24
				draw_rect(Rect2(c + Vector2(-s * 0.48, -h * 0.5), Vector2(w, h)), color, true)
				draw_rect(Rect2(c + Vector2(s * 0.18, -h * 0.5), Vector2(w, h)), color, true)
			&"play":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.42, -s * 0.64),
					c + Vector2(s * 0.66, 0.0),
					c + Vector2(-s * 0.42, s * 0.64),
				]), color)
			&"pencil":
				var dir := Vector2(1.0, -1.0).normalized()
				var perp := Vector2(dir.y, -dir.x)
				var a := c - dir * (s * 0.42)
				var b := c + dir * (s * 0.62)
				var w := s * 0.28
				draw_colored_polygon(PackedVector2Array([
					a - perp * w,
					b - perp * w,
					b + perp * w,
					a + perp * w,
				]), color)
				var tip := c - dir * (s * 0.84)
				draw_colored_polygon(PackedVector2Array([
					tip,
					a - perp * w,
					a + perp * w,
				]), color)
			&"eraser":
				var d := s * 0.54
				draw_line(c + Vector2(-d, -d), c + Vector2(d, d), color, 3.0, true)
				draw_line(c + Vector2(d, -d), c + Vector2(-d, d), color, 3.0, true)
			&"alert_tri":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0.0, -s * 0.78),
					c + Vector2(s * 0.78, s * 0.64),
					c + Vector2(-s * 0.78, s * 0.64),
				]), color)
				draw_line(c + Vector2(0.0, -s * 0.24), c + Vector2(0.0, s * 0.18), COLOR_INNER, 2.4, true)
				draw_circle(c + Vector2(0.0, s * 0.42), 1.8, COLOR_INNER)
			&"diamond":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0.0, -s * 0.74),
					c + Vector2(s * 0.74, 0.0),
					c + Vector2(0.0, s * 0.74),
					c + Vector2(-s * 0.74, 0.0),
				]), color)


# 3 chấm trạng thái thất bại: phân biệt rõ chưa dùng / đã dùng (có dấu X) / gần thua (nhấp nháy) / thua.
class FailurePips extends Control:
	var failed_count := 0
	var max_failed := Config.MAX_FAILED
	var _pulse := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(88, 30)
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
		var spacing := 28.0
		var start_x := (size.x - spacing * float(n - 1)) * 0.5
		var cy := size.y * 0.5
		var r := 9.0
		var near_loss := (failed_count == n - 1 and failed_count > 0)
		var is_lost := (failed_count >= n)
		for i in n:
			var center := Vector2(start_x + float(i) * spacing, cy)
			if i < failed_count:
				draw_circle(center, r, COLOR_DANGER)
				draw_arc(center, r, 0.0, TAU, 24, COLOR_INK if is_lost else Color("#ffb3b3"), 1.8)
				var d := 4.0
				draw_line(center + Vector2(-d, -d), center + Vector2(d, d), COLOR_INNER, 2.4, true)
				draw_line(center + Vector2(d, -d), center + Vector2(-d, d), COLOR_INNER, 2.4, true)
			else:
				var border_col := COLOR_BORDER.lightened(0.28)
				var width := 2.0
				if near_loss and i == n - 1:
					var t := 0.5 + 0.5 * sin(_pulse)
					border_col = COLOR_WARN.lerp(COLOR_INK, t * 0.45)
					width = 2.6
				draw_circle(center, r, COLOR_INNER)
				draw_arc(center, r, 0.0, TAU, 24, border_col, width)


var score_label: Label
var failure_pips: FailurePips
var water_icon: HudIcon
var water_label: Label
var time_label: Label
var pause_btn: Button
var pause_icon: HudIcon
var speed_buttons: Dictionary = {}  # speed (1/2/3) -> Button
var menu_arrow_btn: Button
var menu_arrow_icon: HudIcon
var menu_dropdown: PanelContainer
var draw_mode_btn: Button
var draw_mode_icon: HudIcon
var erase_mode_btn: Button
var erase_mode_icon: HudIcon
var alert_chip: PanelContainer
var alert_icon: HudIcon
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


func _style_pill(bg: Color, border: Color, radius: int = 16, bw: int = 2) -> StyleBoxFlat:
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
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _make_styled_button(caption: String, min_size: Vector2, font_size: int = 20, bold: bool = true) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if bold:
		b.add_theme_font_override("font", FONT_BOLD)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_color_override("font_hover_color", COLOR_INK)
	b.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	b.add_theme_stylebox_override("normal", _style_pill(COLOR_BG, COLOR_BORDER, 12, 2))
	b.add_theme_stylebox_override("hover", _style_pill(COLOR_BG_HOVER, COLOR_CYAN, 12, 2))
	b.add_theme_stylebox_override("pressed", _style_pill(COLOR_BG_SELECTED, COLOR_GOLD, 12, 2))
	return b


func _attach_centered_icon(btn: Button, icon_kind: StringName, icon_size: Vector2, icon_color: Color) -> HudIcon:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var ic := HudIcon.new(icon_kind, icon_size, icon_color)
	center.add_child(ic)
	return ic


# 1. Mũi tên góc trên trái mở Chơi lại / Menu chính
func _build_top_left_menu() -> void:
	menu_arrow_btn = _make_styled_button("", Vector2(54, 54), 22)
	add_child(menu_arrow_btn)
	menu_arrow_btn.anchor_left = 0.0
	menu_arrow_btn.anchor_top = 0.0
	menu_arrow_btn.offset_left = 20
	menu_arrow_btn.offset_top = 18
	menu_arrow_btn.offset_right = 74
	menu_arrow_btn.offset_bottom = 72
	menu_arrow_btn.tooltip_text = "Tùy chọn ván chơi"
	menu_arrow_icon = _attach_centered_icon(menu_arrow_btn, &"chevron_left", Vector2(24, 24), COLOR_INK)
	menu_arrow_btn.pressed.connect(_toggle_menu_dropdown)

	menu_dropdown = PanelContainer.new()
	add_child(menu_dropdown)
	menu_dropdown.anchor_left = 0.0
	menu_dropdown.anchor_top = 0.0
	menu_dropdown.offset_left = 20
	menu_dropdown.offset_top = 80
	menu_dropdown.offset_right = 248
	menu_dropdown.offset_bottom = 206
	menu_dropdown.add_theme_stylebox_override("panel", _style_pill(COLOR_BG, COLOR_BORDER, 14, 2))
	menu_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_dropdown.visible = false

	var margin := MarginContainer.new()
	menu_dropdown.add_child(margin)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	vbox.add_theme_constant_override("separation", 10)

	vbox.add_child(_make_menu_row_button(&"restart", "Chơi lại", func() -> void:
		menu_dropdown.visible = false
		menu_arrow_icon.set_icon(&"chevron_left", COLOR_INK)
		GameManager.restart()
	))
	vbox.add_child(_make_menu_row_button(&"home", "Menu chính", func() -> void:
		menu_dropdown.visible = false
		menu_arrow_icon.set_icon(&"chevron_left", COLOR_INK)
		GameManager.exit_to_menu()
	))


func _make_menu_row_button(icon_kind: StringName, caption: String, on_click: Callable) -> Button:
	var btn := _make_styled_button("", Vector2(204, 48), 20)
	btn.pressed.connect(on_click)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var ic := HudIcon.new(icon_kind, Vector2(20, 20), COLOR_CYAN)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var lbl := Label.new()
	lbl.text = caption
	lbl.add_theme_font_override("font", FONT_BOLD)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", COLOR_INK)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return btn


func _toggle_menu_dropdown() -> void:
	menu_dropdown.visible = not menu_dropdown.visible
	menu_arrow_icon.set_icon(&"chevron_down" if menu_dropdown.visible else &"chevron_left", COLOR_GOLD if menu_dropdown.visible else COLOR_INK)


func _build_fps() -> void:
	fps_label = Label.new()
	add_child(fps_label)
	fps_label.anchor_left = 0.0
	fps_label.anchor_top = 0.0
	fps_label.offset_left = 86
	fps_label.offset_top = 32
	fps_label.offset_right = 230
	fps_label.offset_bottom = 60
	fps_label.text = ""
	fps_label.add_theme_font_override("font", FONT_BOLD)
	fps_label.add_theme_font_size_override("font_size", 16)
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
	pill.offset_left = -196
	pill.offset_right = 196
	pill.offset_top = 18
	pill.offset_bottom = 74
	pill.add_theme_stylebox_override("panel", _style_pill(Color(0.07, 0.12, 0.17, 0.94), COLOR_BORDER, 28, 2))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	pill.add_child(margin)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	margin.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var score_box := HBoxContainer.new()
	score_box.add_theme_constant_override("separation", 8)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_box)
	var star_ic := HudIcon.new(&"star", Vector2(22, 22), COLOR_GOLD)
	star_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_box.add_child(star_ic)
	score_label = Label.new()
	score_box.add_child(score_label)
	score_label.text = "0"
	score_label.add_theme_font_override("font", FONT_BOLD)
	score_label.add_theme_font_size_override("font_size", 25)
	score_label.add_theme_color_override("font_color", COLOR_GOLD)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(_make_vsep())

	failure_pips = FailurePips.new()
	failure_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(failure_pips)

	row.add_child(_make_vsep())

	var water_box := HBoxContainer.new()
	water_box.add_theme_constant_override("separation", 8)
	water_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(water_box)
	water_icon = HudIcon.new(&"wave", Vector2(22, 22), COLOR_CYAN)
	water_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	water_box.add_child(water_icon)
	water_label = Label.new()
	water_box.add_child(water_label)
	water_label.text = "0%"
	water_label.add_theme_font_override("font", FONT_BOLD)
	water_label.add_theme_font_size_override("font_size", 22)
	water_label.add_theme_color_override("font_color", COLOR_CYAN)
	water_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	water_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_vsep() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(2, 24)
	sep.color = COLOR_BORDER
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


# 3. Chip cảnh báo gọn (thay thế banner dài cũ, có cả icon vector + chữ ngắn)
func _build_alert_chip() -> void:
	alert_chip = PanelContainer.new()
	add_child(alert_chip)
	alert_chip.anchor_left = 0.5
	alert_chip.anchor_right = 0.5
	alert_chip.anchor_top = 0.0
	alert_chip.offset_left = -118
	alert_chip.offset_right = 118
	alert_chip.offset_top = 84
	alert_chip.offset_bottom = 126
	alert_chip.add_theme_stylebox_override("panel", _style_pill(COLOR_BG, COLOR_WARN, 20, 2))
	alert_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_chip.visible = false

	var margin := MarginContainer.new()
	alert_chip.add_child(margin)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	margin.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	alert_icon = HudIcon.new(&"alert_tri", Vector2(20, 20), COLOR_WARN)
	alert_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(alert_icon)

	alert_text_label = Label.new()
	row.add_child(alert_text_label)
	alert_text_label.text = "SẮP NGẬP"
	alert_text_label.add_theme_font_override("font", FONT_BOLD)
	alert_text_label.add_theme_font_size_override("font_size", 19)
	alert_text_label.add_theme_color_override("font_color", COLOR_INK)
	alert_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	alert_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


# 4. Cụm đồng hồ gọn góc trên phải: MM:SS + Pause/Play + x1 / x2 / x3
func _build_clock_controls() -> void:
	var dock := PanelContainer.new()
	add_child(dock)
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.0
	dock.offset_left = -376
	dock.offset_right = -20
	dock.offset_top = 18
	dock.offset_bottom = 74
	dock.add_theme_stylebox_override("panel", _style_pill(Color(0.07, 0.12, 0.17, 0.94), COLOR_BORDER, 28, 2))
	dock.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	dock.add_child(margin)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)

	var row := HBoxContainer.new()
	margin.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	time_label = Label.new()
	row.add_child(time_label)
	time_label.custom_minimum_size = Vector2(72, 0)
	time_label.text = "02:00"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.add_theme_font_override("font", FONT_BOLD)
	time_label.add_theme_font_size_override("font_size", 21)
	time_label.add_theme_color_override("font_color", COLOR_INK)
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	pause_btn = _make_styled_button("", Vector2(46, 40), 19)
	pause_btn.tooltip_text = "Tạm dừng / Tiếp tục (Space)"
	pause_icon = _attach_centered_icon(pause_btn, &"pause", Vector2(20, 20), COLOR_INK)
	pause_btn.pressed.connect(_on_pause_toggle)
	row.add_child(pause_btn)

	for spd in [1, 2, 3]:
		var btn := _make_styled_button("x%d" % spd, Vector2(50, 40), 19)
		btn.tooltip_text = "Tốc độ x%d (F)" % spd
		var target_spd: int = spd
		btn.pressed.connect(func() -> void: _select_speed(target_spd))
		row.add_child(btn)
		speed_buttons[spd] = btn


func _on_pause_toggle() -> void:
	if GameManager.state == Types.GameState.PAUSED:
		GameManager.resume_game()
	else:
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
		pause_icon.set_icon(&"play" if is_paused else &"pause", COLOR_GOLD if is_paused else COLOR_INK)
		var p_bg := COLOR_BG_SELECTED if is_paused else COLOR_INNER
		var p_border := COLOR_GOLD if is_paused else COLOR_BORDER
		pause_btn.add_theme_stylebox_override("normal", _style_pill(p_bg, p_border, 11, 2))

	for spd in speed_buttons:
		var btn: Button = speed_buttons[spd]
		var active: bool = (not is_paused) and (cur_speed == spd)
		var bg := COLOR_BG_SELECTED if active else COLOR_INNER
		var border := COLOR_CYAN if active else COLOR_BORDER
		btn.add_theme_stylebox_override("normal", _style_pill(bg, border, 11, 2 if active else 1))
		btn.add_theme_color_override("font_color", COLOR_GOLD if active else COLOR_MUTED)


# 5. Lựa chọn Vẽ / Xóa ở cạnh phải giữa
func _build_right_mode_dock() -> void:
	var dock := PanelContainer.new()
	add_child(dock)
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.5
	dock.anchor_bottom = 0.5
	dock.offset_left = -94
	dock.offset_right = -20
	dock.offset_top = -76
	dock.offset_bottom = 76
	dock.add_theme_stylebox_override("panel", _style_pill(Color(0.07, 0.12, 0.17, 0.94), COLOR_BORDER, 22, 2))
	dock.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	dock.add_child(margin)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)

	draw_mode_btn = _make_styled_button("", Vector2(56, 56), 22)
	draw_mode_btn.tooltip_text = "Chế độ Vẽ (Chuột trái)"
	draw_mode_icon = _attach_centered_icon(draw_mode_btn, &"pencil", Vector2(26, 26), COLOR_GOLD)
	draw_mode_btn.pressed.connect(func() -> void:
		EventBus.active_tool_changed.emit(_last_draw_tool)
	)
	vbox.add_child(draw_mode_btn)

	erase_mode_btn = _make_styled_button("", Vector2(56, 56), 22)
	erase_mode_btn.tooltip_text = "Chế độ Xóa (Click/kéo hoặc giữ Chuột phải)"
	erase_mode_icon = _attach_centered_icon(erase_mode_btn, &"eraser", Vector2(24, 24), COLOR_MUTED)
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
			_style_pill(COLOR_BG_SELECTED if draw_active else COLOR_INNER, COLOR_GOLD if draw_active else COLOR_BORDER, 14, 2 if draw_active else 1)
		)
		draw_mode_icon.set_icon(&"pencil", COLOR_GOLD if draw_active else COLOR_MUTED)
	if erase_mode_btn != null:
		erase_mode_btn.add_theme_stylebox_override(
			"normal",
			_style_pill(Color(0.28, 0.10, 0.12, 0.95) if is_erase else COLOR_INNER, COLOR_DANGER if is_erase else COLOR_BORDER, 14, 2 if is_erase else 1)
		)
		erase_mode_icon.set_icon(&"eraser", COLOR_DANGER if is_erase else COLOR_MUTED)


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
	menu_arrow_icon.set_icon(&"chevron_left", COLOR_INK)
	_active_tool = TOOL_ROAD
	_last_draw_tool = TOOL_ROAD
	_warn_time = 0.0
	_recede_time = 0.0
	_ferry_time = 0.0
	_last_level = 0.0
	_receding = false
	_prev_routes_count = 0
	_alert_mode = ""
	failure_pips.set_failed(0, Config.MAX_FAILED)
	score_label.text = "0"
	_sync_mode_buttons()
	_sync_clock_buttons(true)
	_build_badges()


func _on_game_state_changed(state: int) -> void:
	if state == Types.GameState.MENU:
		menu_dropdown.visible = false
		menu_arrow_icon.set_icon(&"chevron_left", COLOR_INK)
	_sync_clock_buttons(true)


func _on_tool_changed(tool_id: int) -> void:
	_active_tool = tool_id
	if tool_id != TOOL_ERASE:
		_last_draw_tool = tool_id
	_sync_mode_buttons()


# Nhãn tồn kho gọn dưới mỗi Kho trên bản đồ (sắc nét ở 1920×1200)
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
		var pill := Style.rect(self, at.x, at.y, BADGE_SIZE.x, BADGE_SIZE.y, Color(0.07, 0.12, 0.17, 0.92), COLOR_BORDER, 16)
		var food := Style.text(pill, "", 8, 0, 60, BADGE_SIZE.y, 18, COLOR_GOLD, true)
		var med := Style.text(pill, "", 70, 0, 60, BADGE_SIZE.y, 18, COLOR_CYAN, true)
		food.add_theme_font_override("font", FONT_BOLD)
		med.add_theme_font_override("font", FONT_BOLD)
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
			alert_icon.set_icon(&"alert_tri", COLOR_WARN)
			alert_text_label.text = "SẮP NGẬP"
			alert_chip.add_theme_stylebox_override("panel", _style_pill(Color(0.28, 0.08, 0.06, 0.94), COLOR_WARN, 20, 2))
	elif _recede_time > 0.0:
		alert_chip.visible = true
		if _alert_mode != "recede":
			_alert_mode = "recede"
			alert_icon.set_icon(&"arrow_down", COLOR_MINT)
			alert_text_label.text = "NƯỚC RÚT"
			alert_chip.add_theme_stylebox_override("panel", _style_pill(Color(0.06, 0.20, 0.18, 0.92), COLOR_MINT, 20, 2))
	elif _ferry_time > 0.0:
		alert_chip.visible = true
		if _alert_mode != "ferry":
			_alert_mode = "ferry"
			alert_icon.set_icon(&"diamond", COLOR_CYAN)
			alert_text_label.text = "PHÀ MỚI"
			alert_chip.add_theme_stylebox_override("panel", _style_pill(Color(0.06, 0.18, 0.25, 0.92), COLOR_CYAN, 20, 2))
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
	score_label.text = "%d" % value
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
	water_label.text = "%d%%" % int(round(level))
	var col := COLOR_MINT if _receding else (COLOR_WARN if level >= 65.0 else COLOR_CYAN)
	water_label.add_theme_color_override("font_color", col)
	water_icon.set_icon(&"arrow_down" if _receding else &"wave", col)


func _on_stock(hub_id: int, supply: int, qty: int) -> void:
	if not badges.has(hub_id):
		return
	if supply == Types.SupplyType.FOOD:
		badges[hub_id][0].text = "LT %d" % qty
	else:
		badges[hub_id][1].text = "YT %d" % qty


func _on_warning(_edge_id: int, _seconds_left: float) -> void:
	_warn_time = 2.2

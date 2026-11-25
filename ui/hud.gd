extends Control
## Compact HUD (Vector MVP layout): one thin bar on top, stock badges under each hub on the map,
## a small legend in the bottom-left corner and a controls hint at the bottom. Nothing covers the map nodes.
signal pause_pressed
const Style = preload("res://ui/style.gd")

const BAR := Rect2(215, 8, 850, 42)
const BADGE_SIZE := Vector2(104, 26)
const BADGE_OFFSET := 52.0 # below the hub icon and its name (NodeLayer)
const ROAD_DRY := Color("#fbfaf6")
const ROAD_SHALLOW := Color("#f7e6ae")
const ROAD_SHALLOW_MARK := Color("#b9862b")
const ROAD_DEEP := Color("#5aa7d6")
const Road := preload("res://graph/edge_layer.gd")
const ROAD_CASING := Color("#7f97a3")
const MAP_CREDIT := "© OpenStreetMap contributors" # required by the ODbL licence

var _deep_swatch: Array  # [viền, mặt đường] của ô mẫu "Sâu"; bản đồ kiểu lưới: đường chìm dưới nước, không viền

var score_label: Label
var fail_label: Label
var wave_label: Label
var time_label: Label
var water_label: Label
var budget_label: Label
var warning_label: Label
var warning_panel: Panel
var warn_time: float = 0.0
var recede_panel: Panel        # băng "NƯỚC ĐANG RÚT" hiện vài giây khi mặt nước bắt đầu rút (nửa sau mỗi đợt)
var recede_label: Label
var recede_time := 0.0
var ferry_panel: Panel
var ferry_label: Label
var ferry_time := 0.0
var _prev_routes_count := 0
const ToolBarScript := preload("res://ui/tool_bar.gd")
var tool_bar: Control
var _last_level := 0.0
var _receding := false
const RECEDE_BANNER := 3.0
const RECEDE_COLOR := Color("#7ee0a8")  # chữ mực nước lúc đang rút
# Dòng FPS (góc trên trái): số khung hình mỗi giây thật và khung lâu nhất trong 0,5 giây vừa qua. Đo bằng đồng hồ thật
# vì tua nhanh đổi Engine.time_scale. Bản debug, hoặc bản web mở với ?fpslog, in thêm ra console để đo (FPS_LOG_EVERY giây
# một dòng tóm tắt, kèm mọi khung lâu hơn SLOW_FRAME_MS).
const FPS_WINDOW := 0.5
const FPS_LOG_EVERY := 5.0
const SLOW_FRAME_MS := 50.0
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
var countdown: float = 120.0
var break_time: bool = false
var enabled: bool = false
var badges: Dictionary = {} # hub_id -> [food Label, medical Label]
var speed_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_fps()
	var p := Style.button(self, "II", 1216, 8, 50, 42, Style.NIGHT, 22)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.pressed.connect(func() -> void: pause_pressed.emit())
	speed_button = Style.button(self, "x1", 1160, 8, 50, 42, Style.NIGHT, 20)
	speed_button.mouse_filter = Control.MOUSE_FILTER_STOP
	speed_button.focus_mode = Control.FOCUS_NONE  # để Space không bấm nhầm nút này
	speed_button.pressed.connect(func() -> void: GameManager.cycle_speed())
	_build_legend()
	_build_hint()
	warning_panel = Style.rect(self, 440, 58, 400, 44, Color(0.37, 0.04, 0.04, 0.96), Style.ORANGE, 10)
	warning_label = Style.text(self, "ĐƯỜNG SẮP NGẬP!", 440, 58, 400, 44, 21, Style.WHITE, true)
	warning_label.visible = false
	warning_panel.visible = false
	recede_panel = Style.rect(self, 440, 58, 400, 44, Color(0.02, 0.18, 0.26, 0.96), Style.CYAN, 10)
	recede_label = Style.text(self, "NƯỚC ĐANG RÚT", 440, 58, 400, 44, 21, Style.WHITE, true)
	recede_panel.visible = false
	recede_label.visible = false
	ferry_panel = Style.rect(self, 380, 58, 520, 44, Color(0.02, 0.22, 0.32, 0.96), Style.CYAN, 10)
	ferry_label = Style.text(self, "⚓ ĐÃ MỞ TUYẾN PHÀ PHAO VƯỢT SÔNG!", 380, 58, 520, 44, 20, Style.WHITE, true)
	ferry_panel.visible = false
	ferry_label.visible = false
	EventBus.ferry_routes_changed.connect(_on_ferry_routes)
	_build_tool_bar()
	_connect_signals()

func _build_fps() -> void:
	Style.rect(self, 10, 14, 140, 24, Color(0.0, 0.05, 0.11, 0.75), Style.BORDER, 8)
	fps_label = Style.text(self, "FPS --", 10, 14, 140, 24, 13, Style.MUTED, true)
	_fps_last_us = Time.get_ticks_usec()
	_fps_log = OS.is_debug_build()
	if OS.has_feature("web"):
		_fps_log = _fps_log or bool(JavaScriptBridge.eval("location.search.indexOf('fpslog') >= 0", true))

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
	fps_label.text = "FPS %d · %d ms" % [roundi(fps), roundi(_fps_worst)]
	fps_label.add_theme_color_override("font_color", Style.MUTED if fps >= 50.0 else (Style.YELLOW if fps >= 30.0 else Style.ORANGE))
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

func _build_top_bar() -> void:
	Style.rect(self, BAR.position.x, BAR.position.y, BAR.size.x, BAR.size.y, Color(0.0, 0.05, 0.11, 0.9), Style.BORDER, 10)
	var row := HBoxContainer.new()
	add_child(row)
	row.position = BAR.position
	row.size = BAR.size
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_label(row, "F L O O D L I N E", Style.MUTED)
	score_label = _bar_label(row, "ĐIỂM 0", Style.YELLOW)
	wave_label = _bar_label(row, "ĐỢT 1 / 3", Style.WHITE)
	time_label = _bar_label(row, "02:00", Style.WHITE)
	water_label = _bar_label(row, "≈ 0%", Style.CYAN)
	budget_label = _bar_label(row, "ĐƯỜNG 0 / %d" % Config.EDGE_LIMIT_START, Style.WHITE)
	fail_label = _bar_label(row, "THẤT BẠI 0 / 3", Style.WHITE)

func _bar_label(row: HBoxContainer, caption: String, color: Color) -> Label:
	var l := Label.new()
	row.add_child(l)
	l.text = caption
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_legend() -> void:
	var box := Style.rect(self, 12, 612, 236, 70, Color(0.0, 0.05, 0.11, 0.88), Style.BORDER, 10)
	var roads := [["Khô", ROAD_DRY, false], ["Cạn", ROAD_SHALLOW, true], ["Sâu", ROAD_DEEP, false]]
	for i in roads.size():
		var x: float = 14 + i * 76
		var swatch := _road_sample(box, Vector2(x, 16), roads[i][1], roads[i][2])
		if i == 2:
			_deep_swatch = swatch
		Style.text(box, roads[i][0], x + 30, 6, 44, 24, 15, Style.WHITE)
	Style.text(box, "LT", 14, 38, 24, 24, 15, Style.YELLOW)
	Style.text(box, "Lương thực", 40, 38, 84, 24, 15, Style.WHITE)
	Style.text(box, "YT", 130, 38, 24, 24, 15, Style.CYAN)
	Style.text(box, "Y tế", 158, 38, 60, 24, 15, Style.WHITE)
	EventBus.game_started.connect(func() -> void:
		Road.apply_terrain(GraphManager.get_terrain())
		_deep_swatch[0].color = Road.deep_casing if Road.bridges else ROAD_CASING
		_deep_swatch[1].color = Road.deep_fill if Road.bridges else ROAD_DEEP)

# Small road swatch drawn like EdgeLayer: dark casing, road colour, yellow dashes for a shallow road.
func _road_sample(parent: Control, at: Vector2, fill: Color, dashed: bool) -> Array:
	var casing := ColorRect.new()
	parent.add_child(casing)
	casing.position = at - Vector2(0, 2)
	casing.size = Vector2(26, 10)
	casing.color = ROAD_CASING
	casing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var road := ColorRect.new()
	parent.add_child(road)
	road.position = at
	road.size = Vector2(26, 6)
	road.color = fill
	road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dashed:
		for k in 3:
			var dash := ColorRect.new()
			parent.add_child(dash)
			dash.position = at + Vector2(1 + k * 9, 1)
			dash.size = Vector2(6, 4)
			dash.color = ROAD_SHALLOW_MARK
			dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return [casing, road]

func _build_hint() -> void:
	Style.rect(self, 260, 690, 760, 26, Color(0.0, 0.05, 0.11, 0.8), Style.BORDER, 8)
	var hint := Style.text(self, "Chọn công cụ: 1 Vẽ đường  •  2 Bến Phà Phao  |  Chuột trái: vẽ/đặt  •  Chuột phải: xóa/hủy  •  Space: dừng  •  F: tua nhanh",
			260, 690, 760, 26, 13, Style.MUTED, true)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF # one line; with word wrap the label grew past its box
	hint.size = Vector2(760, 26)
	Style.text(self, MAP_CREDIT, 1024, 696, 250, 20, 11, Color("#4f6b7a"), true)

func _build_tool_bar() -> void:
	tool_bar = ToolBarScript.new()
	tool_bar.name = "ToolBar"
	tool_bar.position = Vector2(1015, 622)
	add_child(tool_bar)

func _connect_signals() -> void:
	EventBus.game_started.connect(_build_badges)
	EventBus.score_changed.connect(_on_score)
	EventBus.failed_changed.connect(_on_failed)
	EventBus.wave_started.connect(_on_wave)
	EventBus.break_started.connect(_on_break)
	EventBus.water_level_changed.connect(_on_water)
	EventBus.edge_budget_changed.connect(_on_budget)
	EventBus.stock_changed.connect(_on_stock)
	EventBus.flood_warning.connect(_on_warning)

# One stock badge under each hub. Positions come from the GraphManager read API; the counts are read from
# RescueManager because C emits the first stock_changed before this HUD hears game_started.
func _build_badges() -> void:
	for pair in badges.values():
		pair[0].get_parent().queue_free()
	badges.clear()
	for id in GraphManager.get_node_ids():
		var n = GraphManager.get_map_node(id)
		if n == null or n.kind != Types.NodeKind.HUB:
			continue
		var at: Vector2 = n.pos + Vector2(-BADGE_SIZE.x / 2.0, BADGE_OFFSET)
		var pill := Style.rect(self, at.x, at.y, BADGE_SIZE.x, BADGE_SIZE.y, Color(0.0, 0.05, 0.11, 0.9), Style.BORDER, 13)
		var food := Style.text(pill, "", 6, 0, 46, BADGE_SIZE.y, 15, Style.YELLOW, true)
		var med := Style.text(pill, "", 52, 0, 46, BADGE_SIZE.y, 15, Style.CYAN, true)
		food.autowrap_mode = TextServer.AUTOWRAP_OFF  # "YT 20" rộng hơn ô 40 px cũ nên bị xuống dòng
		med.autowrap_mode = TextServer.AUTOWRAP_OFF
		badges[id] = [food, med]
		pill.set_meta("anchor", n.pos + Vector2(0.0, BADGE_OFFSET))
		for supply in [Types.SupplyType.FOOD, Types.SupplyType.MEDICAL]:
			_on_stock(id, supply, RescueManager.get_stock(id, supply))

func _process(delta: float) -> void:
	# Nhãn tồn kho bám theo kho khi camera phóng to (vùng chơi theo đợt), kích thước giữ nguyên.
	var xf := get_viewport().get_canvas_transform()
	for pair in badges.values():
		var pill: Control = pair[0].get_parent()
		pill.position = xf * (pill.get_meta("anchor") as Vector2) - Vector2(BADGE_SIZE.x / 2.0, 0.0)
	_tick_fps()
	var speed_text := "x%d" % GameManager.game_speed
	if speed_button.text != speed_text:
		speed_button.text = speed_text
	if not enabled:
		return
	if countdown > 0.0:
		countdown = maxf(0.0, countdown - delta)
	var sec := int(ceil(countdown))
	time_label.text = "%02d:%02d" % [int(sec / 60), sec % 60]
	if warn_time > 0.0:
		warn_time -= delta
		warning_label.visible = fmod(Time.get_ticks_msec()/1000.0, 0.5) < 0.33
		warning_panel.visible = warning_label.visible
	else:
		warning_label.visible = false
		warning_panel.visible = false
	if recede_time > 0.0:
		recede_time -= delta
	var show_recede := recede_time > 0.0 and not warning_panel.visible  # cảnh báo ngập ưu tiên hơn
	recede_panel.visible = show_recede
	recede_label.visible = show_recede
	if ferry_time > 0.0:
		ferry_time -= delta
	var show_ferry := ferry_time > 0.0 and not warning_panel.visible and not recede_panel.visible
	ferry_panel.visible = show_ferry
	ferry_label.visible = show_ferry

func _on_ferry_routes() -> void:
	if not has_node("/root/GraphManager"):
		return
	var count: int = GraphManager.get_ferry_routes().size()
	if count > _prev_routes_count:
		ferry_time = 3.5
	_prev_routes_count = count

func _on_score(value: int) -> void:
	score_label.text = "ĐIỂM %d" % value
	score_label.pivot_offset = score_label.size / 2.0
	var tw := score_label.create_tween()
	score_label.scale = Vector2(1.25, 1.25)
	tw.tween_property(score_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_failed(count: int, maximum: int) -> void:
	fail_label.text = "THẤT BẠI %d / %d" % [count, maximum]
	fail_label.add_theme_color_override("font_color", Style.ORANGE if count > 0 else Style.WHITE)

func _on_wave(index: int) -> void:
	break_time = false
	wave_label.text = "ĐỢT %d / %d" % [index + 1, Config.WAVE_COUNT]
	countdown = Config.WAVE_DURATION

func _on_break(seconds: float) -> void:
	break_time = true
	wave_label.text = "NGHỈ GIỮA ĐỢT"
	countdown = seconds

func _on_water(level: float) -> void:
	water_label.text = "≈ %d%%" % int(round(level))
	# Nước bắt đầu rút: hiện băng vài giây, chữ mực nước đổi màu tới khi nước dâng lại.
	if level < _last_level - 0.0001 and not _receding:
		_receding = true
		recede_time = RECEDE_BANNER
	elif level > _last_level + 0.0001 or level <= 0.0:
		_receding = false
	_last_level = level
	water_label.add_theme_color_override("font_color", RECEDE_COLOR if _receding else Style.CYAN)

func _on_budget(used: int, limit: int) -> void:
	budget_label.text = "ĐƯỜNG %d / %d" % [used, limit]

func _on_stock(hub_id: int, supply: int, qty: int) -> void:
	if not badges.has(hub_id):
		return
	if supply == Types.SupplyType.FOOD:
		badges[hub_id][0].text = "LT %d" % qty
	else:
		badges[hub_id][1].text = "YT %d" % qty

func _on_warning(_edge_id: int, _seconds_left: float) -> void:
	warn_time = 2.0

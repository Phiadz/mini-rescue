extends Control
## Compact HUD (Vector MVP layout): one thin bar on top, stock badges under each hub on the map,
## a small legend in the bottom-left corner and a controls hint at the bottom. Nothing covers the map
## nodes, so map_01.json keeps the coordinates that match terrain/height_field.png.
signal pause_pressed
const Style = preload("res://ui/style.gd")

const BAR := Rect2(250, 8, 780, 42)
const BADGE_SIZE := Vector2(96, 26)
const BADGE_OFFSET := 66.0 # below the hub icon and its name (NodeLayer)
const ROAD_DRY := Color("#aeb8c4")
const ROAD_SHALLOW := Color("#1f2b3c")
const ROAD_SHALLOW_MARK := Color("#e9c85c")
const ROAD_DEEP := Color("#3a8fd0")
const ROAD_CASING := Color("#0d1726")

var score_label: Label
var fail_label: Label
var wave_label: Label
var time_label: Label
var water_label: Label
var budget_label: Label
var warning_label: Label
var warning_panel: Panel
var warn_time: float = 0.0
var countdown: float = 120.0
var break_time: bool = false
var enabled: bool = false
var badges: Dictionary = {} # hub_id -> [food Label, medical Label]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	var p := Style.button(self, "Ⅱ", 1216, 8, 50, 42, Style.NIGHT, 22)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.pressed.connect(func() -> void: pause_pressed.emit())
	_build_legend()
	_build_hint()
	warning_panel = Style.rect(self, 440, 58, 400, 44, Color(0.37, 0.04, 0.04, 0.96), Style.ORANGE, 10)
	warning_label = Style.text(self, "⚠  TUYẾN SẮP NGẬP!", 440, 58, 400, 44, 21, Style.WHITE, true)
	warning_label.visible = false
	warning_panel.visible = false
	_connect_signals()

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
	score_label = _bar_label(row, "★ 0", Style.YELLOW)
	wave_label = _bar_label(row, "ĐỢT 1 / 3", Style.WHITE)
	time_label = _bar_label(row, "02:00", Style.WHITE)
	water_label = _bar_label(row, "≈ 0%", Style.CYAN)
	budget_label = _bar_label(row, "TUYẾN 0 / 10", Style.WHITE)
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
		_road_sample(box, Vector2(x, 16), roads[i][1], roads[i][2])
		Style.text(box, roads[i][0], x + 30, 6, 44, 24, 15, Style.WHITE)
	Style.text(box, "●", 14, 38, 14, 24, 15, Style.YELLOW)
	Style.text(box, "Lương thực", 30, 38, 90, 24, 15, Style.WHITE)
	Style.text(box, "✚", 126, 38, 16, 24, 15, Style.CYAN)
	Style.text(box, "Y tế", 144, 38, 60, 24, 15, Style.WHITE)

# Small road swatch drawn like EdgeView: dark casing, road colour, yellow dashes for a shallow road.
func _road_sample(parent: Control, at: Vector2, fill: Color, dashed: bool) -> void:
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

func _build_hint() -> void:
	Style.rect(self, 260, 690, 760, 26, Color(0.0, 0.05, 0.11, 0.8), Style.BORDER, 8)
	Style.text(self, "Kéo trái: nối tuyến  •  Chuột phải / Delete: xóa  •  Bấm SOS: ưu tiên (tối đa 2)  •  Space/Esc: tạm dừng",
			260, 690, 760, 26, 14, Style.MUTED, true)

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
		var food := Style.text(pill, "", 8, 0, 40, BADGE_SIZE.y, 15, Style.YELLOW, true)
		var med := Style.text(pill, "", 48, 0, 40, BADGE_SIZE.y, 15, Style.CYAN, true)
		badges[id] = [food, med]
		for supply in [Types.SupplyType.FOOD, Types.SupplyType.MEDICAL]:
			_on_stock(id, supply, RescueManager.get_stock(id, supply))

func _process(delta: float) -> void:
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

func _on_score(value: int) -> void:
	score_label.text = "★ %d" % value

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

func _on_budget(used: int, limit: int) -> void:
	budget_label.text = "TUYẾN %d / %d" % [used, limit]

func _on_stock(hub_id: int, supply: int, qty: int) -> void:
	if not badges.has(hub_id):
		return
	if supply == Types.SupplyType.FOOD:
		badges[hub_id][0].text = "● %d" % qty
	else:
		badges[hub_id][1].text = "✚ %d" % qty

func _on_warning(_edge_id: int, _seconds_left: float) -> void:
	warn_time = 2.0

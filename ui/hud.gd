extends Control
signal pause_pressed
const Style = preload("res://ui/style.gd")
var score_label: Label
var fail_label: Label
var wave_label: Label
var time_label: Label
var water_label: Label
var budget_label: Label
var stock_north: Label
var stock_south: Label
var water_bar: ProgressBar
var warning_label: Label
var warning_panel: Panel
var warn_time: float = 0.0
var countdown: float = 120.0
var break_time: bool = false
var enabled: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.rect(self, 15, 10, 976, 73, Color(0.0, 0.05, 0.11, 0.94), Style.BORDER, 11)
	Style.text(self, "★", 32, 19, 48, 48, 38, Style.YELLOW)
	score_label = Style.text(self, "0", 80, 21, 122, 43, 27)
	Style.text(self, "◷", 242, 25, 42, 37, 32)
	time_label = Style.text(self, "02:00", 289, 24, 116, 40, 28)
	wave_label = Style.text(self, "ĐỢT 1 / 3", 427, 23, 200, 41, 27, Style.WHITE, true)
	Style.text(self, "💧", 700, 22, 45, 42, 29, Style.CYAN)
	water_label = Style.text(self, "0%", 745, 23, 120, 40, 29, Style.CYAN)
	var p := Style.button(self, "Ⅱ", 918, 20, 58, 52, Style.NIGHT, 28)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.pressed.connect(func() -> void: pause_pressed.emit())
	Style.rect(self, 1003, 10, 262, 694, Color(0.0, 0.06, 0.14, 0.96), Style.BORDER, 12)
	Style.text(self, "HẠN MỨC TUYẾN", 1022, 21, 235, 40, 22, Style.CYAN)
	Style.bar(self, 1021, 68, 165, 18, 0.0)
	budget_label = Style.text(self, "0 / 10", 1186, 63, 72, 28, 21, Style.WHITE, true)
	Style.separator(self, 100)
	Style.text(self, "TỒN KHO", 1022, 113, 225, 33, 25)
	stock_north = Style.text(self, "KHO BẮC   ● 6  ✚ 6", 1021, 157, 238, 38, 20, Style.YELLOW)
	stock_south = Style.text(self, "KHO NAM   ● 6  ✚ 6", 1021, 203, 238, 38, 20, Style.YELLOW)
	Style.rect(self, 1019, 262, 230, 1, Style.BORDER, Style.BORDER, 0)
	Style.text(self, "CHÚ THÍCH", 1022, 280, 222, 36, 24)
	var legend := [
		["⌂", "Nhà dân"], ["▣", "Kho"], ["━━", "Đường khô ráo"],
		["┄┄", "Đường ngập"], ["●", "SOS cứu hộ"], ["✚", "Trạm y tế"],
		["", "Xe tải"], ["", "Ca-nô"]
	]
	for i in range(legend.size()):
		var yy: int = 324 + i*44
		if i < 6:
			Style.text(self, str(legend[i][0]), 1028, yy, 72, 42, 31, Style.CYAN if i % 2 == 1 else Style.YELLOW)
		else:
			var vehicle_icon := TextureRect.new()
			add_child(vehicle_icon)
			vehicle_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			vehicle_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vehicle_icon.texture = load("res://assets/icons/rescue_truck.png") if i == 6 else load("res://assets/icons/rescue_boat.png")
			vehicle_icon.position = Vector2(1024, yy + 2)
			vehicle_icon.size = Vector2(72, 39)
			vehicle_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Style.text(self, str(legend[i][1]), 1104, yy, 147, 42, 19)
	Style.rect(self, 22, 100, 284, 52, Color(0.02,0.07,0.12,0.87), Style.BORDER, 10)
	fail_label = Style.text(self, "THẤT BẠI: 0 / 3", 36, 106, 269, 39, 23, Style.WHITE)
	water_bar = Style.bar(self, 780, 89, 185, 14, 0.0, Style.BLUE)
	warning_panel = Style.rect(self, 350, 92, 407, 61, Color(0.37, 0.04, 0.04, 0.96), Style.ORANGE, 10)
	warning_label = Style.text(self, "⚠  TUYẾN SẮP NGẬP!", 362, 98, 384, 48, 23, Style.WHITE, true)
	warning_label.visible = false
	warning_panel.visible = false
	Style.text(self, "F1: THƯỞNG  |  F2: THẮNG  |  F3: THUA  |  F7: CẢNH BÁO (TEST)", 20, 672, 900, 31, 16, Style.MUTED)
	_connect_signals()

func _connect_signals() -> void:
	EventBus.score_changed.connect(_on_score)
	EventBus.failed_changed.connect(_on_failed)
	EventBus.wave_started.connect(_on_wave)
	EventBus.break_started.connect(_on_break)
	EventBus.water_level_changed.connect(_on_water)
	EventBus.edge_budget_changed.connect(_on_budget)
	EventBus.stock_changed.connect(_on_stock)
	EventBus.flood_warning.connect(_on_warning)

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
	score_label.text = str(value)

func _on_failed(count: int, maximum: int) -> void:
	fail_label.text = "THẤT BẠI: %d / %d" % [count, maximum]

func _on_wave(index: int) -> void:
	break_time = false
	wave_label.text = "ĐỢT %d / 3" % (index + 1)
	countdown = Config.WAVE_DURATION

func _on_break(seconds: float) -> void:
	break_time = true
	wave_label.text = "NGHỈ GIỮA ĐỢT"
	countdown = seconds

func _on_water(level: float) -> void:
	water_label.text = "%d%%" % int(round(level))
	water_bar.value = level

func _on_budget(used: int, limit: int) -> void:
	budget_label.text = "%d / %d" % [used, limit]

func _on_stock(hub_id: int, supply: int, qty: int) -> void:
	var target := stock_north if hub_id == 0 else stock_south
	var key := "food_%d" % hub_id if supply == 0 else "med_%d" % hub_id
	set_meta(key, qty)
	target.text = "KHO %s   ● %d  ✚ %d" % ["BẮC" if hub_id == 0 else "NAM", int(get_meta("food_%d" % hub_id, 6)), int(get_meta("med_%d" % hub_id, 6))]

func _on_warning(_edge_id: int, _seconds_left: float) -> void:
	warn_time = 2.0

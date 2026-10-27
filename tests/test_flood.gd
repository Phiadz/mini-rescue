extends Node2D

var canvas: CanvasLayer
var tank_water: ColorRect
var lbl_info: Label
var btn_next_wave: Button
var btn_pause: Button
var btn_speed: Button
var road_rects: Array[ColorRect] = []
var road_labels: Array[Label] = []

var road_elevations: Array[float] = [10.0, 25.0, 50.0, 87.5]

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.1, 0.14))
	
	# Chạy test biên bắt buộc mục 5.2
	test_asserts()
	FloodManager.reset_flood()
	
	canvas = CanvasLayer.new()
	canvas.name = "TestCanvasUI"
	add_child(canvas)
	_build_ui()

func _process(_delta: float) -> void:
	if tank_water == null or lbl_info == null:
		return
	
	var cur_w = FloodManager.water_level
	var wave_idx = FloodManager.current_wave
	
	# Hiển thị index + 1 chuẩn theo Quy tắc 8
	var state_desc = ""
	if FloodManager.is_rising:
		state_desc = "ĐANG DÂNG ĐỢT %d (%.0fm)..." % [wave_idx + 1, FloodManager.wave_levels[wave_idx]]
	else:
		if wave_idx == -1 or cur_w == 0.0:
			state_desc = "BAN ĐẦU (0m) - ĐANG DỪNG"
		elif wave_idx == 0 and cur_w >= 30.0:
			state_desc = "ĐÃ ĐẠT ĐỢT 1 (30m) - ĐANG DỪNG"
		elif wave_idx == 1 and cur_w >= 60.0:
			state_desc = "ĐÃ ĐẠT ĐỢT 2 (60m) - ĐANG DỪNG"
		elif wave_idx == 2 and cur_w >= 100.0:
			state_desc = "ĐÃ ĐẠT ĐỈNH ĐỢT 3 (100m) - ĐANG DỪNG"
		else:
			state_desc = "TẠM DỪNG Ở %.1fm (Bấm Space để dâng tiếp)" % cur_w

	lbl_info.text = "Mực nước: %5.2f m  |  Tốc độ: %.1fx  |  Trạng thái: %s" % [cur_w, Engine.time_scale, state_desc]
	
	# Cập nhật nhãn nút phím R theo đúng chỉ số cộng 1 (Quy tắc 8)
	if btn_next_wave != null:
		if FloodManager.is_rising:
			btn_next_wave.text = "🌊 Đang dâng Đợt %d (%.0fm)..." % [wave_idx + 1, FloodManager.wave_levels[wave_idx]]
		elif wave_idx == -1 or cur_w == 0.0:
			btn_next_wave.text = "🌊 [R] Bấm để dâng lên ĐỢT 1 (30m)"
		elif wave_idx == 0:
			btn_next_wave.text = "🌊 [R] Đang ở Đợt 1. Bấm để dâng lên ĐỢT 2 (60m)"
		elif wave_idx == 1:
			btn_next_wave.text = "🌊 [R] Đang ở Đợt 2. Bấm để dâng lên ĐỢT 3 (100m)"
		else:
			btn_next_wave.text = "🔄 [R] Đã ngập đỉnh Đợt 3. Bấm để ĐẶT LẠI VỀ 0m"

	if btn_pause != null:
		btn_pause.text = "⏸ [Space] Tạm Dừng" if FloodManager.is_rising else "▶ [Space] Dâng Tiếp"

	# Cập nhật chiều cao bể nước
	var max_h = 400.0
	var h = clamp(cur_w / 100.0, 0.0, 1.0) * max_h
	tank_water.size.y = h
	tank_water.position.y = 520.0 - h
	
	# Cập nhật màu các đoạn đường
	for i in range(road_elevations.size()):
		var elev = road_elevations[i]
		var state = FloodManager.compute_state(elev)
		if state == Types.EdgeState.DRY:
			road_rects[i].color = Color(0.18, 0.8, 0.44)
			road_labels[i].text = "Đoạn %d (Cao độ %4.1fm) ➔ KHÔ RÁO (DRY)" % [i + 1, elev]
			road_labels[i].modulate = Color(0.18, 0.8, 0.44)
		elif state == Types.EdgeState.SHALLOW:
			road_rects[i].color = Color(0.95, 0.61, 0.07)
			road_labels[i].text = "Đoạn %d (Cao độ %4.1fm) ➔ NGẬP NÔNG (SHALLOW)" % [i + 1, elev]
			road_labels[i].modulate = Color(0.95, 0.61, 0.07)
		else:
			road_rects[i].color = Color(0.91, 0.3, 0.24)
			road_labels[i].text = "Đoạn %d (Cao độ %4.1fm) ➔ NGẬP SÂU (DEEP)" % [i + 1, elev]
			road_labels[i].modulate = Color(0.91, 0.3, 0.24)

# BẢNG TEST BIÊN BẮT BUỘC 5.2
func test_asserts() -> void:
	FloodManager.water_level = 0.0
	assert(FloodManager.compute_state(10.0) == Types.EdgeState.DRY, "Test 1 Thất bại")
	FloodManager.water_level = 10.0
	assert(FloodManager.compute_state(10.0) == Types.EdgeState.SHALLOW, "Test 2 Thất bại")
	FloodManager.water_level = 24.9
	assert(FloodManager.compute_state(10.0) == Types.EdgeState.SHALLOW, "Test 3 Thất bại")
	FloodManager.water_level = 25.0
	assert(FloodManager.compute_state(10.0) == Types.EdgeState.DEEP, "Test 4 Thất bại")
	FloodManager.water_level = 90.0
	assert(FloodManager.compute_state(87.5) == Types.EdgeState.SHALLOW, "Test 5 Thất bại")
	print(">> [B-TEST] Test biên compute_state: ĐẠT 100% <<")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		match event.keycode:
			KEY_R:
				FloodManager.next_wave()
			KEY_SPACE:
				FloodManager.toggle_pause()
			KEY_T:
				Engine.time_scale = 10.0 if Engine.time_scale == 1.0 else 1.0

func _build_ui() -> void:
	var title = Label.new()
	title.position = Vector2(40, 20)
	title.text = "HỆ THỐNG MÔ PHỎNG NƯỚC LŨ (FLOOD SIMULATION)"
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(1.0, 0.8, 0.2)
	canvas.add_child(title)

	lbl_info = Label.new()
	lbl_info.position = Vector2(40, 52)
	lbl_info.add_theme_font_size_override("font_size", 16)
	canvas.add_child(lbl_info)

	var tank_outline = ColorRect.new()
	tank_outline.position = Vector2(40, 95)
	tank_outline.size = Vector2(200, 430)
	tank_outline.color = Color(0.25, 0.3, 0.4)
	canvas.add_child(tank_outline)

	var tank_bg = ColorRect.new()
	tank_bg.position = Vector2(44, 99)
	tank_bg.size = Vector2(192, 422)
	tank_bg.color = Color(0.04, 0.05, 0.08)
	canvas.add_child(tank_bg)

	tank_water = ColorRect.new()
	tank_water.position = Vector2(44, 520)
	tank_water.size = Vector2(192, 0)
	tank_water.color = Color(0.18, 0.55, 0.95, 0.9)
	canvas.add_child(tank_water)

	# Vạch mốc hiển thị ĐỢT 1, ĐỢT 2, ĐỢT 3 chuẩn Quy tắc 8
	var marks = [
		{"m": 100, "txt": "ĐỢT 3 (100m Đỉnh)"},
		{"m": 60,  "txt": "ĐỢT 2 (60m)"},
		{"m": 30,  "txt": "ĐỢT 1 (30m)"},
		{"m": 0,   "txt": "0m (Ban đầu)"}
	]
	for item in marks:
		var mark_y = 520 - (float(item.m) / 100.0) * 400.0
		var lbl_m = Label.new()
		lbl_m.position = Vector2(248, mark_y - 10)
		lbl_m.text = "➔ %s" % item.txt
		lbl_m.add_theme_font_size_override("font_size", 13)
		if item.m == 100:
			lbl_m.modulate = Color(0.95, 0.3, 0.3)
		elif item.m == 60:
			lbl_m.modulate = Color(0.95, 0.65, 0.1)
		elif item.m == 30:
			lbl_m.modulate = Color(0.3, 0.8, 1.0)
		else:
			lbl_m.modulate = Color(0.6, 0.7, 0.8)
		canvas.add_child(lbl_m)

	# 4 đoạn đường
	road_rects.clear()
	road_labels.clear()
	for i in range(road_elevations.size()):
		var elev = road_elevations[i]
		var y = 100 + i * 80
		var bar = ColorRect.new()
		bar.position = Vector2(440, y)
		bar.size = Vector2(220, 24)
		bar.color = Color.GREEN
		canvas.add_child(bar)
		road_rects.append(bar)

		var lbl = Label.new()
		lbl.position = Vector2(675, y - 2)
		lbl.add_theme_font_size_override("font_size", 15)
		canvas.add_child(lbl)
		road_labels.append(lbl)

	# BẢNG ĐIỀU KHIỂN
	var pnl_title = Label.new()
	pnl_title.position = Vector2(440, 430)
	pnl_title.text = "ĐIỀU KHIỂN (BẤM PHÍM HOẶC CLICK NÚT):"
	pnl_title.add_theme_font_size_override("font_size", 16)
	pnl_title.modulate = Color(0.4, 0.8, 1.0)
	canvas.add_child(pnl_title)

	btn_next_wave = _make_button("🌊 [R] Bấm để dâng lên ĐỢT 1 (30m)", Vector2(440, 465), Vector2(480, 50))
	btn_next_wave.modulate = Color(0.3, 0.85, 1.0)
	btn_next_wave.add_theme_font_size_override("font_size", 16)
	btn_next_wave.pressed.connect(func(): FloodManager.next_wave())

	btn_pause = _make_button("⏸ [Space] Tạm Dừng", Vector2(440, 530), Vector2(230, 42))
	btn_pause.pressed.connect(func(): FloodManager.toggle_pause())

	btn_speed = _make_button("⏩ [T] Tua Nhanh x10", Vector2(685, 530), Vector2(235, 42))
	btn_speed.pressed.connect(func(): Engine.time_scale = 10.0 if Engine.time_scale == 1.0 else 1.0)

	var btn_reset = _make_button("🔄 Đặt Lại Về 0m", Vector2(935, 465), Vector2(170, 50))
	btn_reset.pressed.connect(func(): FloodManager.reset_flood())

func _make_button(text_str: String, pos: Vector2, btn_size: Vector2) -> Button:
	var b = Button.new()
	b.text = text_str
	b.position = pos
	b.size = btn_size
	b.add_theme_font_size_override("font_size", 14)
	canvas.add_child(b)
	return b

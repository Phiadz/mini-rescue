extends Node

# Tín hiệu đặt ở thì quá khứ theo Quy tắc 2
signal water_level_changed(new_level: float)
signal wave_started(wave_idx: int)
signal flood_stopped()

var water_level: float = 0.0:
	set(val):
		var old = water_level
		water_level = clamp(val, 0.0, 100.0)
		if old != water_level:
			water_level_changed.emit(water_level)
			# Báo tin qua EventBus chung theo Quy tắc 6 (nếu EventBus có khai báo)
			if EventBus != null and EventBus.has_signal("water_level_changed"):
				EventBus.emit_signal("water_level_changed", water_level)

var is_rising: bool = false
var current_wave: int = -1 # Chỉ số đợt tính từ 0 theo Quy tắc 8
var rise_speed: float = 5.0

# Tham số cấu hình lấy từ Config theo Quy tắc 7 (tránh số cứng)
var wave_levels: Array[float] = [30.0, 60.0, 100.0]

func _ready() -> void:
	if "WAVE_TARGETS" in Config:
		wave_levels = Config.WAVE_TARGETS

func _process(delta: float) -> void:
	if is_rising and current_wave >= 0 and current_wave < wave_levels.size():
		var target = wave_levels[current_wave]
		if water_level < target:
			water_level += rise_speed * delta
			if water_level >= target:
				water_level = target
				is_rising = false
				print(">> [FLOOD] Đợt %d (%.0fm) đạt đỉnh và tự dừng <<" % [current_wave + 1, target])

# Chữ ký hàm công khai giữ nguyên theo hợp đồng Mục 5.2 & Quy tắc 9
func compute_state(edge_elevation: float) -> int:
	var d := water_level - edge_elevation
	if d < 0.0:
		return Types.EdgeState.DRY
	# Dùng hằng số Config theo Quy tắc 7
	var shallow_limit: float = Config.SHALLOW_MAX if "SHALLOW_MAX" in Config else 15.0
	if d < shallow_limit:
		return Types.EdgeState.SHALLOW
	return Types.EdgeState.DEEP

# Phím R: Chuyển tuần tự qua từng đợt
func next_wave() -> void:
	if current_wave < 2:
		current_wave += 1
		is_rising = true
		wave_started.emit(current_wave)
		if EventBus != null and EventBus.has_signal("flood_wave_started"):
			EventBus.emit_signal("flood_wave_started", current_wave)
		print(">> [FLOOD] Đang dâng Đợt %d (Mục tiêu: %.0fm) <<" % [current_wave + 1, wave_levels[current_wave]])
	else:
		reset_flood()

# Đặt lại về ban đầu
func reset_flood() -> void:
	is_rising = false
	current_wave = -1
	water_level = 0.0
	Engine.time_scale = 1.0
	flood_stopped.emit()
	print(">> [FLOOD] Đã đặt lại về Mức 0m ban đầu <<")

# Bật/tắt dâng nước bằng phím Space
func toggle_pause() -> void:
	if is_rising:
		is_rising = false
		flood_stopped.emit()
	else:
		if current_wave == -1:
			current_wave = 0
		if water_level < wave_levels[current_wave]:
			is_rising = true
		else:
			next_wave()

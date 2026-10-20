extends Node
# Config: toàn bộ tham số cân bằng của game (Tài liệu chốt, Phần 1).
# Không đặt class_name (script autoload). Chỉ số đợt (wave index) tính từ 0.

# --- Bản đồ và tuyến ---
const MAP_PATH := 'res://data/map_01.json'
const EDGE_LIMIT_START := 10

# --- Tốc độ phương tiện (px/giây) ---
const TRUCK_SPEED := 120.0
const BOAT_SPEED := 90.0

# --- Lũ ---
const SHALLOW_MAX := 15.0
const FLOOD_TICK := 0.25
const WARNING_SECONDS := 5.0

# --- Đợt và ván chơi ---
const WAVE_COUNT := 3
const WAVE_DURATION := 120.0
const BREAK_DURATION := 15.0
const MAX_FAILED := 3

# --- Giao hàng, kho, SOS ---
const DELIVERY_TIME := 1.5
const SOS_COOLDOWN := 20.0
const STOCK_START := 6
const STOCK_MAX := 10
const STOCK_REGEN := 20.0
const MAX_PRIORITIZED := 2

# --- Điểm ---
const POINTS := {0: 10, 1: 20}
const BONUS_RATIO := 1.5
const REWARD_EDGE_BONUS := 2 

# --- Hệ số tốc độ: SPEED_FACTOR[loại xe][trạng thái tuyến] ---
# Loại xe: 0 TRUCK, 1 BOAT. Trạng thái tuyến: 0 DRY, 1 SHALLOW, 2 DEEP
const SPEED_FACTOR := {
	0: [1.0, 0.5, 0.0],
	1: [0.0, 0.5, 1.0],
}

# --- Các đợt lũ (chỉ số 0, 1, 2) ---
const WAVES := [
	{water_delta = 25.0, sos_interval = 12.0, sos_max = 4, food_ratio = 0.70, deadline_food = 60.0, deadline_medical = 45.0},
	{water_delta = 30.0, sos_interval = 9.0, sos_max = 5, food_ratio = 0.60, deadline_food = 50.0, deadline_medical = 38.0},
	{water_delta = 35.0, sos_interval = 7.0, sos_max = 6, food_ratio = 0.55, deadline_food = 40.0, deadline_medical = 32.0},
]

# --- Khảo sát: E điền link Google Form sau ---
var SURVEY_URL := ''

func base_speed(vehicle_type: int) -> float:
	return TRUCK_SPEED if vehicle_type == 0 else BOAT_SPEED

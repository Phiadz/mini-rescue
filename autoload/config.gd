extends Node
# Config: toàn bộ tham số cân bằng của game (Tài liệu chốt, Phần 1).
# Không đặt class_name (script autoload). Chỉ số đợt (wave index) tính từ 0.

# --- Bản đồ và tuyến ---
const MAP_PATH := 'res://data/map_saigon.json'
const EDGE_LIMIT_START := 50  # hạn mức tính theo số ô đường

# --- Lưới đường: bản đồ 1280 × 720 chia ô vuông ---
const CELL_SIZE := 40
const GRID_COLS := 32
const GRID_ROWS := 18

# --- Tốc độ phương tiện (px/giây) ---
const TRUCK_SPEED := 120.0
const BOAT_SPEED := 90.0

# --- Lũ ---
const SHALLOW_MAX := 15.0
const FLOOD_TICK := 0.25
const WARNING_SECONDS := 5.0
# Lũ lan theo ô: ô có độ cao tới SEA_MAX_ELEVATION là biển, mặt nước biển dâng theo WAVES.
# Mỗi FLOOD_TICK, ô kề một ô đã ngập ít nhất FLOOD_SPILL_DEPTH thì mặt nước dâng dần về phía ô đó,
# nhanh nhất FLOOD_SPREAD_RATE đơn vị độ cao mỗi giây, không vượt mặt nước của ô nguồn.
const SEA_MAX_ELEVATION := 1.0
const FLOOD_SPILL_DEPTH := 1.0
const FLOOD_SPREAD_RATE := 3.0

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
const REWARD_EDGE_BONUS := 12  # số ô đường

# --- Cửa hàng cứu trợ (mở trong lượt nghỉ giữa hai đợt) ---
# Mỗi SOS cứu được cộng vào quỹ đúng bằng số điểm nhận được; mua hàng chỉ trừ quỹ, không trừ điểm.
# Khóa là Types.Reward: 0 MORE_EDGES (+REWARD_EDGE_BONUS ô đường), 1 EXTRA_TRUCK, 2 EXTRA_BOAT.
const SHOP_PRICES := {0: 60, 1: 100, 2: 80}
const FUND_UNIT_VND := 10000000  # mỗi đơn vị quỹ hiển thị là 10 triệu đồng (chỉ để hiển thị)
const SHOP_PRICE_GROWTH := 1.5  # mỗi lần mua cùng một món trong ván, giá món đó nhân thêm (làm tròn 5)

# --- Hệ số tốc độ: SPEED_FACTOR[loại xe][trạng thái tuyến] ---
# Loại xe: 0 TRUCK, 1 BOAT. Trạng thái tuyến: 0 DRY, 1 SHALLOW, 2 DEEP
const SPEED_FACTOR := {
	0: [1.0, 0.5, 0.0],
	1: [0.25, 0.5, 1.0],  # ca-nô đi được đường khô ở 25% tốc độ (kéo bằng rơ-moóc ra chỗ ngập)
}

# --- Các đợt lũ (chỉ số 0, 1, 2) ---
const WAVES := [
	{water_delta = 25.0, sos_interval = 12.0, sos_max = 4, food_ratio = 0.70, deadline_food = 60.0, deadline_medical = 45.0},
	{water_delta = 30.0, sos_interval = 9.0, sos_max = 5, food_ratio = 0.60, deadline_food = 50.0, deadline_medical = 38.0},
	{water_delta = 35.0, sos_interval = 7.0, sos_max = 6, food_ratio = 0.55, deadline_food = 40.0, deadline_medical = 32.0},
]

# --- Khảo sát: E điền link Google Form sau ---
var SURVEY_URL := 'https://docs.google.com/forms/d/e/1FAIpQLSdjOjb0RipPcebnFNh5uKQh2SgIuu_9ysoWz64FoBmw0bJSZQ/viewform'

func base_speed(vehicle_type: int) -> float:
	return TRUCK_SPEED if vehicle_type == 0 else BOAT_SPEED

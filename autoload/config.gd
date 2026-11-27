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
const TRUCK_SPEED := 180.0
const BOAT_SPEED := 135.0
const MOTORBIKE_SPEED := 220.0
const CAR_SPEED := 160.0

const HIGHWAY_SPEED_FACTOR := 1.5
# Pixels per second squared, indexed by Types.VehicleType in enum order.
const ACCELERATION := [95.0, 65.0, 170.0, 120.0]
const BRAKING := [290.0, 210.0, 380.0, 340.0]
const JUNCTION_SPEED_FACTOR := 0.65

# --- Lũ ---
const SHALLOW_MAX := 15.0
const DEEP_FLOOD_REACH := 3  # cardinal cells connected to a water source
const BOAT_CHANNEL_MIN_DEPTH := SHALLOW_MAX  # marked land corridors open at DEEP
const FLOOD_TICK := 0.25
const WARNING_SECONDS := 5.0
# Lũ lan theo ô: ô có độ cao tới SEA_MAX_ELEVATION là biển, mặt nước biển dâng rồi rút theo WAVES.
# Mỗi FLOOD_TICK, ô kề một ô đã ngập ít nhất FLOOD_SPILL_DEPTH thì mặt nước dâng dần về phía ô đó,
# nhanh nhất FLOOD_SPREAD_RATE đơn vị độ cao mỗi giây, không vượt mặt nước của ô nguồn.
const SEA_MAX_ELEVATION := 1.0
const FLOOD_SPILL_DEPTH := 1.0
const FLOOD_SPREAD_RATE := 3.0
# Nước rút: ô đất có mặt nước cao hơn mức cân bằng (mức cao nhất phải vượt qua trên đường ra biển thấp nhất) thì thoát
# về mức đó, nhanh nhất FLOOD_DRAIN_RATE mỗi giây; nước đọng trong hố trũng (bờ cao hơn mặt biển) thấm dần FLOOD_SEEP_RATE.
const FLOOD_DRAIN_RATE := 3.0
const FLOOD_SEEP_RATE := 0.5

# --- Đợt và ván chơi ---
const WAVE_COUNT := 3
const WAVE_DURATION := 120.0
# Mỗi đợt: WAVE_RISE_TIME giây đầu mặt nước dâng tới đỉnh water_peak, thời gian còn lại rút RECEDE_RATIO phần vừa dâng,
# nên mực nước nền vẫn tăng dần qua các đợt (25 -> rút còn ~14, 55 -> ~37, 90 -> ~66).
const WAVE_RISE_TIME := 80.0
const RECEDE_RATIO := 0.45
const BREAK_DURATION := 15.0
const MAX_FAILED := 3

# --- Giao hàng, kho, SOS ---
const DELIVERY_TIME := 0.5
const SOS_COOLDOWN := 20.0
const STOCK_START := 12
const STOCK_MAX := 20
const STOCK_REGEN := 10.0
const MAX_PRIORITIZED := 2

# --- Xe dân (xe máy, ô tô con của từng nhà) ---
const CIVILIAN_LOAD_TIME := 0.3    # giây nhận hàng ở kho
const MOTORBIKE_RATIO := 0.7       # 70% nhà có xe máy, còn lại là ô tô con
const CIVILIAN_FADE_TIME := 0.25   # giây mờ dần khi xe gặp ngập và biến mất

# --- Nâng cấp tải trọng xe cứu hộ ---
const TRUCK_CAPACITY_DEFAULT := 1
const BOAT_CAPACITY_DEFAULT := 1
const CAPACITY_UPGRADED := 2
const MULTIDROP_RADIUS := 120.0    # px: hai SOS gần nhau trong bán kính này thì gom một chuyến

# --- Điểm ---
const POINTS := {0: 10, 1: 20}
const BONUS_RATIO := 1.5
const REWARD_EDGE_BONUS := 12  # số ô đường
const REWARD_VEHICLE_BONUS := 2  # số xe mỗi lần mua xe tải hoặc ca-nô ở cửa hàng

# --- Cửa hàng cứu trợ (mở trong lượt nghỉ giữa hai đợt) ---
# Mỗi SOS cứu được cộng vào quỹ đúng bằng số điểm nhận được; mua hàng chỉ trừ quỹ, không trừ điểm.
# Khóa là Types.Reward: 0 MORE_EDGES (+REWARD_EDGE_BONUS ô đường), 1 EXTRA_TRUCK, 2 EXTRA_BOAT, 3 UPGRADE_TRUCK_CAP, 4 UPGRADE_BOAT_CAP.
const SHOP_PRICES := {0: 60, 1: 100, 2: 80, 3: 150, 4: 120}  # 3,4 là nâng cấp sức chứa phương tiện cứu hộ
const FUND_UNIT_VND := 10000000  # mỗi đơn vị quỹ hiển thị là 10 triệu đồng (chỉ để hiển thị)
const SHOP_PRICE_GROWTH := 1.5  # mỗi lần mua cùng một món trong ván, giá món đó nhân thêm (làm tròn 5)

# --- Hệ số tốc độ: SPEED_FACTOR[loại xe][trạng thái tuyến] ---
# Loại xe: 0 TRUCK, 1 BOAT, 2 MOTORBIKE, 3 CAR. Trạng thái tuyến: 0 DRY, 1 SHALLOW, 2 DEEP
const SPEED_FACTOR := {
	Types.VehicleType.TRUCK: [1.0, 0.5, 0.0],
	Types.VehicleType.BOAT: [0.0, 0.5, 1.0],  # ca-nô không lên đất khô; chạy trên sông (cạnh boat_only, luôn DEEP), đường ngập sâu, đường ngập nhẹ thì chậm
	Types.VehicleType.MOTORBIKE: [1.0, 0.4, 0.0],  # xe máy: lội chậm qua ngập nông, không đi ngập sâu
	Types.VehicleType.CAR: [1.0, 0.0, 0.0],  # ô tô con: chỉ đi đường khô
}

# --- Các đợt lũ (chỉ số 0, 1, 2) ---
# water_peak: mặt nước biển cao nhất của đợt (thang 0–100), tới sau WAVE_RISE_TIME giây rồi rút.
# sos_units: số phần hàng mỗi SOS cần; mỗi xe chở 1 phần. Mỗi nhà chỉ cần 1 xe (góp ý của Lộc: một xe tải đủ cho một nhà).
# house_interval: bản đồ có cổng thì cứ chừng ấy giây lại mọc thêm một nhà quanh một khu đã mở.
const WAVES := [
	{water_peak = 25.0, sos_interval = 7.0, sos_max = 6, sos_units = 1, house_interval = 9.0, food_ratio = 0.70, deadline_food = 40.0, deadline_medical = 30.0},
	{water_peak = 55.0, sos_interval = 5.0, sos_max = 8, sos_units = 1, house_interval = 7.0, food_ratio = 0.60, deadline_food = 35.0, deadline_medical = 27.0},
	{water_peak = 90.0, sos_interval = 3.8, sos_max = 10, sos_units = 1, house_interval = 5.0, food_ratio = 0.55, deadline_food = 27.0, deadline_medical = 21.0},
]

# Nhà mọc dần: mỗi khu (điểm có tên) có tối đa HOUSE_MAX_PER_DISTRICT nhà, cách khu tối đa HOUSE_RADIUS ô.
const HOUSE_MAX_PER_DISTRICT := 3
const HOUSE_RADIUS := 3

# --- Khảo sát: E điền link Google Form sau ---
var SURVEY_URL := 'https://docs.google.com/forms/d/e/1FAIpQLSdjOjb0RipPcebnFNh5uKQh2SgIuu_9ysoWz64FoBmw0bJSZQ/viewform'

func base_speed(vehicle_type: int) -> float:
	match vehicle_type:
		Types.VehicleType.TRUCK: return TRUCK_SPEED
		Types.VehicleType.BOAT: return BOAT_SPEED
		Types.VehicleType.MOTORBIKE: return MOTORBIKE_SPEED
		Types.VehicleType.CAR: return CAR_SPEED
	return TRUCK_SPEED

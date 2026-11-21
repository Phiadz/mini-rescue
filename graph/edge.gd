class_name Edge extends RefCounted
# Một đoạn đường ngắn nối hai node kề nhau (hai ô đường, hoặc một ô đường và một điểm).
# Cạnh boat_only (sông, bến, lối xuống nước) chỉ ca-nô đi; GraphManager giữ riêng, không vẽ, không tính hạn mức.
var id: int
var node_a: int
var node_b: int
var length: float = 0.0
var elevation: float = 0.0   # độ cao chung của cả đoạn chứa cạnh này
var segment: int = -1        # id đoạn, GraphManager tính lại mỗi lần tô hoặc xóa ô
var state: int = 0           # Types.EdgeState: 0 DRY, 1 SHALLOW, 2 DEEP
var boat_only := false       # cạnh chỉ dành cho ca-nô: xe tải không đi được

func other_end(n: int) -> int:
	return node_b if n == node_a else node_a

func speed_factor(vehicle_type: int) -> float:
	if boat_only and vehicle_type != Types.VehicleType.BOAT:
		return 0.0  # sông, bến, lối xuống nước: chỉ ca-nô đi, mọi xe đường bộ (tải, xe máy, ô tô) bị chặn
	return Config.SPEED_FACTOR[vehicle_type][state]
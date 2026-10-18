extends Node
# Autoload: GraphManager. Chủ sở hữu: A. Không đặt class_name.
# Bản khung: các module khác gọi được hàm ngay, A sẽ thay thân hàm dần.

func load_map(_path: String) -> void:
	pass  # TODO(A): đọc map_01.json, tạo MapNode

func get_node_ids() -> Array[int]:
	return []  # TODO(A)

func get_map_node(_id: int) -> MapNode:
	return null  # TODO(A)

func get_edge(_edge_id: int) -> Edge:
	return null  # TODO(A)

func get_edge_ids() -> Array[int]:
	return []  # TODO(A)

func get_edges_of(_node_id: int) -> Array[int]:
	return []  # TODO(A)

func add_edge(_a: int, _b: int) -> int:
	return -1  # TODO(A): trả edge_id, hoặc -1 nếu thất bại

func remove_edge(_edge_id: int) -> void:
	pass  # TODO(A)

func set_edge_state(_edge_id: int, _state: int) -> void:
	pass  # TODO(A): CHỈ B được gọi; chỉ phát edge_state_changed khi trạng thái thật sự đổi

func add_edge_limit(_n: int) -> void:
	pass  # TODO(A): E gọi khi nhận thưởng

func get_edge_budget() -> Dictionary:
	return {used = 0, limit = 0}  # TODO(A)

func find_path(_from_id: int, _to_id: int, _vehicle_type: int) -> PathResult:
	return PathResult.new()  # TODO(A): Dijkstra (mã mẫu ở mục 5.3 tài liệu của bạn)

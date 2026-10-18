extends Node
# STUB do A tạo. Chủ sở hữu: C. Thay thân hàm, GIỮ NGUYÊN tên và thứ tự tham số.
# Khi C tạo xong class SosRequest, đổi kiểu trả về của get_pending_requests thành Array[SosRequest].

func reset() -> void:
	pass  # TODO(C)

func set_wave(_index: int) -> void:
	pass  # TODO(C)

func set_spawning(_enabled: bool) -> void:
	pass  # TODO(C)

func prioritize(_req_id: int) -> bool:
	return false  # TODO(C)

func get_pending_requests() -> Array:
	return []  # TODO(C)

func get_vehicle_ids() -> Array[int]:
	return []  # TODO(C)

func add_vehicle(_type: int) -> int:
	return -1  # TODO(C): trả vehicle_id

func get_stock(_hub_id: int, _supply: int) -> int:
	return 0  # TODO(C)

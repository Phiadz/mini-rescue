class_name ScoreSystem extends Node
# Node con của GameManager (GameManager tự tạo trong _ready). Chủ sở hữu: E.
# Đếm điểm, số SOS cứu được và số SOS thất bại từ tín hiệu của C.

signal max_failed_reached  # chỉ GameManager nghe, không đi qua EventBus

const MAX_STARS := 3

var enabled := false  # GameManager bật khi ván bắt đầu, tắt khi thắng hoặc thua
var score := 0
var saved := 0
var failed := 0


func _ready() -> void:
	EventBus.sos_rescued.connect(_on_sos_rescued)
	EventBus.sos_failed.connect(_on_sos_failed)


func reset() -> void:
	score = 0
	saved = 0
	failed = 0


# Chỉ có nghĩa khi thắng: 0 thất bại 3 sao, 1 thất bại 2 sao, 2 thất bại 1 sao.
func get_stars() -> int:
	return clampi(MAX_STARS - failed, 1, MAX_STARS)


func _on_sos_rescued(_req_id: int, points: int) -> void:
	if not enabled:
		return
	score += points
	saved += 1
	EventBus.score_changed.emit(score)


func _on_sos_failed(_req_id: int) -> void:
	if not enabled:
		return
	failed += 1
	EventBus.failed_changed.emit(failed, Config.MAX_FAILED)
	if failed >= Config.MAX_FAILED:
		max_failed_reached.emit()

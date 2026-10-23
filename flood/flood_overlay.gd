class_name FloodOverlay
extends CanvasItem

func _ready() -> void:
	if FloodManager.has_signal("water_level_changed"):
		FloodManager.water_level_changed.connect(func(_val): queue_redraw())

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Cung cấp sẵn hàm vẽ cho các module bản đồ sau này khi bạn kết nối graph
	pass

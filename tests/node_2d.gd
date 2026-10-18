extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print(Config.TRUCK_SPEED)
	print(Config.WAVE_COUNT)
	print(Config.WAVES)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

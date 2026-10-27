extends Node2D
# Chủ sở hữu: E. Tạo và xóa EdgeView theo tín hiệu của A.

var _views := {}  # edge_id -> EdgeView


func _ready() -> void:
	EventBus.edge_added.connect(_on_edge_added)
	EventBus.edge_removed.connect(_on_edge_removed)
	EventBus.game_started.connect(_clear)  # A xóa cạnh của ván trước mà không phát edge_removed


func _on_edge_added(edge_id: int) -> void:
	var v := EdgeView.new()
	v.edge_id = edge_id
	add_child(v)
	_views[edge_id] = v


func _on_edge_removed(edge_id: int) -> void:
	if _views.has(edge_id):
		_views[edge_id].queue_free()
		_views.erase(edge_id)


func _clear() -> void:
	for v in _views.values():
		v.queue_free()
	_views.clear()

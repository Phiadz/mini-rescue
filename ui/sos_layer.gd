extends Node2D
## Visual presentation only. SOS positions come from the GraphManager read API.
const Marker = preload("res://ui/sos_marker.gd")
var markers: Dictionary = {}

func _ready() -> void:
	add_to_group("sos_layer")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.sos_spawned.connect(_on_sos_spawned)
	EventBus.sos_assigned.connect(_on_sos_assigned)
	EventBus.sos_rescued.connect(_on_sos_removed)
	EventBus.sos_failed.connect(_on_sos_removed)
	EventBus.game_started.connect(clear_markers)

func _on_sos_spawned(req_id: int, node_id: int, supply: int, time_total: float) -> void:
	if markers.has(req_id):
		return
	var node_data = GraphManager.get_map_node(node_id)
	if node_data == null:
		return
	var m = Marker.new()
	add_child(m)
	m.setup(req_id, supply, time_total)
	m.position = node_data.pos
	markers[req_id] = m

func _on_sos_assigned(req_id: int, _vehicle_id: int) -> void:
	if markers.has(req_id):
		markers[req_id].mark_assigned()

func _on_sos_removed(req_id: int, _unused: int = 0) -> void:
	if markers.has(req_id):
		markers[req_id].queue_free()
		markers.erase(req_id)

func clear_markers() -> void:
	for m in markers.values():
		m.queue_free()
	markers.clear()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	for rid in markers.keys():
		var m: Node2D = markers[rid]
		if m.hit(get_global_mouse_position()):
			# prioritize() returns the new state: true = now prioritized, false = un-prioritized or limit reached.
			m.set_priority(RescueManager.prioritize(int(rid)))
			get_viewport().set_input_as_handled()
			return

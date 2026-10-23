extends Node2D
## Person D's visual-only feedback. No flood simulation or game rules here.
## A sends flood_warning(edge_id, seconds_left); D reads endpoint positions.
const MARK_COLOR := Color("#FF4500")
const OUTLINE := Color("#FFD700")
const WARNING_LIFETIME := 2.0
var active: Dictionary = {} # edge id -> {start, end, seconds, ttl}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.flood_warning.connect(_on_flood_warning)
	EventBus.game_started.connect(clear_warnings)

func _position_for(node_id: int) -> Vector2:
	var node_data: Variant = GraphManager.get_map_node(node_id)
	if node_data == null:
		return Vector2(-1000.0, -1000.0)
	if node_data is Dictionary:
		return node_data.get("pos", Vector2(-1000.0, -1000.0))
	return node_data.get("pos")

func _on_flood_warning(edge_id: int, seconds_left: float) -> void:
	if not GraphManager.has_method("get_edge"):
		return
	var edge_data: Variant = GraphManager.get_edge(edge_id)
	if edge_data == null:
		return
	var node_a: int = int(edge_data.get("node_a", -1)) if edge_data is Dictionary else int(edge_data.get("node_a"))
	var node_b: int = int(edge_data.get("node_b", -1)) if edge_data is Dictionary else int(edge_data.get("node_b"))
	if node_a < 0 or node_b < 0:
		return
	var pa := _position_for(node_a)
	var pb := _position_for(node_b)
	if pa.x < 0.0 or pb.x < 0.0:
		return
	active[edge_id] = {"start": pa, "end": pb, "seconds": seconds_left, "ttl": WARNING_LIFETIME}
	queue_redraw()

func clear_warnings() -> void:
	active.clear()
	queue_redraw()

func _process(delta: float) -> void:
	if active.is_empty():
		return
	for key in active.keys():
		var item: Dictionary = active[key]
		item["ttl"] = float(item["ttl"]) - delta
		if float(item["ttl"]) <= 0.0:
			active.erase(key)
		else:
			active[key] = item
	queue_redraw()

func _draw() -> void:
	var flash: float = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.013))
	for item in active.values():
		var a: Vector2 = item["start"]
		var b: Vector2 = item["end"]
		var middle: Vector2 = (a + b) * 0.5
		# Orange dashes with yellow end markers; readable without relying on colour alone.
		var sections := 14
		for segment in range(sections):
			if segment % 2 == 0:
				var va: Vector2 = a.lerp(b, float(segment)/float(sections))
				var vb: Vector2 = a.lerp(b, float(segment+1)/float(sections))
				draw_line(va, vb, Color(MARK_COLOR, flash), 9.0, true)
		draw_arc(a, 16.0, 0.0, TAU, 28, OUTLINE, 3.0, true)
		draw_arc(b, 16.0, 0.0, TAU, 28, OUTLINE, 3.0, true)
		draw_circle(middle, 13.0, Color(MARK_COLOR, flash))
		# The HUD already shows the long warning; here show a compact road-local icon.
		var cross_a := middle + Vector2(-5, -6)
		var cross_b := middle + Vector2(5, 6)
		draw_line(cross_a, cross_b, Color.WHITE, 3.0)
		draw_line(middle+Vector2(-5, 6), middle+Vector2(5,-6), Color.WHITE, 3.0)

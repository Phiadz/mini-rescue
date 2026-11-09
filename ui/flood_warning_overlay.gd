extends Node2D
## Person D's visual-only feedback. No flood simulation or game rules here.
## B sends flood_warning(edge_id, seconds_left) once per road segment; D flashes the whole segment.
const MARK_COLOR := Color("#FF4500")
const OUTLINE := Color("#FFD700")
const WARNING_LIFETIME := 2.0
const SECTIONS := 3 # dashes on each short edge of the segment
var active: Dictionary = {} # edge id -> {links, seconds, ttl}

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
	var links: Array = []
	for id in GraphManager.get_segment_edges(edge_id):
		var edge := GraphManager.get_edge(id)
		var pa := _position_for(edge.node_a)
		var pb := _position_for(edge.node_b)
		if pa.x >= 0.0 and pb.x >= 0.0:
			links.append([pa, pb])
	if links.is_empty():
		return
	active[edge_id] = {"links": links, "seconds": seconds_left, "ttl": WARNING_LIFETIME}
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
		var links: Array = item["links"]
		# Orange dashes along the segment and one marker; readable without relying on colour alone.
		for link in links:
			var a: Vector2 = link[0]
			var b: Vector2 = link[1]
			for section in range(SECTIONS):
				if section % 2 == 0:
					var va: Vector2 = a.lerp(b, float(section)/float(SECTIONS))
					var vb: Vector2 = a.lerp(b, float(section+1)/float(SECTIONS))
					draw_line(va, vb, Color(MARK_COLOR, flash), 9.0, true)
		var centre: Array = links[links.size() / 2]
		var middle: Vector2 = (centre[0] + centre[1]) * 0.5
		draw_arc(middle, 16.0, 0.0, TAU, 28, OUTLINE, 3.0, true)
		draw_circle(middle, 13.0, Color(MARK_COLOR, flash))
		# The HUD already shows the long warning; here show a compact road-local icon.
		var cross_a := middle + Vector2(-5, -6)
		var cross_b := middle + Vector2(5, 6)
		draw_line(cross_a, cross_b, Color.WHITE, 3.0)
		draw_line(middle+Vector2(-5, 6), middle+Vector2(5,-6), Color.WHITE, 3.0)

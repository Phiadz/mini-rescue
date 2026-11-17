extends Node2D
# Chủ sở hữu: E. Vẽ nút giao tự động lên trên đường (dưới điểm và xe), loại nút do RescueManager.junction_kind quyết định:
# - vòng xoay (ngã ba đường): vòng đường tròn rộng hơn đường (cùng màu đường theo độ ngập, có viền), đảo cỏ ở giữa,
#   vạch đứt chạy vòng; xe trong vòng chạy lệch ra vòng (RescueManager.RING_RADIUS);
# - đèn giao thông (ngã tư đường trở lên): vạch dừng màu xanh hoặc đỏ ở làn vào của từng nhánh,
#   cột đèn nhỏ ở góc ô với hai chấm (trên: trục ngang, dưới: trục dọc). Chỉ vẽ lại khi có đèn đổi pha.

const ISLAND_COLOR := Color('#cfe3b4')
const ISLAND_EDGE := Color('#a9c78c')
const ISLAND_RADIUS := 6.0
const RING_OUTER := 18.0      # bán kính mặt đường của vòng xoay (đường rộng 22 px nên vòng nhìn rõ hơn đường)
const RING_MARK := 12.0       # vạch đứt chạy vòng, đúng chỗ xe chạy
const RING_DASHES := 10
const Road := preload('res://graph/edge_layer.gd')
const ISLAND_EDGE_WIDTH := 1.5
const GREEN := Color('#34c759')
const RED := Color('#ff3b30')
const POLE_COLOR := Color('#33485a')
const POLE_OFFSET := Vector2(15, -15)  # góc trên bên phải của ô
const POLE_SIZE := Vector2(8, 15)
const DOT_RADIUS := 2.6
const BAR_DIST := 15.0      # vạch dừng cách tâm nút (px), ngay trước vùng nút giao
const BAR_HALF := 4.0       # nửa chiều dài vạch, vừa một làn
const BAR_WIDTH := 3.0
const LANE := 5.5           # làn vào lệch phải hướng đi, như Vehicle.LANE_OFFSET

var _roundabouts: Array[int] = []
var _lights: Array[int] = []
var _phases := {}  # nút đèn -> trục ngang đang xanh không (lúc vẽ lần trước)


func _ready() -> void:
	EventBus.road_changed.connect(_rebuild)
	EventBus.game_started.connect(_rebuild)
	EventBus.edge_state_changed.connect(func(_id: int, _state: int) -> void:
		if not _roundabouts.is_empty():
			queue_redraw())  # vòng xoay đổi màu theo độ ngập
	_rebuild()


func _rebuild() -> void:
	_roundabouts.clear()
	_lights.clear()
	for id in GraphManager.get_road_ids():
		match RescueManager.junction_kind(id):
			RescueManager.JUNCTION_ROUNDABOUT:
				_roundabouts.append(id)
			RescueManager.JUNCTION_LIGHT:
				_lights.append(id)
	set_process(not _lights.is_empty())
	queue_redraw()


func _process(_delta: float) -> void:
	for id in _lights:
		if not _phases.has(id) or _phases[id] != RescueManager.light_green(id, Vector2.RIGHT):
			queue_redraw()
			return


func _draw() -> void:
	_phases.clear()
	for id in _roundabouts:
		var n := GraphManager.get_map_node(id)
		if n == null:
			continue
		var state := Types.EdgeState.DRY  # vòng xoay ngập theo nhánh ngập nặng nhất
		for eid in GraphManager.get_edges_of(id):
			state = maxi(state, GraphManager.get_edge(eid).state)
		var colors := {
			Types.EdgeState.DRY: [Road.DRY_COLOR, Road.DRY_CASING, Road.DRY_MARK_COLOR],
			Types.EdgeState.SHALLOW: [Road.SHALLOW_COLOR, Road.SHALLOW_CASING, Road.SHALLOW_MARK_COLOR],
			Types.EdgeState.DEEP: [Road.DEEP_COLOR, Road.DEEP_CASING, Road.DEEP_MARK_COLOR],
		}
		var c: Array = colors[state]
		var casing := (Road.CASING_WIDTH - Road.ROAD_WIDTH) / 2.0
		draw_circle(n.pos, RING_OUTER + casing, c[1])
		draw_circle(n.pos, RING_OUTER, c[0])
		for k in RING_DASHES:  # vạch đứt chạy vòng
			var a0 := TAU * k / RING_DASHES
			draw_arc(n.pos, RING_MARK, a0, a0 + TAU / RING_DASHES * 0.5, 4, c[2], Road.MARK_WIDTH)
		draw_circle(n.pos, ISLAND_RADIUS + ISLAND_EDGE_WIDTH, ISLAND_EDGE)
		draw_circle(n.pos, ISLAND_RADIUS, ISLAND_COLOR)
	for id in _lights:
		var n := GraphManager.get_map_node(id)
		if n == null:
			continue
		var h_green := RescueManager.light_green(id, Vector2.RIGHT)
		var v_green := RescueManager.light_green(id, Vector2.DOWN)
		_phases[id] = h_green
		for eid in GraphManager.get_edges_of(id):
			var e := GraphManager.get_edge(eid)
			var other: MapNode = GraphManager.get_map_node(e.other_end(id)) if e != null else null
			if other == null:
				continue
			var d := n.pos.direction_to(other.pos)  # hướng ra nhánh; xe vào đi theo -d
			var into := -d
			var center := n.pos + d * BAR_DIST + into.rotated(PI / 2.0) * LANE
			var across := d.rotated(PI / 2.0) * BAR_HALF
			var green := RescueManager.light_green(id, into)
			draw_line(center - across, center + across, GREEN if green else RED, BAR_WIDTH, true)
		var pole := Rect2(n.pos + POLE_OFFSET - POLE_SIZE / 2.0, POLE_SIZE)
		draw_rect(pole, POLE_COLOR)
		draw_circle(pole.position + Vector2(POLE_SIZE.x / 2.0, POLE_SIZE.y * 0.28), DOT_RADIUS, GREEN if h_green else RED)
		draw_circle(pole.position + Vector2(POLE_SIZE.x / 2.0, POLE_SIZE.y * 0.72), DOT_RADIUS, GREEN if v_green else RED)

extends Node2D
# Chủ sở hữu: E. Vẽ các điểm của bản đồ khi nhận game_started (sau khi A đã load_map).
# Mỗi điểm vẽ bằng icon tòa nhà của D theo trường `icon` trong tệp bản đồ (ví dụ hub_north, hospital).
# Điểm chưa có icon thì vẽ hình khối, phân biệt bằng hình dạng (Tài liệu chốt 1.10): kho ▣, khu dân cư ⌂.

const ICON_PATH := 'res://assets/icons/%s.svg'
const HUB_ICON_SIZE := 56.0
const DISTRICT_ICON_SIZE := 36.0  # khu và nhà mọc thêm cùng cỡ để các nhà to nhỏ đều nhau (kho to hơn)
const HOUSE_ICON_SIZE := DISTRICT_ICON_SIZE  # nhà mọc thêm trong ván (điểm không tên): cùng cỡ khu, không nhãn

const SHAPE_COLOR := Color('#E8E8E8')
const HUB_FILL := Color('#1E1E24')
const HUB_HALF := 16.0
const HUB_BORDER := 3.0
const HUB_CORE_HALF := 4.0
# Ngôi nhà: thân vuông và mái nhọn, tâm đặt ở vị trí của điểm.
const HOUSE := [Vector2(-10, 11), Vector2(10, 11), Vector2(10, -2), Vector2(0, -12), Vector2(-10, -2)]

const LABEL_COLOR := Color('#33485a')
const LABEL_WIDTH := 160.0
const LABEL_GAP := 14.0
const LABEL_SIZE := 13
const LABEL_OUTLINE := 5
const LABEL_OUTLINE_COLOR := Color('#f4f0e7')  # màu nền, để tên vẫn đọc được khi đường chạy qua
# Phông D chọn: có đủ dấu tiếng Việt và được đóng gói vào bản web (SystemFont không có trên web).
const LABEL_FONT := preload('res://assets/fonts/BeVietnamPro-Regular.ttf')

var _icons := {}  # tên icon -> Texture2D, hoặc null nếu không có file

# Nhãn số xe đang đỗ ở mỗi kho (xe trong kho ẩn đi nên cần nhãn này). Node con riêng để chỉ vẽ lại nhãn khi xe đổi trạng thái.
const BADGE_ICON := Vector2(15, 10)
const BADGE_FONT_SIZE := 12
const BADGE_FILL := Color(1, 1, 1, 0.92)
const BADGE_BORDER := Color('#b9cdd6')
const TRUCK_ICON := preload('res://assets/icons/truck.svg')
const BOAT_ICON := preload('res://assets/icons/boat.svg')
var _badges := Node2D.new()

# Tên địa điểm chỉ hiện khi rê chuột lên (góp ý của Lộc: bản đồ tối giản). SHOW_NAMES = true thì luôn hiện như trước.
const SHOW_NAMES := false
const HOVER_PAD := 4.0  # rê chuột trong bán kính icon cộng chừng này px thì hiện tên
var _hover := Node2D.new()
var _hover_id := -1


func _ready() -> void:
	EventBus.game_started.connect(queue_redraw)
	EventBus.point_added.connect(queue_redraw.unbind(1))
	EventBus.edge_state_changed.connect(_on_edge_state)  # bãi đỗ đổi màu theo đoạn kho–cổng khi ngập
	add_child(_badges)
	_badges.draw.connect(_draw_badges)
	EventBus.game_started.connect(_badges.queue_redraw)
	EventBus.vehicle_added.connect(_badges.queue_redraw.unbind(3))
	EventBus.vehicle_state_changed.connect(_badges.queue_redraw.unbind(2))
	add_child(_hover)
	_hover.draw.connect(_draw_hover)
	EventBus.game_started.connect(func() -> void:
		_hover_id = -1
		_hover.queue_redraw())
	queue_redraw()


# Rê chuột: tìm điểm có tên dưới con trỏ, đổi thì chỉ vẽ lại nhãn tên. Không chặn sự kiện (EdgeDrawer vẫn nhận chuột).
func _input(event: InputEvent) -> void:
	if SHOW_NAMES or not event is InputEventMouseMotion:
		return
	var id := _named_point_at(get_local_mouse_position())
	if id != _hover_id:
		_hover_id = id
		_hover.queue_redraw()


# Điểm có tên (kho, khu) gần p nhất trong bán kính icon của nó, hoặc -1.
func _named_point_at(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n == null or n.name.is_empty():
			continue
		var d := n.pos.distance_to(p)
		if d <= _icon_size(n) / 2.0 + HOVER_PAD and d < best_d:
			best = id
			best_d = d
	return best


func _draw_hover() -> void:
	var n := GraphManager.get_map_node(_hover_id) if _hover_id != -1 else null
	if n != null and not n.name.is_empty():
		_draw_name(_hover, n, _icon_size(n) / 2.0)


func _icon_size(n: MapNode) -> float:
	if n.kind == Types.NodeKind.HUB:
		return HUB_ICON_SIZE
	return HOUSE_ICON_SIZE if n.name.is_empty() else DISTRICT_ICON_SIZE


# Tên điểm dưới icon: chữ có viền màu nền để đọc được khi đường chạy qua.
func _draw_name(canvas: CanvasItem, n: MapNode, half_height: float) -> void:
	var label_pos := n.pos + Vector2(-LABEL_WIDTH / 2.0, half_height + LABEL_GAP)
	canvas.draw_string_outline(LABEL_FONT, label_pos, n.name, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_SIZE,
			LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
	canvas.draw_string(LABEL_FONT, label_pos, n.name, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_SIZE, LABEL_COLOR)


func _draw() -> void:
	for id in GraphManager.get_node_ids():
		var hub := GraphManager.get_map_node(id)
		if hub != null and hub.kind == Types.NodeKind.HUB:
			_draw_lot(hub)
			_draw_dock(hub)
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n == null:
			continue
		var half_height := HUB_HALF
		var tex := _icon_of(n)
		if tex != null:
			var size := HUB_ICON_SIZE if n.kind == Types.NodeKind.HUB else DISTRICT_ICON_SIZE
			if n.name.is_empty():
				size = HOUSE_ICON_SIZE
			draw_texture_rect(tex, Rect2(n.pos - Vector2(size, size) / 2.0, Vector2(size, size)), false)
			half_height = size / 2.0
		elif n.kind == Types.NodeKind.HUB:
			_draw_hub(n.pos)
		else:
			_draw_house(n.pos)
		if SHOW_NAMES and not n.name.is_empty():  # mặc định tên chỉ hiện khi rê chuột (_draw_hover); nhà không có tên
			_draw_name(self, n, half_height)


# Icon theo trường `icon` của MapNode (A thêm); bản đồ chưa có trường này thì trả null.
func _icon_of(n: MapNode) -> Texture2D:
	var icon_name = n.get('icon')
	if icon_name == null or str(icon_name).is_empty():
		return null
	if not _icons.has(icon_name):
		var path := ICON_PATH % icon_name
		_icons[icon_name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[icon_name]


func _draw_hub(p: Vector2) -> void:
	var half := Vector2(HUB_HALF, HUB_HALF)
	var core := Vector2(HUB_CORE_HALF, HUB_CORE_HALF)
	draw_rect(Rect2(p - half, half * 2.0), HUB_FILL)
	draw_rect(Rect2(p - half, half * 2.0), SHAPE_COLOR, false, HUB_BORDER)
	draw_rect(Rect2(p - core, core * 2.0), SHAPE_COLOR)


func _draw_house(p: Vector2) -> void:
	var pts := PackedVector2Array()
	for v in HOUSE:
		pts.append(p + v)
	draw_colored_polygon(pts, SHAPE_COLOR)


# Góc trên bên phải mỗi kho: số xe tải, số ca-nô đang đỗ trong kho (chỉ hiện loại xe kho đó có).
# Bãi đỗ của kho (bản đồ có cổng): khung bo tròn ôm nhà kho và ô bãi, kẻ vạch chỗ đỗ hai bên lối đi giữa,
# giống bãi xe của tòa nhà trong Mini Motorways. Vẽ trước icon kho nên nhà kho nằm đè lên phần đầu khung.
# Màu lấy đúng màu đường của EdgeLayer (mặt đường, viền, vạch) theo trạng thái ngập của đoạn kho–cổng; chỗ nối ra đường không viền.
const Road := preload('res://graph/edge_layer.gd')
const PIER_COLOR := Color('#b48c5c')
const PIER_POST := Color('#8c6a42')

func _draw_lot(hub: MapNode) -> void:
	var lot := GraphManager.get_lot_cell(hub.id)
	if lot == Vector2i(-1, -1):
		return
	var center := GraphManager.cell_center(lot)
	var d := Vector2(hub.gate)
	var p := Vector2(-d.y, d.x)
	var mid := (hub.pos + center) / 2.0
	var across := 2.0 * (RescueManager.SLOT_DEPTH + 13.0)
	var along := 2.0 * Config.CELL_SIZE + 4.0
	var size := Vector2(along, across) if d.y == 0.0 else Vector2(across, along)
	var state := Types.EdgeState.DRY
	var link := GraphManager.get_edges_of(hub.id)
	if not link.is_empty():
		state = GraphManager.get_edge(link[0]).state  # đoạn kho–cổng chạy qua bãi
	var colors := {
		Types.EdgeState.DRY: [Road.DRY_COLOR, Road.DRY_CASING, Road.DRY_MARK_COLOR],
		Types.EdgeState.SHALLOW: [Road.SHALLOW_COLOR, Road.SHALLOW_CASING, Road.SHALLOW_MARK_COLOR],
		Types.EdgeState.DEEP: [Road.DEEP_COLOR, Road.DEEP_CASING, Road.DEEP_MARK_COLOR],
	}
	var c: Array = colors[state]
	var box := StyleBoxFlat.new()
	box.bg_color = c[0]
	box.border_color = c[1]
	box.set_border_width_all(int((Road.CASING_WIDTH - Road.ROAD_WIDTH) / 2.0))  # viền dày bằng viền đường
	box.set_corner_radius_all(12)
	draw_style_box(box, Rect2(mid - size / 2.0, size))
	# Chỗ bãi nối ra đường (phía cổng): xóa viền trên đúng bề rộng mặt đường, để bãi liền với đường.
	var edge := mid + d * (along / 2.0 - 1.0)  # giữa dải viền 2 px ở mép bãi phía cổng
	var gap := Vector2(4.0, Road.ROAD_WIDTH) if d.y == 0.0 else Vector2(Road.ROAD_WIDTH, 4.0)
	draw_rect(Rect2(edge - gap / 2.0, gap), c[0])
	var half := RescueManager.LOT_SLOTS / 2
	for side in [-1.0, 1.0]:
		for k in half + 1:  # vạch ngăn giữa các chỗ đỗ, cùng màu vạch chia làn
			var a := (float(k) - half / 2.0) * RescueManager.SLOT_PITCH
			draw_line(center + d * a + p * side * 9.0, center + d * a + p * side * (RescueManager.SLOT_DEPTH + 11.0), c[2], Road.MARK_WIDTH)

# Bến ca-nô: cầu tàu gỗ dọc bờ phía sông của kho, cọc ngăn giữa các chỗ đỗ.
# Mỗi chỗ đỗ ca-nô (nằm trên sông, tại nút nước nối bến) có một cầu tàu ngắn từ mép kho ra, cọc ở đầu cầu.
func _draw_dock(hub: MapNode) -> void:
	var docks := GraphManager.get_dock_nodes(hub.id)
	var slots := RescueManager.dock_slot_nodes(hub.id)
	for i in slots.size():
		if not docks.has(slots[i]):
			continue  # chỗ neo xa hơn (nút sông kề bến): không có cầu tàu
		var s := GraphManager.get_map_node(slots[i]).pos
		var dir := (s - hub.pos).normalized()
		var from := hub.pos + dir * (HUB_ICON_SIZE / 2.0 - 6.0)
		var to := s - dir * 8.0  # dừng trước chỗ ca-nô đỗ
		if hub.pos.distance_to(to) <= hub.pos.distance_to(from):
			continue  # chỗ đỗ sát kho: không cần cầu
		draw_line(from, to, PIER_COLOR, 5.0)
		draw_circle(to, 2.5, PIER_POST)


# Chỉ vẽ lại khi cạnh đổi trạng thái là đoạn kho–cổng (đi qua bãi đỗ).
func _on_edge_state(edge_id: int, _state: int) -> void:
	var e := GraphManager.get_edge(edge_id)
	if e == null:
		return
	for id in [e.node_a, e.node_b]:
		var n := GraphManager.get_map_node(id)
		if n != null and n.kind == Types.NodeKind.HUB:
			queue_redraw()
			return


func _draw_badges() -> void:
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n == null or n.kind != Types.NodeKind.HUB:
			continue
		var items := []
		for type in [Types.VehicleType.TRUCK, Types.VehicleType.BOAT]:
			if RescueManager.get_home_count(id, type) > 0:
				items.append([TRUCK_ICON if type == Types.VehicleType.TRUCK else BOAT_ICON, str(RescueManager.get_idle_count(id, type))])
		if items.is_empty():
			continue
		var widths := []
		var total := 4.0
		for it in items:
			var w: float = BADGE_ICON.x + 2.0 + LABEL_FONT.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE).x + 4.0
			widths.append(w)
			total += w
		# Giữa, phía trên icon kho (bãi đỗ ở bên cạnh); bãi ở phía trên thì đặt sang trái icon.
		var top_left := n.pos + Vector2(-total / 2.0, -HUB_ICON_SIZE / 2.0 - 20.0)
		if n.gate == Vector2i(0, -1):
			top_left = n.pos + Vector2(-HUB_ICON_SIZE / 2.0 - total - 2.0, -8.0)
		var box := StyleBoxFlat.new()
		box.bg_color = BADGE_FILL
		box.border_color = BADGE_BORDER
		box.set_border_width_all(1)
		box.set_corner_radius_all(7)
		_badges.draw_style_box(box, Rect2(top_left, Vector2(total, 16)))
		var x := top_left.x + 4.0
		for i in items.size():
			_badges.draw_texture_rect(items[i][0], Rect2(Vector2(x, top_left.y + 3.0), BADGE_ICON), false)
			_badges.draw_string(LABEL_FONT, Vector2(x + BADGE_ICON.x + 2.0, top_left.y + 12.5), items[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE, LABEL_COLOR)
			x += widths[i]

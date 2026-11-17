extends Node2D
# Chủ sở hữu: E. Vẽ các điểm của bản đồ khi nhận game_started (sau khi A đã load_map).
# Mỗi điểm vẽ bằng icon tòa nhà của D theo trường `icon` trong tệp bản đồ (ví dụ hub_north, hospital).
# Điểm chưa có icon thì vẽ hình khối, phân biệt bằng hình dạng (Tài liệu chốt 1.10): kho ▣, khu dân cư ⌂.

const ICON_PATH := 'res://assets/icons/%s.svg'
const HUB_ICON_SIZE := 56.0
const DISTRICT_ICON_SIZE := 44.0
const HOUSE_ICON_SIZE := 30.0  # nhà mọc thêm trong ván (điểm không tên): nhỏ hơn khu, không nhãn

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


func _ready() -> void:
	EventBus.game_started.connect(queue_redraw)
	EventBus.point_added.connect(queue_redraw.unbind(1))
	add_child(_badges)
	_badges.draw.connect(_draw_badges)
	EventBus.game_started.connect(_badges.queue_redraw)
	EventBus.vehicle_added.connect(_badges.queue_redraw.unbind(3))
	EventBus.vehicle_state_changed.connect(_badges.queue_redraw.unbind(2))
	queue_redraw()


func _draw() -> void:
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
		if n.name.is_empty():
			continue  # nhà không có nhãn
		var label_pos := n.pos + Vector2(-LABEL_WIDTH / 2.0, half_height + LABEL_GAP)
		draw_string_outline(LABEL_FONT, label_pos, n.name, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_SIZE,
				LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
		draw_string(LABEL_FONT, label_pos, n.name, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_SIZE, LABEL_COLOR)


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
		var top_left := n.pos + Vector2(HUB_ICON_SIZE / 2.0 - 10.0, -HUB_ICON_SIZE / 2.0 - 8.0)
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

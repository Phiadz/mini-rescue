extends Node2D
# Chủ sở hữu: E. Vẽ các điểm của bản đồ khi nhận game_started (sau khi A đã load_map).
# Mỗi điểm vẽ bằng icon tòa nhà của D theo trường `icon` trong map_01.json (ví dụ hub_north, hospital).
# Điểm chưa có icon thì vẽ hình khối, phân biệt bằng hình dạng (Tài liệu chốt 1.10): kho ▣, khu dân cư ⌂.

const ICON_PATH := 'res://assets/icons/%s.svg'
const HUB_ICON_SIZE := 72.0
const DISTRICT_ICON_SIZE := 60.0

const SHAPE_COLOR := Color('#E8E8E8')
const HUB_FILL := Color('#1E1E24')
const HUB_HALF := 16.0
const HUB_BORDER := 3.0
const HUB_CORE_HALF := 4.0
# Ngôi nhà: thân vuông và mái nhọn, tâm đặt ở vị trí của điểm.
const HOUSE := [Vector2(-10, 11), Vector2(10, 11), Vector2(10, -2), Vector2(0, -12), Vector2(-10, -2)]

const LABEL_COLOR := Color('#E8E8E8')
const LABEL_WIDTH := 160.0
const LABEL_GAP := 16.0
const LABEL_SIZE := 15
const LABEL_OUTLINE := 5
const LABEL_OUTLINE_COLOR := Color('#1E1E24')  # màu nền, để tên vẫn đọc được khi tuyến chạy qua
# Phông D chọn: có đủ dấu tiếng Việt và được đóng gói vào bản web (SystemFont không có trên web).
const LABEL_FONT := preload('res://assets/fonts/BeVietnamPro-Regular.ttf')

var _icons := {}  # tên icon -> Texture2D, hoặc null nếu không có file


func _ready() -> void:
	EventBus.game_started.connect(queue_redraw)
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
			draw_texture_rect(tex, Rect2(n.pos - Vector2(size, size) / 2.0, Vector2(size, size)), false)
			half_height = size / 2.0
		elif n.kind == Types.NodeKind.HUB:
			_draw_hub(n.pos)
		else:
			_draw_house(n.pos)
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

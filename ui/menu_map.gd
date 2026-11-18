extends Control
## Nền menu chính (theme tối): chính bản đồ Sài Gòn theo lưới, đổi màu sang đêm bằng menu_map_dark.gdshader, với các
## điểm của bản đồ vẽ như trong game và vài khu có vòng SOS nhấp nháy. Cả nền phóng to và trôi rất chậm qua lại.

const GROUND := preload("res://assets/icons/terrain/saigon_grid_base.png")
const DARK := preload("res://ui/menu_map_dark.gdshader")
const ICON_PATH := "res://assets/icons/%s.svg"
const MAP_SIZE := Vector2(1280, 720)
const PLOT := 32.0            # lô đất của khu, như NodeLayer.PLOT_SIZE
const ICON := 30.0
const HUB_ICON := 56.0
const PLOT_COLOR := Color("#233244")
const PLOT_BORDER := Color("#3b5873")
const SOS_COLOR := Color("#ffd23f")
const SOS_POINTS := [4, 12, 15]  # chỉ số điểm (khu, ngoài thẻ menu) có vòng SOS nhấp nháy
const DRIFT_TIME := 48.0        # giây cho một vòng phóng to rồi thu về
const DRIFT_SCALE := 0.05

var _points: Array = []  # [vị trí, texture, là kho]
var _plot := StyleBoxFlat.new()
var _ground := Control.new()  # nền bản đồ: con vẽ sau lưng nút này, có shader đổi màu riêng (icon giữ màu gốc)
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plot.bg_color = PLOT_COLOR
	_plot.border_color = PLOT_BORDER
	_plot.set_border_width_all(2)
	_plot.set_corner_radius_all(7)
	var mat := ShaderMaterial.new()
	mat.shader = DARK
	_ground.material = mat
	_ground.show_behind_parent = true
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	var f := FileAccess.open(Config.MAP_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f != null else null
	if typeof(data) != TYPE_DICTIONARY:
		return
	for n in data.get("nodes", []):
		var path := ICON_PATH % String(n.get("icon", ""))
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		_points.append([Vector2(float(n.x), float(n.y)), tex, int(n.get("kind", 1)) == Types.NodeKind.HUB])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_ground.queue_redraw()


# Phóng to quanh tâm, lệch nhẹ: cả bản đồ luôn phủ kín màn hình. Dùng chung cho nền và các điểm.
func _view() -> Array:
	var k := 0.5 - 0.5 * cos(TAU * _t / DRIFT_TIME)
	var s := (size.x / MAP_SIZE.x) * (1.0 + DRIFT_SCALE * k)
	var focus := MAP_SIZE / 2.0 + Vector2(30.0, -12.0) * k
	return [size / 2.0 - focus * s, s]


func _draw_ground() -> void:
	var v := _view()
	_ground.draw_set_transform(v[0], 0.0, Vector2(v[1], v[1]))
	_ground.draw_texture_rect(GROUND, Rect2(Vector2.ZERO, MAP_SIZE), false)


func _draw() -> void:
	var v := _view()
	draw_set_transform(v[0], 0.0, Vector2(v[1], v[1]))
	for i in _points.size():
		var p: Vector2 = _points[i][0]
		var tex: Texture2D = _points[i][1]
		var hub: bool = _points[i][2]
		if not hub:
			draw_style_box(_plot, Rect2(p - Vector2.ONE * PLOT / 2.0, Vector2.ONE * PLOT))
		if tex != null:
			var w := HUB_ICON if hub else ICON
			draw_texture_rect(tex, Rect2(p - Vector2.ONE * w / 2.0, Vector2.ONE * w), false)
		if SOS_POINTS.has(i):
			var ph := fmod(_t / 1.6 + i * 0.37, 1.0)  # mỗi vòng 1,6 giây, các khu lệch nhịp
			draw_arc(p, 20.0 + 14.0 * ph, 0.0, TAU, 40, Color(SOS_COLOR, 1.0 - ph), 3.0, true)
	draw_set_transform(Vector2.ZERO)

extends Node2D
## Làm nóng shader và ảnh cho bản web (WebGL). Trình duyệt chỉ biên dịch shader và đưa ảnh lên GPU lúc một kiểu nét vẽ
## xuất hiện lần đầu, nên lần chạy đầu game khựng 100–700 ms lúc vào ván và lúc lũ, xe, SOS lần đầu hiện ra (đo bằng dòng
## FPS, ?fpslog trên bản web). Menu thêm nút này làm con đầu tiên, vẽ trước nền menu nên bị che kín: vẽ mỗi kiểu nét
## game dùng (đường cong khử răng cưa, nét mảnh, vòng tròn, cung, đa giác, hộp bo góc, icon xoay lật, chữ, hai shader
## nước, ảnh nền bản đồ) trong FRAMES khung hình, rồi báo finished và tự xóa. Màn khởi động (ui/boot.gd) dùng nút này
## trước khi vào game, nên menu hiện ra là bấm được ngay.

signal finished

const FRAMES := 4
const ICON_DIR := 'res://assets/icons/'
const GROUND := 'res://assets/icons/terrain/saigon_grid_base.png'  # ảnh nền 2560 × 1440: đưa lên GPU từ lúc ở menu
const SHADERS := [preload('res://flood/water_grid.gdshader'), preload('res://flood/water.gdshader'), preload('res://ui/menu_map_dark.gdshader')]
const FONT := preload('res://assets/fonts/BeVietnamPro-Regular.ttf')

var _textures: Array[Texture2D] = []
var _left := FRAMES


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in ResourceLoader.list_directory(ICON_DIR):
		if f.ends_with('.svg') or f.ends_with('.png'):
			var t := load(ICON_DIR + f) as Texture2D
			if t != null:
				_textures.append(t)
	if ResourceLoader.exists(GROUND):
		_textures.append(load(GROUND))
	# Hai shader nước của FloodOverlay: mỗi shader một nút con có vật liệu riêng, vẽ một hình chữ nhật như lớp lũ.
	var img := Image.create(Config.GRID_COLS, Config.GRID_ROWS, false, Image.FORMAT_RGBH)
	var field := ImageTexture.create_from_image(img)
	for shader in SHADERS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter('field_prev', field)
		mat.set_shader_parameter('field_next', field)
		var n := Node2D.new()
		n.material = mat
		n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		n.draw.connect(func() -> void: n.draw_texture_rect(field, Rect2(0, 0, 64, 36), false))
		add_child(n)


func _process(_delta: float) -> void:
	_left -= 1
	if _left > 0:
		queue_redraw()
		for c in get_children():
			(c as CanvasItem).queue_redraw()
		return
	finished.emit()
	queue_free()


func _draw() -> void:
	var c := Color(1, 1, 1, 1)
	var pts := PackedVector2Array([Vector2(10, 10), Vector2(40, 22), Vector2(60, 50), Vector2(90, 52)])
	draw_polyline(pts, c, 22.0, true)       # đường (EdgeLayer), khử răng cưa
	draw_polyline(pts, c, 3.0, false)
	draw_line(Vector2(0, 0), Vector2(30, 0), c, 2.0)   # vạch đứt, lan can
	draw_line(Vector2(0, 4), Vector2(30, 4), c, -1.0)  # nét mảnh 1 px
	draw_circle(Vector2(20, 20), 10.0, c)
	draw_arc(Vector2(40, 40), 12.0, 0.0, TAU, 24, c, 3.0, true)   # vòng SOS, vòng chọn
	draw_arc(Vector2(40, 40), 14.0, 0.0, PI, 12, c, 2.0, false)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(20, 5), Vector2(8, 18)]), c)
	draw_rect(Rect2(0, 0, 20, 20), c)
	draw_rect(Rect2(0, 0, 20, 20), c, false, 2.0)
	for shadow in [0, 4]:
		var box := StyleBoxFlat.new()
		box.bg_color = c
		box.border_color = c
		box.set_border_width_all(2)
		box.set_corner_radius_all(8)
		box.shadow_size = shadow
		draw_style_box(box, Rect2(0, 0, 40, 30))
	for t in _textures:
		draw_texture_rect(t, Rect2(0, 0, 24, 24), false)
		draw_texture_rect(t, Rect2(0, 0, 24, 24), false, Color(1, 1, 1, 0.5))
	if not _textures.is_empty():
		draw_set_transform(Vector2(30, 30), 0.7, Vector2(-0.8, 0.8))  # xe xoay, lật
		draw_texture_rect(_textures[0], Rect2(-10, -7, 21, 14), false)
		draw_set_transform(Vector2.ZERO)
	draw_string(FONT, Vector2(0, 20), 'Ẩ 0', HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
	draw_string_outline(FONT, Vector2(0, 40), 'Ẩ 0', HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, c)

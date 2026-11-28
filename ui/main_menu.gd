extends Control
## Menu chính kiểu tối giản như bản đồ (Mini Motorways), theme tối: nền là chính bản đồ Sài Gòn theo lưới đổi màu đêm
## (ui/menu_map.gd), giữa màn hình là thẻ xanh đen có tên game và ba nút phẳng. Dựng bằng Control, không nướng chữ vào ảnh.
signal start_pressed
signal guide_pressed
signal audio_pressed
signal volume_changed(value: float)

const Style = preload("res://ui/style.gd")
const MenuMap = preload("res://ui/menu_map.gd")
const BOLD = preload("res://assets/fonts/BeVietnamPro-Bold.ttf")
const BOAT = preload("res://assets/icons/boat.svg")

const CARD_SIZE := Vector2(588, 632)
const INK := Color("#f2f8ff")      # chữ: trắng ngà như HUD
const TEAL := Color("#4fd3ec")     # phụ đề, viền nút khi rê chuột
const CARD_BG := Color("#0f1d2c")  # thẻ: xanh đen như bảng HUD
const LINE := Color("#2a4a63")     # viền thẻ, viền nút
const BUTTON_BG := Color("#16283a")
const PLAY := Color("#ffd23f")     # nút chơi: vàng như điểm số trên HUD
const PLAY_INK := Color("#10324d")  # chữ trên nút vàng
const BUTTON_W := 448.0
const BUTTON_H := 78.0
const BUTTON_GAP := 20.0
const BUTTONS_TOP := 346.0         # tính từ mép trên thẻ

var _root: Control


func _ready() -> void:
	var map := MenuMap.new()
	add_child(map)
	Style.full(map)

	_root = Control.new()
	add_child(_root)
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.anchor_top = 0.5
	_root.anchor_bottom = 0.5
	_root.offset_left = -CARD_SIZE.x * 0.5
	_root.offset_right = CARD_SIZE.x * 0.5
	_root.offset_top = -CARD_SIZE.y * 0.5 - 24.0
	_root.offset_bottom = CARD_SIZE.y * 0.5 - 24.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_card()
	_build_buttons()
	_build_tagline()


func _build_card() -> void:
	var card := Panel.new()
	_root.add_child(card)
	card.position = Vector2.ZERO
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Style.rounded(CARD_BG, LINE, 30, 2)
	box.shadow_color = Color(0, 0, 0, 0.42)
	box.shadow_size = 24
	box.shadow_offset = Vector2(0, 8)
	card.add_theme_stylebox_override("panel", box)
	var boat := TextureRect.new()
	_root.add_child(boat)
	boat.texture = BOAT
	boat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boat.position = Vector2((CARD_SIZE.x - 118.0) * 0.5, 48.0)
	boat.size = Vector2(118, 78)
	boat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Style.text(_root, "FLOODLINE", 0.0, 140.0, CARD_SIZE.x, 106.0, 82, INK, true)
	title.add_theme_font_override("font", BOLD)
	var subtitle := Style.text(_root, "C Ứ U   H Ộ   0   G I Ờ", 0.0, 248.0, CARD_SIZE.x, 42.0, 24, TEAL, true)
	subtitle.add_theme_font_override("font", BOLD)


func _build_buttons() -> void:
	var y := BUTTONS_TOP
	var play := _button("CHƠI NGAY", y, PLAY, 32, PLAY_INK)
	play.pressed.connect(func() -> void: start_pressed.emit())
	y += BUTTON_H + BUTTON_GAP
	var guide := _button("HƯỚNG DẪN", y, BUTTON_BG, 28, INK)
	guide.pressed.connect(func() -> void: guide_pressed.emit())
	y += BUTTON_H + BUTTON_GAP
	var audio := _button("ÂM LƯỢNG", y, BUTTON_BG, 28, INK)
	audio.pressed.connect(func() -> void: audio_pressed.emit())


# Nút phẳng: giữ hiệu ứng rê chuột, bấm và tiếng của Style.button, chỉ đổi màu nền, viền, chữ.
func _button(caption: String, y: float, fill: Color, font_size: int, ink: Color) -> Button:
	var b := Style.button(_root, caption, (CARD_SIZE.x - BUTTON_W) * 0.5, y, BUTTON_W, BUTTON_H, fill, font_size, ink)
	b.add_theme_font_override("font", BOLD)
	b.add_theme_stylebox_override("normal", Style.rounded(fill, LINE, 18, 2))
	b.add_theme_stylebox_override("hover", Style.rounded(fill.lightened(0.1), TEAL, 18, 2))
	b.add_theme_stylebox_override("pressed", Style.rounded(fill.darkened(0.08), TEAL, 18, 2))
	b.add_theme_stylebox_override("focus", Style.rounded(Color.TRANSPARENT, TEAL, 18, 2))
	return b


func _build_tagline() -> void:
	var w := 650.0
	var x := (CARD_SIZE.x - w) * 0.5
	var y := CARD_SIZE.y + 30.0
	var pill := Panel.new()
	_root.add_child(pill)
	pill.position = Vector2(x, y)
	pill.size = Vector2(w, 48)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", Style.rounded(Color(CARD_BG, 0.92), LINE, 24, 2))
	var lbl := Style.text(_root, "LẬP KẾ HOẠCH  •  CỨU HỘ  •  CHẠY ĐUA VỚI LŨ", x, y, w, 48, 20, Style.MUTED, true)
	lbl.add_theme_font_override("font", BOLD)

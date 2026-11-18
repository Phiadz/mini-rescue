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

const SCREEN_W := 1280.0
const CARD := Rect2(430, 118, 420, 452)
const INK := Color("#f2f8ff")      # chữ: trắng ngà như HUD
const TEAL := Color("#4fd3ec")     # phụ đề, viền nút khi rê chuột
const CARD_BG := Color("#0f1d2c")  # thẻ: xanh đen như bảng HUD
const LINE := Color("#2a4a63")     # viền thẻ, viền nút
const BUTTON_BG := Color("#16283a")
const PLAY := Color("#ffd23f")     # nút chơi: vàng như điểm số trên HUD
const PLAY_INK := Color("#10324d")  # chữ trên nút vàng
const BUTTON_W := 320.0
const BUTTON_H := 56.0
const BUTTON_GAP := 14.0
const BUTTONS_TOP := 248.0         # tính từ mép trên thẻ


func _ready() -> void:
	var map := MenuMap.new()
	add_child(map)
	Style.full(map)
	_build_card()
	_build_buttons()
	_build_tagline()


func _build_card() -> void:
	var card := Panel.new()
	add_child(card)
	card.position = CARD.position
	card.size = CARD.size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Style.rounded(CARD_BG, LINE, 22, 2)
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 18
	box.shadow_offset = Vector2(0, 6)
	card.add_theme_stylebox_override("panel", box)
	var boat := TextureRect.new()
	add_child(boat)
	boat.texture = BOAT
	boat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boat.position = Vector2(CARD.position.x + (CARD.size.x - 84.0) / 2.0, CARD.position.y + 34.0)
	boat.size = Vector2(84, 56)
	boat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Style.text(self, "FLOODLINE", CARD.position.x, CARD.position.y + 100.0, CARD.size.x, 76, 60, INK, true)
	title.add_theme_font_override("font", BOLD)
	var subtitle := Style.text(self, "C Ứ U   H Ộ   0   G I Ờ", CARD.position.x, CARD.position.y + 178.0, CARD.size.x, 30, 18, TEAL, true)
	subtitle.add_theme_font_override("font", BOLD)


func _build_buttons() -> void:
	var y := CARD.position.y + BUTTONS_TOP
	var play := _button("CHƠI NGAY", y, PLAY, 24, PLAY_INK)
	play.pressed.connect(func() -> void: start_pressed.emit())
	y += BUTTON_H + BUTTON_GAP
	var guide := _button("HƯỚNG DẪN", y, BUTTON_BG, 21, INK)
	guide.pressed.connect(func() -> void: guide_pressed.emit())
	y += BUTTON_H + BUTTON_GAP
	var audio := _button("ÂM LƯỢNG", y, BUTTON_BG, 21, INK)
	audio.pressed.connect(func() -> void: audio_pressed.emit())


# Nút phẳng: giữ hiệu ứng rê chuột, bấm và tiếng của Style.button, chỉ đổi màu nền, viền, chữ.
func _button(caption: String, y: float, fill: Color, font_size: int, ink: Color) -> Button:
	var b := Style.button(self, caption, (SCREEN_W - BUTTON_W) / 2.0, y, BUTTON_W, BUTTON_H, fill, font_size, ink)
	b.add_theme_font_override("font", BOLD)
	b.add_theme_stylebox_override("normal", Style.rounded(fill, LINE, 14, 2))
	b.add_theme_stylebox_override("hover", Style.rounded(fill.lightened(0.1), TEAL, 14, 2))
	b.add_theme_stylebox_override("pressed", Style.rounded(fill.darkened(0.08), TEAL, 14, 2))
	b.add_theme_stylebox_override("focus", Style.rounded(Color.TRANSPARENT, TEAL, 14, 2))
	return b


func _build_tagline() -> void:
	var w := 470.0
	var x := (SCREEN_W - w) / 2.0
	var y := CARD.end.y + 22.0
	var pill := Panel.new()
	add_child(pill)
	pill.position = Vector2(x, y)
	pill.size = Vector2(w, 34)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", Style.rounded(Color(CARD_BG, 0.9), LINE, 17, 1))
	Style.text(self, "LẬP KẾ HOẠCH  •  CỨU HỘ  •  CHẠY ĐUA VỚI LŨ", x, y, w, 34, 15, Style.MUTED, true)

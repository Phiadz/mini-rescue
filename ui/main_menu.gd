extends Control
## Main menu built from real Control nodes (not baked into one image), so the layout stays balanced:
## title block on top, three equal buttons centred below, tagline at the bottom.
signal start_pressed
signal guide_pressed
signal audio_pressed
signal volume_changed(value: float)

const Style = preload("res://ui/style.gd")
# Both images were separated from floodline_menu_art.png: the background is its right part (no baked
# logo or buttons), the logo is the FLOODLINE title keyed onto a transparent background.
const MENU_BG = preload("res://assets/images/floodline_menu_bg.png")
const LOGO = preload("res://assets/images/floodline_logo.png")

const SCREEN_W := 1280.0
const LOGO_W := 360.0
const LOGO_HEIGHT_SCALE := 0.82 # logo drawn a bit shorter than its natural aspect, looks less tall above the buttons
const LOGO_TOP := 60.0
const BUTTON_W := 400.0
const BUTTON_H := 66.0
const BUTTON_GAP := 20.0
const BUTTONS_TOP := 384.0

func _ready() -> void:
	_build_background()
	_build_title()
	_build_buttons()
	Style.text(self, "LẬP KẾ HOẠCH  •  CỨU HỘ  •  CHẠY ĐUA VỚI LŨ", 0, 652, SCREEN_W, 36, 19, Style.WHITE, true)

func _build_background() -> void:
	var bg := TextureRect.new()
	add_child(bg)
	Style.full(bg)
	bg.texture = MENU_BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	add_child(shade)
	Style.full(shade)
	shade.color = Color(0.0, 0.03, 0.09, 0.42)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_title() -> void:
	var logo := TextureRect.new()
	add_child(logo)
	var size := Vector2(LOGO_W, LOGO_W * LOGO.get_height() / LOGO.get_width() * LOGO_HEIGHT_SCALE)
	logo.position = Vector2((SCREEN_W - size.x) / 2.0, LOGO_TOP)
	logo.size = size
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var subtitle := Style.text(self, "CỨU HỘ 0 GIỜ", 0, LOGO_TOP + size.y + 6, SCREEN_W, 40, 28, Style.CYAN, true)
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.add_theme_color_override("font_outline_color", Color("#06142a"))

func _build_buttons() -> void:
	var x := (SCREEN_W - BUTTON_W) / 2.0
	var y := BUTTONS_TOP
	var play := Style.button(self, "▶   CHƠI NGAY", x, y, BUTTON_W, BUTTON_H, Style.YELLOW, 30, Style.NIGHT)
	play.pressed.connect(func() -> void: start_pressed.emit())
	y += BUTTON_H + BUTTON_GAP
	var guide := Style.button(self, "▣   HƯỚNG DẪN", x, y, BUTTON_W, BUTTON_H, Style.PANEL, 27)
	guide.pressed.connect(func() -> void: guide_pressed.emit())
	y += BUTTON_H + BUTTON_GAP
	var audio := Style.button(self, "◖))   ÂM LƯỢNG", x, y, BUTTON_W, BUTTON_H, Style.PANEL, 27)
	audio.pressed.connect(func() -> void: audio_pressed.emit())

extends Control
## Main menu built from real Control nodes (not baked into one image), so the layout stays balanced:
## title block on top, three equal buttons centred below, tagline at the bottom.
signal start_pressed
signal guide_pressed
signal audio_pressed
signal volume_changed(value: float)

const Style = preload("res://ui/style.gd")
const TITLE_FONT = preload("res://assets/fonts/BeVietnamPro-Bold.ttf")

const SCREEN_W := 1280.0
const BUTTON_W := 400.0
const BUTTON_H := 66.0
const BUTTON_GAP := 20.0
const BUTTONS_TOP := 372.0

func _ready() -> void:
	Style.background(self, Color(0.0, 0.03, 0.09, 0.45))
	_build_title()
	_build_buttons()
	Style.text(self, "LẬP KẾ HOẠCH  •  CỨU HỘ  •  CHẠY ĐUA VỚI LŨ", 0, 646, SCREEN_W, 36, 19, Style.MUTED, true)

func _build_title() -> void:
	var title := Style.text(self, "FLOODLINE", 0, 112, SCREEN_W, 130, 104, Style.YELLOW, true)
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color("#0b2a4a"))
	Style.text(self, "﹏﹏﹏   CỨU HỘ 0 GIỜ   ﹏﹏﹏", 0, 246, SCREEN_W, 48, 30, Style.CYAN, true)

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

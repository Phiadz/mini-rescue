extends Control
signal start_pressed
signal guide_pressed
signal audio_pressed
signal volume_changed(value: float)

const Style = preload("res://ui/style.gd")
const MENU_ART = preload("res://assets/images/floodline_menu_art.png")

var muted: bool = false
var saved_volume: float = 0.65

func _ready() -> void:
	_build_background()
	_build_hotspots()

func _build_background() -> void:
	var bg := TextureRect.new()
	add_child(bg)
	Style.full(bg)
	bg.texture = MENU_ART
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_hotspots() -> void:
	var play := _hotspot_button(Rect2(168, 378, 255, 90), "Bắt đầu chơi")
	play.pressed.connect(func() -> void: start_pressed.emit())

	var guide := _hotspot_button(Rect2(168, 490, 255, 80), "Mở hướng dẫn")
	guide.pressed.connect(func() -> void: guide_pressed.emit())

	var volume := _hotspot_button(Rect2(168, 602, 255, 80), "Bật hoặc tắt âm lượng")
	volume.pressed.connect(func() -> void: audio_pressed.emit())

func _toggle_volume() -> void:
	muted = not muted
	if muted:
		volume_changed.emit(0.0)
	else:
		volume_changed.emit(saved_volume)

func _hotspot_button(area: Rect2, tooltip: String) -> Button:
	var button := Button.new()
	add_child(button)
	button.position = area.position
	button.size = area.size
	button.text = ""
	button.tooltip_text = tooltip
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", Style.rounded(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 14, 0))
	button.add_theme_stylebox_override("hover", Style.rounded(Color(1, 1, 1, 0.05), Color("#8fd9ff"), 14, 2))
	button.add_theme_stylebox_override("pressed", Style.rounded(Color(1, 1, 1, 0.08), Color("#8fd9ff"), 14, 2))
	button.add_theme_stylebox_override("focus", Style.rounded(Color(1, 1, 1, 0.0), Color("#8fd9ff"), 14, 2))
	button.pressed.connect(func() -> void: AudioManager.play_sfx(&"ui_click"))
	return button

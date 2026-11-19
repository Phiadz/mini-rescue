extends RefCounted
## Reusable Zero-Art theme helpers. The UI uses Control nodes, not baked text in images.

const NIGHT := Color("#1E1E24")
const PANEL := Color("#172637")
const BORDER := Color("#2577b2")
const WHITE := Color("#f2f8ff")
const MUTED := Color("#b5cadb")
const BLUE := Color("#0073e6")
const CYAN := Color("#16d8ff")
const YELLOW := Color("#ffd700")
const ORANGE := Color("#ff4500")

static func rounded(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 12, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_width
	s.border_width_right = border_width
	s.border_width_top = border_width
	s.border_width_bottom = border_width
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	# Soft shadow tinh tế giúp UI có chiều sâu hiện đại
	s.shadow_color = Color(0, 0, 0, 0.18)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s

static func full(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

static func background(parent: Node, tint: Color = Color(0, 0, 0, 0.3)) -> void:
	# Required zero-art background colour: #1E1E24. Artwork is optional decoration.
	var base := ColorRect.new()
	parent.add_child(base)
	full(base)
	base.color = NIGHT
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	parent.add_child(tex)
	full(tex)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.texture = load("res://assets/images/night_village.png")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var overlay := ColorRect.new()
	parent.add_child(overlay)
	full(overlay)
	overlay.color = tint
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func rect(parent: Node, x: float, y: float, w: float, h: float, bg: Color = PANEL, border: Color = BORDER, radius: int = 12) -> Panel:
	var p := Panel.new()
	parent.add_child(p)
	p.position = Vector2(x, y)
	p.size = Vector2(w, h)
	p.add_theme_stylebox_override("panel", rounded(bg, border, radius))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func text(parent: Node, caption: String, x: float, y: float, w: float, h: float, font_size: int = 22, color: Color = WHITE, centered: bool = false) -> Label:
	var l := Label.new()
	parent.add_child(l)
	l.text = caption
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func button(parent: Node, caption: String, x: float, y: float, w: float, h: float, fill: Color = BLUE, font_size: int = 25, fg: Color = WHITE) -> Button:
	var b := Button.new()
	parent.add_child(b)
	b.text = caption
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.pivot_offset = Vector2(w / 2.0, h / 2.0)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_stylebox_override("normal", rounded(fill, BORDER, 10, 2))
	b.add_theme_stylebox_override("hover", rounded(fill.lightened(0.18), CYAN, 10, 2))
	b.add_theme_stylebox_override("pressed", rounded(fill.darkened(0.2), CYAN, 10, 2))
	b.add_theme_stylebox_override("focus", rounded(Color.TRANSPARENT, CYAN, 10, 2))
	b.add_theme_stylebox_override("disabled", rounded(PANEL, BORDER, 10, 2))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Juicy hover & press feedback
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		AudioManager.play_sfx(&"ui_hover")
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	b.mouse_exited.connect(func() -> void:
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(b, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE)
	)
	b.button_down.connect(func() -> void:
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(b, "scale", Vector2(0.96, 0.96), 0.05).set_trans(Tween.TRANS_QUAD)
	)
	b.button_up.connect(func() -> void:
		var tw := b.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var target := Vector2(1.05, 1.05) if b.is_hovered() else Vector2.ONE
		tw.tween_property(b, "scale", target, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

	# All interface buttons provide the same click sound, including Pause/Reward/End.
	# AudioManager has PROCESS_MODE_ALWAYS so this still plays while the game is paused.
	b.pressed.connect(func() -> void: AudioManager.play_sfx(&"ui_click"))
	return b

## Hiệu ứng xuất hiện nảy mượt mà (Pop-in) cho các cửa sổ / menu
static func pop_in(target: Control, from_scale: float = 0.94, duration: float = 0.22) -> void:
	target.pivot_offset = target.size / 2.0
	target.scale = Vector2(from_scale, from_scale)
	target.modulate.a = 0.0
	var tw := target.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(target, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(target, "modulate:a", 1.0, duration * 0.75).set_trans(Tween.TRANS_SINE)

static func bar(parent: Node, x: float, y: float, w: float, h: float, amount: float, color: Color = CYAN) -> ProgressBar:
	var b := ProgressBar.new()
	parent.add_child(b)
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.max_value = 100.0
	b.value = clampf(amount, 0.0, 100.0)
	b.show_percentage = false
	b.add_theme_stylebox_override("background", rounded(Color("#13364e"), Color.TRANSPARENT, 6, 0))
	b.add_theme_stylebox_override("fill", rounded(color, Color.TRANSPARENT, 6, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func separator(parent: Node, y: float) -> void:
	var c := ColorRect.new()
	parent.add_child(c)
	c.position = Vector2(45, y)
	c.size = Vector2(1190, 2)
	c.color = Color("#126193")
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

extends Node2D
## Visual-only SOS marker. Does not decide success/failure or the priority rules.
var request_id: int = 0
var supply: int = 0
var time_total: float = 60.0
var time_left: float = 60.0
var assigned: bool = false
var prioritized: bool = false
var elapsed: float = 0.0
var display_label: Label

func setup(req_id: int, kind: int, total: float) -> void:
	request_id = req_id
	supply = kind
	time_total = maxf(1.0, total)
	time_left = time_total

func _ready() -> void:
	display_label = Label.new()
	add_child(display_label)
	display_label.position = Vector2(-32, -18)
	display_label.size = Vector2(64, 36)
	display_label.text = "+" if supply == 1 else "SOS"
	display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	display_label.add_theme_font_size_override("font_size", 20)
	display_label.add_theme_color_override("font_color", Color.WHITE)
	display_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	time_left = maxf(0.0, time_left-delta)
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.72+0.28*sin(elapsed*6.0)
	draw_circle(Vector2.ZERO, 30.0, Color(1.0,0.27,0.0,pulse))
	draw_arc(Vector2.ZERO, 36, -PI/2.0, -PI/2.0 + TAU*(time_left/time_total), 44, Color("#ffd700"), 4.0, true)
	if prioritized:
		draw_arc(Vector2.ZERO, 43, 0.0, TAU, 48, Color("#ffd700"), 3.0, true)
	if not assigned and elapsed > 3.0:
		draw_arc(Vector2.ZERO, 48, 0.0, TAU, 48, Color(1.0,0.1,0.1,absf(sin(elapsed*5.0))), 4.0, true)

func mark_assigned() -> void:
	assigned = true

func set_priority(is_prioritized: bool) -> void:
	prioritized = is_prioritized

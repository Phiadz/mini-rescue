extends Node2D
## Visual-only SOS marker. Does not decide success/failure or the priority rules.
## The SOS bubble (assets/icons/sos.svg, sos_medical.svg) floats above the district's building
## so the building stays visible; the countdown, priority and warning rings surround the building.
const SOS_ICON = preload("res://assets/icons/sos.svg")
const SOS_MEDICAL_ICON = preload("res://assets/icons/sos_medical.svg")
const BUBBLE_OFFSET := Vector2(0, -54)
const BUBBLE_SIZE := Vector2(48, 40)
const BUBBLE_HIT_RADIUS := 28.0
var request_id: int = 0
var supply: int = 0
var time_total: float = 60.0
var time_left: float = 60.0
var assigned: bool = false
var prioritized: bool = false
var elapsed: float = 0.0
var units_left: int = 1  # SOS lớn cần nhiều phần hàng (nhiều xe): hiện "×N" ở góc bong bóng

func setup(req_id: int, kind: int, total: float) -> void:
	request_id = req_id
	supply = kind
	time_total = maxf(1.0, total)
	time_left = time_total

func _process(delta: float) -> void:
	time_left = maxf(0.0, time_left-delta)
	elapsed += delta
	units_left = RescueManager.get_units_left(request_id)
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.72+0.28*sin(elapsed*6.0)
	var icon: Texture2D = SOS_MEDICAL_ICON if supply == Types.SupplyType.MEDICAL else SOS_ICON
	draw_texture_rect(icon, Rect2(BUBBLE_OFFSET - BUBBLE_SIZE/2.0, BUBBLE_SIZE), false, Color(1.0,1.0,1.0,pulse))
	draw_arc(Vector2.ZERO, 36, -PI/2.0, -PI/2.0 + TAU*(time_left/time_total), 44, Color("#ffd700"), 4.0, true)
	if prioritized:
		draw_arc(Vector2.ZERO, 43, 0.0, TAU, 48, Color("#ffd700"), 3.0, true)
	if not assigned and elapsed > 3.0:
		draw_arc(Vector2.ZERO, 48, 0.0, TAU, 48, Color(1.0,0.1,0.1,absf(sin(elapsed*5.0))), 4.0, true)
	if units_left > 1:
		var c := BUBBLE_OFFSET + Vector2(BUBBLE_SIZE.x / 2.0, -BUBBLE_SIZE.y / 2.0) + Vector2(-2, 4)
		draw_circle(c, 11.0, Color("#e63946"))
		draw_arc(c, 11.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
		draw_string(ThemeDB.fallback_font, c + Vector2(-9, 5), "x%d" % units_left, HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Color.WHITE)

## True when p (same coordinates as position) is on the bubble. Only the bubble is clickable, so a
## press on the building itself still reaches the route drawer (dragging a new route from this district).
func hit(p: Vector2) -> bool:
	return p.distance_to(position + BUBBLE_OFFSET * scale) < BUBBLE_HIT_RADIUS * scale.x  # scale < 1 khi camera phóng to

func mark_assigned() -> void:
	assigned = true

func set_priority(is_prioritized: bool) -> void:
	prioritized = is_prioritized

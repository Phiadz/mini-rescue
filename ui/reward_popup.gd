extends Control

## Màn hình chọn thẻ (Card Draft) trước đợt 1 và giữa mỗi đợt (Owner: E).
## Chỉ hiển thị dữ liệu offer từ backend (C) và gửi đúng 1 lựa chọn qua GameManager.choose_card(card_id).
## Không tự tính xác suất, không cộng inventory, không tự giữ cờ pause hay tự bắt đầu đợt.

signal card_selected(card_id: StringName)
signal card_chosen(card_id: StringName)

const Style = preload("res://ui/style.gd")
const FONT_BOLD = preload("res://assets/fonts/BeVietnamPro-Bold.ttf")

const EXPECTED_CARD_COUNT := 4

# Hợp đồng Types.Reward (0–4 có sẵn; 5–8 C nối thêm theo tài liệu giao việc mục 2).
const REWARD_MORE_EDGES := 0
const REWARD_EXTRA_TRUCK := 1
const REWARD_EXTRA_BOAT := 2
const REWARD_UPGRADE_TRUCK_CAP := 3
const REWARD_UPGRADE_BOAT_CAP := 4
const REWARD_TRAFFIC_LIGHT := 5
const REWARD_ROUNDABOUT := 6
const REWARD_HIGHWAY := 7
const REWARD_FERRY := 8

const REWARD_META := {
	REWARD_MORE_EDGES: {"label": "Ô đường", "accent": Color("#f3c86b"), "icon": &"road"},
	REWARD_EXTRA_TRUCK: {"label": "Xe tải", "accent": Color("#ffd23f"), "icon": &"truck"},
	REWARD_EXTRA_BOAT: {"label": "Ca-nô", "accent": Color("#4fd3ec"), "icon": &"boat"},
	REWARD_UPGRADE_TRUCK_CAP: {"label": "Tải 2 ngăn", "accent": Color("#ffd23f"), "icon": &"upgrade_truck", "upgrade": true},
	REWARD_UPGRADE_BOAT_CAP: {"label": "Ca-nô 2 ngăn", "accent": Color("#4fd3ec"), "icon": &"upgrade_boat", "upgrade": true},
	REWARD_TRAFFIC_LIGHT: {"label": "Đèn giao thông", "accent": Color("#5ee3b0"), "icon": &"traffic_light"},
	REWARD_ROUNDABOUT: {"label": "Vòng xoay", "accent": Color("#5ee3b0"), "icon": &"roundabout"},
	REWARD_HIGHWAY: {"label": "Đường cao tốc", "accent": Color("#7cb8ff"), "icon": &"highway"},
	REWARD_FERRY: {"label": "Phà vượt sông", "accent": Color("#4fd3ec"), "icon": &"ferry"},
}

# Bảng icon_key khớp chính xác catalog mục 7 của tài liệu giao việc.
const TEMPLATE_STYLE := {
	&"road_supply": {"icon": &"road", "accent": Color("#f3c86b")},
	&"truck_fleet": {"icon": &"truck", "accent": Color("#ffd23f")},
	&"boat_fleet_ferry": {"icon": &"boat_ferry", "accent": Color("#4fd3ec")},
	&"junction_kit": {"icon": &"junction", "accent": Color("#5ee3b0")},
	&"highway_ferry": {"icon": &"highway_ferry", "accent": Color("#7cb8ff")},
	&"boat_capacity": {"icon": &"upgrade_boat", "accent": Color("#4fd3ec")},
	&"truck_capacity": {"icon": &"upgrade_truck", "accent": Color("#ffd23f")},
	&"road_highway": {"icon": &"road_highway", "accent": Color("#7cb8ff")},
}

const COLOR_DIM := Color(0.03, 0.06, 0.10, 0.80)
const COLOR_CARD_BG := Color("#121e2b")
const COLOR_CARD_HOVER := Color("#1a2b3d")
const COLOR_CARD_PRESSED := Color("#0f1a26")
const COLOR_CARD_SELECTED := Color("#192d40")
const COLOR_CARD_DISABLED := Color("#0c141d")
const COLOR_CARD_BORDER := Color("#2a4259")
const COLOR_CARD_DISABLED_BORDER := Color("#1e2e3d")
const COLOR_INNER_BG := Color("#0c1520")
const COLOR_ERROR := Color("#ff6b6b")
const COLOR_ERROR_BG := Color(0.32, 0.08, 0.10, 0.92)
const COLOR_INK := Color("#f2f8ff")
const COLOR_MUTED := Color("#8ea8be")
const COLOR_GOLD := Color("#ffd23f")
const COLOR_CYAN := Color("#4fd3ec")

var _margin: MarginContainer
var _root_vbox: VBoxContainer
var _eyebrow_label: Label
var _title_label: Label
var _error_banner: PanelContainer
var _error_label: Label
var _cards_grid: GridContainer
var _footer_label: Label

var _offers: Array = []
var _card_entries: Array[Dictionary] = []  # {button, id, valid, disabled, accent, cta_pill, cta_label}
var _submitting := false
var _selected_card_id: StringName = &""
var _error_message := ""
var _last_errors: PackedStringArray = PackedStringArray()
var _pop_tween: Tween = null
var _syncing_visibility := false

# Hook tuỳ chọn cho test tự động; mặc định gọi trực tiếp GameManager theo hợp đồng C.
var _get_offers_fn: Callable = Callable()
var _choose_card_fn: Callable = Callable()


# Biểu tượng vector tối giản đồng bộ nhận diện Floodline (không phụ thuộc file .ctex chưa import).
class CardEmblem extends Control:
	var icon_type: StringName = &"road"
	var accent: Color = Color("#4fd3ec")
	var ink: Color = Color("#f2f8ff")
	var dimmed := false

	func _draw() -> void:
		var s := minf(size.x, size.y)
		if s <= 1.0:
			return
		var c := size * 0.5
		var col := accent if not dimmed else Color("#4a5d6e")
		var hi := ink if not dimmed else Color("#6b7f91")
		var r := s * 0.44
		match icon_type:
			&"road":
				_draw_road(c, r, col, hi)
			&"truck":
				_draw_truck(c, r, col, hi)
			&"boat":
				_draw_boat(c, r, col, hi)
			&"upgrade_truck":
				_draw_truck(c + Vector2(-r * 0.12, r * 0.14), r * 0.80, col, hi)
				_draw_upgrade_chevron(c + Vector2(r * 0.42, -r * 0.40), r * 0.36, hi)
			&"upgrade_boat":
				_draw_boat(c + Vector2(-r * 0.12, r * 0.14), r * 0.80, col, hi)
				_draw_upgrade_chevron(c + Vector2(r * 0.42, -r * 0.40), r * 0.36, hi)
			&"traffic_light":
				_draw_traffic_light(c, r, col, hi)
			&"roundabout":
				_draw_roundabout(c, r, col, hi)
			&"highway":
				_draw_highway(c, r, col, hi)
			&"ferry":
				_draw_ferry(c, r, col, hi)
			&"boat_ferry":
				_draw_boat(c + Vector2(-r * 0.36, -r * 0.28), r * 0.52, col, hi)
				_draw_ferry(c + Vector2(r * 0.34, r * 0.30), r * 0.54, hi, col)
			&"junction":
				_draw_traffic_light(c + Vector2(-r * 0.42, 0.0), r * 0.58, col, hi)
				_draw_roundabout(c + Vector2(r * 0.40, 0.0), r * 0.54, hi, col)
			&"highway_ferry":
				_draw_highway(c + Vector2(0.0, -r * 0.34), r * 0.62, col, hi)
				_draw_ferry(c + Vector2(0.0, r * 0.40), r * 0.56, hi, col)
			&"road_highway":
				_draw_highway(c + Vector2(0.0, -r * 0.26), r * 0.68, col, hi)
				_draw_single_road_strip(c + Vector2(0.0, r * 0.48), r * 0.78, Color("#f3c86b") if not dimmed else col, hi)
			&"error":
				draw_arc(c, r * 0.82, 0.0, TAU, 32, COLOR_ERROR, maxf(2.0, s * 0.06), true)
				var d := r * 0.38
				draw_line(c + Vector2(-d, -d), c + Vector2(d, d), COLOR_ERROR, maxf(2.0, s * 0.07), true)
				draw_line(c + Vector2(d, -d), c + Vector2(-d, d), COLOR_ERROR, maxf(2.0, s * 0.07), true)
			_:
				_draw_road(c, r, col, hi)

	func _draw_road(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var w := r * 1.45
		var h := r * 0.34
		var lw := maxf(1.5, r * 0.09)
		for i in range(3):
			var oy := (float(i) - 1.0) * r * 0.44
			var rect := Rect2(c + Vector2(-w * 0.5, oy - h * 0.5), Vector2(w, h))
			var alpha := 0.45 + 0.275 * float(2 - i)
			draw_rect(rect, Color(col, alpha))
		draw_line(c + Vector2(-w * 0.34, -r * 0.44), c + Vector2(-w * 0.06, -r * 0.44), Color("#0c1520"), lw, true)
		draw_line(c + Vector2(w * 0.08, -r * 0.44), c + Vector2(w * 0.34, -r * 0.44), Color("#0c1520"), lw, true)
		draw_rect(Rect2(c + Vector2(-w * 0.5, -r * 0.44 - h * 0.5), Vector2(w, h)), hi, false, 1.0)

	func _draw_single_road_strip(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var w := r * 1.65
		var h := r * 0.34
		var lw := maxf(1.5, r * 0.10)
		var rect := Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
		draw_rect(rect, col)
		draw_rect(rect, hi, false, 1.0)
		draw_line(c + Vector2(-w * 0.34, 0.0), c + Vector2(-w * 0.08, 0.0), Color("#0c1520"), lw, true)
		draw_line(c + Vector2(w * 0.08, 0.0), c + Vector2(w * 0.34, 0.0), Color("#0c1520"), lw, true)

	func _draw_truck(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var body := Rect2(c + Vector2(-r * 0.82, -r * 0.42), Vector2(r * 1.08, r * 0.78))
		var cab := Rect2(c + Vector2(r * 0.28, -r * 0.18), Vector2(r * 0.54, r * 0.54))
		draw_rect(body, col)
		draw_rect(cab, hi)
		draw_circle(c + Vector2(-r * 0.42, r * 0.44), r * 0.20, hi)
		draw_circle(c + Vector2(r * 0.46, r * 0.44), r * 0.20, hi)

	func _draw_boat(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var hull := PackedVector2Array([
			c + Vector2(-r * 0.85, r * 0.04),
			c + Vector2(r * 0.88, r * 0.04),
			c + Vector2(r * 0.56, r * 0.46),
			c + Vector2(-r * 0.62, r * 0.46),
		])
		draw_colored_polygon(hull, col)
		draw_rect(Rect2(c + Vector2(-r * 0.36, -r * 0.44), Vector2(r * 0.62, r * 0.44)), hi)
		var lw := maxf(1.5, r * 0.10)
		draw_line(c + Vector2(-r * 0.80, r * 0.68), c + Vector2(r * 0.80, r * 0.68), Color(col, 0.7), lw, true)

	func _draw_upgrade_chevron(c: Vector2, r: float, hi: Color) -> void:
		var lw := maxf(2.0, r * 0.28)
		draw_circle(c, r * 0.92, Color("#0c1520"))
		draw_arc(c, r * 0.92, 0.0, TAU, 24, hi, maxf(1.4, r * 0.16), true)
		var pts := PackedVector2Array([
			c + Vector2(-r * 0.44, r * 0.18),
			c + Vector2(0.0, -r * 0.34),
			c + Vector2(r * 0.44, r * 0.18),
		])
		draw_polyline(pts, hi, lw, true)

	func _draw_traffic_light(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var w := r * 0.72
		var h := r * 1.56
		var box := Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
		draw_rect(box, Color("#0c1520"))
		draw_rect(box, hi, false, maxf(1.6, r * 0.10))
		var lr := r * 0.17
		draw_circle(c + Vector2(0.0, -r * 0.44), lr, Color("#ff6b6b") if not dimmed else col)
		draw_circle(c, lr, Color("#ffd23f") if not dimmed else col)
		draw_circle(c + Vector2(0.0, r * 0.44), lr, col)

	func _draw_roundabout(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var lw := maxf(2.0, r * 0.18)
		draw_arc(c, r * 0.68, 0.0, TAU, 32, col, lw, true)
		draw_circle(c, r * 0.24, hi)
		var arrow := PackedVector2Array([
			c + Vector2(0.0, -r * 0.92),
			c + Vector2(r * 0.30, -r * 0.68),
			c + Vector2(0.0, -r * 0.44),
		])
		draw_colored_polygon(arrow, hi)

	func _draw_highway(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var lw := maxf(2.2, r * 0.20)
		var pts := PackedVector2Array()
		for i in range(11):
			var t := float(i) / 10.0
			var x := lerpf(-r * 0.88, r * 0.88, t)
			var y := r * 0.30 - sin(t * PI) * r * 0.74
			pts.append(c + Vector2(x, y))
		draw_polyline(pts, col, lw, true)
		var pillar_w := maxf(1.8, r * 0.13)
		draw_line(c + Vector2(-r * 0.42, -r * 0.02), c + Vector2(-r * 0.42, r * 0.62), hi, pillar_w, true)
		draw_line(c + Vector2(r * 0.42, -r * 0.02), c + Vector2(r * 0.42, r * 0.62), hi, pillar_w, true)

	func _draw_ferry(c: Vector2, r: float, col: Color, hi: Color) -> void:
		var lw := maxf(1.8, r * 0.13)
		draw_line(c + Vector2(-r * 0.82, r * 0.08), c + Vector2(r * 0.82, r * 0.08), hi, lw * 1.15, true)
		draw_line(c + Vector2(-r * 0.46, -r * 0.46), c + Vector2(-r * 0.46, r * 0.22), col, lw * 1.2, true)
		draw_line(c + Vector2(r * 0.46, -r * 0.46), c + Vector2(r * 0.46, r * 0.22), col, lw * 1.2, true)
		draw_line(c + Vector2(-r * 0.46, -r * 0.34), c + Vector2(0.0, -r * 0.02), col, lw * 0.85, true)
		draw_line(c + Vector2(r * 0.46, -r * 0.34), c + Vector2(0.0, -r * 0.02), col, lw * 0.85, true)
		draw_line(c + Vector2(-r * 0.74, r * 0.46), c + Vector2(r * 0.74, r * 0.46), Color(col, 0.8), lw, true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	Style.full(self)
	_build_shell()
	resized.connect(_update_responsive_layout)
	visibility_changed.connect(_on_visibility_changed)
	_update_responsive_layout()


func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.name = "BackdropDim"
	dim.color = COLOR_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_backdrop_gui_input)
	add_child(dim)
	Style.full(dim)

	_margin = MarginContainer.new()
	_margin.name = "DraftMargin"
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	Style.full(_margin)

	var center := CenterContainer.new()
	center.name = "DraftCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(center)

	_root_vbox = VBoxContainer.new()
	_root_vbox.name = "DraftRoot"
	_root_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_root_vbox.add_theme_constant_override("separation", 24)
	_root_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_root_vbox)

	var header := VBoxContainer.new()
	header.name = "Header"
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_vbox.add_child(header)

	_eyebrow_label = Label.new()
	_eyebrow_label.text = "C H I   V I Ệ N   Đ Ợ T   M Ớ I"
	_eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow_label.add_theme_font_override("font", FONT_BOLD)
	_eyebrow_label.add_theme_font_size_override("font_size", 15)
	_eyebrow_label.add_theme_color_override("font_color", COLOR_CYAN)
	_eyebrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_eyebrow_label)

	_title_label = Label.new()
	_title_label.text = "CHỌN 1 THẺ NÂNG CẤP"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", FONT_BOLD)
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", COLOR_INK)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title_label)

	_error_banner = PanelContainer.new()
	_error_banner.name = "ErrorBanner"
	_error_banner.visible = false
	_error_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var err_box := Style.rounded(COLOR_ERROR_BG, COLOR_ERROR, 10, 1)
	err_box.content_margin_left = 18
	err_box.content_margin_right = 18
	err_box.content_margin_top = 10
	err_box.content_margin_bottom = 10
	_error_banner.add_theme_stylebox_override("panel", err_box)
	_root_vbox.add_child(_error_banner)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_font_size_override("font_size", 16)
	_error_label.add_theme_color_override("font_color", COLOR_INK)
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_banner.add_child(_error_label)

	_cards_grid = GridContainer.new()
	_cards_grid.name = "CardsGrid"
	_cards_grid.columns = EXPECTED_CARD_COUNT
	_cards_grid.add_theme_constant_override("h_separation", 24)
	_cards_grid.add_theme_constant_override("v_separation", 20)
	_cards_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_vbox.add_child(_cards_grid)

	_footer_label = Label.new()
	_footer_label.text = "Chọn 1 thẻ duy nhất để nhận toàn bộ gói và bắt đầu đợt tiếp theo"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.add_theme_font_size_override("font_size", 15)
	_footer_label.add_theme_color_override("font_color", COLOR_MUTED)
	_footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_vbox.add_child(_footer_label)


func set_backend_hooks(get_offers_fn: Callable, choose_card_fn: Callable) -> void:
	_get_offers_fn = get_offers_fn
	_choose_card_fn = choose_card_fn


func sync_from_backend() -> bool:
	var offers: Array = []
	if _get_offers_fn.is_valid():
		var raw = _get_offers_fn.call()
		if raw is Array:
			offers = raw
	elif GameManager.has_method("get_card_offers"):
		var raw = GameManager.call("get_card_offers")
		if raw is Array:
			offers = raw
	else:
		_last_errors = PackedStringArray(["Backend chưa cung cấp GameManager.get_card_offers()."])
		_set_error(_last_errors[0])
		_clear_cards()
		return false
	return set_offers(offers)


func set_offers(offers: Array) -> bool:
	_offers = offers.duplicate(true)
	_submitting = false
	_selected_card_id = &""
	_error_message = ""
	_last_errors = PackedStringArray()
	_clear_cards()

	var errors: PackedStringArray = PackedStringArray()
	if _offers.is_empty():
		errors.append("Không có dữ liệu thẻ từ hệ thống (0/%d thẻ)." % EXPECTED_CARD_COUNT)
	elif _offers.size() != EXPECTED_CARD_COUNT:
		errors.append("Số lượng thẻ không khớp quy ước (%d/%d thẻ)." % [_offers.size(), EXPECTED_CARD_COUNT])

	var seen_ids := {}
	for i in range(_offers.size()):
		var validation := _validate_offer(_offers[i], i, seen_ids)
		if not validation.ok:
			errors.append(String(validation.error))
		_create_card_node(validation)

	_last_errors = errors
	if not errors.is_empty():
		var combined := " | ".join(errors)
		push_error("RewardPopup: " + combined)
		_set_error(combined)
	else:
		_set_error("")

	_wire_focus_neighbors()
	_update_responsive_layout()
	_focus_first_selectable()
	if visible and not _syncing_visibility:
		_play_pop_in.call_deferred()
	return errors.is_empty()


func get_rendered_offers() -> Array:
	return _offers.duplicate(true)


func get_card_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for entry in _card_entries:
		out.append(entry.button)
	return out


func get_error_message() -> String:
	return _error_message


func get_last_errors() -> PackedStringArray:
	return _last_errors.duplicate()


func is_locked() -> bool:
	return _submitting or _selected_card_id != &""


func is_selection_locked() -> bool:
	return is_locked()


func select_card(card_id: StringName) -> bool:
	for i in range(_card_entries.size()):
		if _card_entries[i].id == card_id:
			var before := is_locked()
			_on_card_pressed(i)
			return (not before) and _selected_card_id == card_id
	return false


func _validate_offer(raw: Variant, index: int, seen_ids: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"error": "",
		"id": &"",
		"title": "",
		"icon_key": &"",
		"rewards": [],
		"disabled": false,
		"disabled_reason": "",
	}
	if typeof(raw) != TYPE_DICTIONARY:
		result.error = "Thẻ #%d không phải Dictionary." % (index + 1)
		return result
	var offer: Dictionary = raw
	var id_str := String(offer.get("id", "")).strip_edges()
	if id_str.is_empty():
		result.error = "Thẻ #%d thiếu id." % (index + 1)
		return result
	var card_id := StringName(id_str)
	if seen_ids.has(card_id):
		result.error = "Thẻ #%d trùng id '%s'." % [index + 1, id_str]
		return result
	seen_ids[card_id] = true

	var title := String(offer.get("title", "")).strip_edges()
	if title.is_empty():
		result.error = "Thẻ '%s' thiếu tiêu đề." % id_str
		return result

	if not offer.has("icon_key") or String(offer.get("icon_key", "")).strip_edges().is_empty():
		result.error = "Thẻ '%s' thiếu icon_key." % id_str
		return result

	var raw_rewards = offer.get("rewards", null)
	if not (raw_rewards is Array) or (raw_rewards as Array).is_empty():
		result.error = "Thẻ '%s' thiếu danh sách phần thưởng." % id_str
		return result

	var parsed_rewards: Array[Dictionary] = []
	var has_maxed_upgrade := false
	for r_idx in range((raw_rewards as Array).size()):
		var item = raw_rewards[r_idx]
		if typeof(item) != TYPE_DICTIONARY:
			result.error = "Thẻ '%s' có phần thưởng #%d sai định dạng." % [id_str, r_idx + 1]
			return result
		var d: Dictionary = item
		if not d.has("reward_id") or not d.has("amount"):
			result.error = "Thẻ '%s' thiếu reward_id hoặc amount." % id_str
			return result
		var raw_rid = d.get("reward_id")
		var raw_amt = d.get("amount")
		if not _is_whole_number(raw_rid) or not _is_whole_number(raw_amt):
			result.error = "Thẻ '%s' có reward_id/amount không phải số nguyên." % id_str
			return result
		var reward_id := int(raw_rid)
		var amount := int(raw_amt)
		if not REWARD_META.has(reward_id):
			result.error = "Thẻ '%s' chứa reward_id không hợp lệ (%d)." % [id_str, reward_id]
			return result
		if amount <= 0:
			result.error = "Thẻ '%s' có số lượng không hợp lệ (%d)." % [id_str, amount]
			return result
		var item_maxed := bool(d.get("maxed", false)) or bool(d.get("disabled", false)) or _is_upgrade_already_maxed(reward_id)
		if item_maxed:
			has_maxed_upgrade = true
		parsed_rewards.append({
			"reward_id": reward_id,
			"amount": amount,
			"maxed": item_maxed,
		})

	var icon_str := String(offer.get("icon_key", id_str)).strip_edges()
	var icon_key := StringName(icon_str) if not icon_str.is_empty() else card_id
	var disabled_flag := bool(offer.get("disabled", false)) or bool(offer.get("maxed", false)) or (offer.has("available") and not bool(offer.get("available", true)))
	var disabled_reason := String(offer.get("disabled_reason", "")).strip_edges()
	if has_maxed_upgrade:
		disabled_flag = true
		if disabled_reason.is_empty():
			disabled_reason = "ĐÃ TỐI ĐA"
	elif disabled_flag and disabled_reason.is_empty():
		disabled_reason = "KHÔNG KHẢ DỤNG"

	result.ok = true
	result.id = card_id
	result.title = title
	result.icon_key = icon_key
	result.rewards = parsed_rewards
	result.disabled = disabled_flag
	result.disabled_reason = disabled_reason
	return result


func _is_whole_number(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t == TYPE_FLOAT:
		var f := float(v)
		return is_finite(f) and is_equal_approx(f, roundf(f))
	return false


func _is_upgrade_already_maxed(reward_id: int) -> bool:
	if reward_id == REWARD_UPGRADE_TRUCK_CAP:
		return int(GameManager.get("truck_capacity")) >= Config.CAPACITY_UPGRADED
	if reward_id == REWARD_UPGRADE_BOAT_CAP:
		return int(GameManager.get("boat_capacity")) >= Config.CAPACITY_UPGRADED
	return false


func _resolve_card_visual(icon_key: StringName, rewards: Array) -> Dictionary:
	if TEMPLATE_STYLE.has(icon_key):
		return TEMPLATE_STYLE[icon_key]
	if not rewards.is_empty():
		var rid := int(rewards[0].get("reward_id", REWARD_MORE_EDGES))
		if REWARD_META.has(rid):
			var meta: Dictionary = REWARD_META[rid]
			return {"icon": meta.icon, "accent": meta.accent}
	return {"icon": &"road", "accent": COLOR_CYAN}


func _create_card_node(data: Dictionary) -> void:
	var is_valid: bool = bool(data.ok)
	var is_disabled: bool = (not is_valid) or bool(data.disabled)
	var visual := _resolve_card_visual(data.icon_key, data.rewards) if is_valid else {"icon": &"error", "accent": COLOR_ERROR}
	var accent: Color = visual.accent

	var card_slot := PanelContainer.new()
	card_slot.name = "CardSlot_%s" % (String(data.id) if is_valid else str(_card_entries.size()))
	card_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card_slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card := Button.new()
	card.name = "Card_%s" % (String(data.id) if is_valid else str(_card_entries.size()))
	card.focus_mode = Control.FOCUS_NONE if is_disabled else Control.FOCUS_ALL
	card.disabled = is_disabled
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if is_disabled else Control.CURSOR_POINTING_HAND
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.clip_contents = false

	_apply_card_styleboxes(card, accent, false, is_disabled)
	card_slot.add_child(card)

	var pad := MarginContainer.new()
	pad.name = "CardPad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 20)
	card_slot.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 14)
	pad.add_child(vbox)

	# Khung biểu tượng đầu thẻ
	var emblem_center := CenterContainer.new()
	emblem_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(emblem_center)

	var emblem_bg := PanelContainer.new()
	emblem_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem_bg.custom_minimum_size = Vector2(88, 88)
	var emblem_box := Style.rounded(
		Color(accent.r, accent.g, accent.b, 0.14 if not is_disabled else 0.06),
		Color(accent.r, accent.g, accent.b, 0.55 if not is_disabled else 0.22),
		20,
		2
	)
	emblem_box.shadow_size = 0
	emblem_bg.add_theme_stylebox_override("panel", emblem_box)
	emblem_center.add_child(emblem_bg)

	var emblem := CardEmblem.new()
	emblem.icon_type = visual.icon
	emblem.accent = accent
	emblem.dimmed = is_disabled
	emblem.custom_minimum_size = Vector2(64, 64)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem_bg.add_child(emblem)

	# Tên ngắn của thẻ
	var title_lbl := Label.new()
	title_lbl.text = String(data.title) if is_valid else "THẺ LỖI DỮ LIỆU"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_override("font", FONT_BOLD)
	title_lbl.add_theme_font_size_override("font_size", 21)
	title_lbl.add_theme_color_override("font_color", COLOR_INK if not is_disabled else (COLOR_ERROR if not is_valid else COLOR_MUTED))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	# Danh sách phần thưởng trong gói (hỗ trợ 1 hoặc nhiều thành phần)
	var rewards_box := PanelContainer.new()
	rewards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rewards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := Style.rounded(COLOR_INNER_BG, Color(accent, 0.22 if not is_disabled else 0.12), 12, 1)
	inner_style.content_margin_left = 12
	inner_style.content_margin_right = 12
	inner_style.content_margin_top = 12
	inner_style.content_margin_bottom = 12
	inner_style.shadow_size = 0
	rewards_box.add_theme_stylebox_override("panel", inner_style)
	vbox.add_child(rewards_box)

	var rewards_list := VBoxContainer.new()
	rewards_list.name = "RewardRows"
	rewards_list.alignment = BoxContainer.ALIGNMENT_CENTER
	rewards_list.add_theme_constant_override("separation", 10)
	rewards_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rewards_box.add_child(rewards_list)

	var row_refs: Array[Dictionary] = []
	if is_valid:
		for item in data.rewards:
			var built := _build_reward_row(item, is_disabled)
			rewards_list.add_child(built.row)
			row_refs.append(built)
	else:
		var err_lbl := Label.new()
		err_lbl.text = String(data.error)
		err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err_lbl.add_theme_font_size_override("font_size", 14)
		err_lbl.add_theme_color_override("font_color", COLOR_ERROR)
		err_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rewards_list.add_child(err_lbl)

	# Thanh trạng thái/hành động đáy thẻ
	var cta_pill := PanelContainer.new()
	cta_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cta_pill.custom_minimum_size = Vector2(0, 38)
	var cta_label := Label.new()
	cta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cta_label.add_theme_font_override("font", FONT_BOLD)
	cta_label.add_theme_font_size_override("font_size", 15)
	cta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cta_pill.add_child(cta_label)
	vbox.add_child(cta_pill)

	if not is_valid:
		_style_cta(cta_pill, cta_label, "KHÔNG HỢP LỆ", Color(0.28, 0.08, 0.10, 0.8), COLOR_ERROR, COLOR_ERROR)
	elif is_disabled:
		_style_cta(cta_pill, cta_label, String(data.disabled_reason), Color("#111b26"), COLOR_CARD_DISABLED_BORDER, COLOR_MUTED)
	else:
		_style_cta(cta_pill, cta_label, "CHỌN", Color(accent.r, accent.g, accent.b, 0.16), Color(accent, 0.55), COLOR_INK)

	var entry := {
		"slot": card_slot,
		"button": card,
		"pad": pad,
		"emblem_bg": emblem_bg,
		"emblem": emblem,
		"title_lbl": title_lbl,
		"vbox": vbox,
		"rewards_list": rewards_list,
		"row_refs": row_refs,
		"id": data.id,
		"valid": is_valid,
		"disabled": is_disabled,
		"disabled_reason": String(data.disabled_reason),
		"accent": accent,
		"cta_pill": cta_pill,
		"cta_label": cta_label,
		"hover_tween": null,
	}
	var entry_idx := _card_entries.size()
	_card_entries.append(entry)

	card.pressed.connect(_on_card_pressed.bind(entry_idx))
	card.mouse_entered.connect(_on_card_mouse_entered.bind(entry_idx))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(entry_idx))
	card.focus_entered.connect(_on_card_hover.bind(entry_idx, true))
	card.focus_exited.connect(_on_card_hover.bind(entry_idx, false))
	_cards_grid.add_child(card_slot)


func _build_reward_row(item: Dictionary, card_disabled: bool) -> Dictionary:
	var rid := int(item.get("reward_id", -1))
	var amount := int(item.get("amount", 0))
	var item_maxed := bool(item.get("maxed", false))
	var meta: Dictionary = REWARD_META.get(rid, {"label": "Vật phẩm", "accent": COLOR_CYAN, "icon": &"road"})
	var row_accent: Color = meta.accent

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mini_icon := CardEmblem.new()
	mini_icon.icon_type = meta.icon
	mini_icon.accent = row_accent
	mini_icon.dimmed = card_disabled or item_maxed
	mini_icon.custom_minimum_size = Vector2(26, 26)
	mini_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mini_icon)

	var name_lbl := Label.new()
	name_lbl.text = String(meta.label)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", COLOR_INK if not (card_disabled or item_maxed) else COLOR_MUTED)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_bg := Color(row_accent.r, row_accent.g, row_accent.b, 0.20 if not (card_disabled or item_maxed) else 0.08)
	var badge_style := Style.rounded(badge_bg, Color(row_accent, 0.55 if not (card_disabled or item_maxed) else 0.2), 8, 1)
	badge_style.content_margin_left = 10
	badge_style.content_margin_right = 10
	badge_style.content_margin_top = 3
	badge_style.content_margin_bottom = 3
	badge_style.shadow_size = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	row.add_child(badge)

	var qty_lbl := Label.new()
	if item_maxed:
		qty_lbl.text = "MAX"
	elif bool(meta.get("upgrade", false)):
		qty_lbl.text = "×%d" % Config.CAPACITY_UPGRADED if amount == 1 else "+%d" % amount
	else:
		qty_lbl.text = "+%d" % amount
	qty_lbl.add_theme_font_override("font", FONT_BOLD)
	qty_lbl.add_theme_font_size_override("font_size", 16)
	qty_lbl.add_theme_color_override("font_color", row_accent if not (card_disabled or item_maxed) else COLOR_MUTED)
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(qty_lbl)

	return {
		"row": row,
		"mini_icon": mini_icon,
		"name_lbl": name_lbl,
		"qty_lbl": qty_lbl,
	}


func _style_cta(pill: PanelContainer, lbl: Label, caption: String, bg: Color, border: Color, fg: Color) -> void:
	lbl.text = caption
	lbl.add_theme_color_override("font_color", fg)
	var s := Style.rounded(bg, border, 10, 1)
	s.shadow_size = 0
	pill.add_theme_stylebox_override("panel", s)


func _apply_card_styleboxes(card: Button, accent: Color, selected: bool, is_disabled: bool) -> void:
	if selected:
		var sel := Style.rounded(COLOR_CARD_SELECTED, COLOR_GOLD, 16, 3)
		card.add_theme_stylebox_override("normal", sel)
		card.add_theme_stylebox_override("hover", sel)
		card.add_theme_stylebox_override("pressed", sel)
		card.add_theme_stylebox_override("focus", sel)
		card.add_theme_stylebox_override("disabled", sel)
		card.modulate = Color.WHITE
		return
	card.add_theme_stylebox_override("normal", Style.rounded(COLOR_CARD_BG, COLOR_CARD_BORDER, 16, 2))
	card.add_theme_stylebox_override("hover", Style.rounded(COLOR_CARD_HOVER, accent, 16, 2))
	card.add_theme_stylebox_override("pressed", Style.rounded(COLOR_CARD_PRESSED, accent, 16, 2))
	card.add_theme_stylebox_override("focus", Style.rounded(COLOR_CARD_HOVER, COLOR_GOLD, 16, 3))
	card.add_theme_stylebox_override("disabled", Style.rounded(COLOR_CARD_DISABLED, COLOR_CARD_DISABLED_BORDER, 16, 1))
	card.modulate = Color(1.0, 1.0, 1.0, 0.56 if is_disabled else 1.0)


func _kill_entry_tween(entry: Dictionary) -> void:
	var prev_tw = entry.get("hover_tween")
	if prev_tw is Tween and (prev_tw as Tween).is_valid():
		(prev_tw as Tween).kill()
	entry["hover_tween"] = null


func _on_card_mouse_entered(entry_idx: int) -> void:
	if entry_idx < 0 or entry_idx >= _card_entries.size():
		return
	var card: Button = _card_entries[entry_idx].button
	if card.disabled or is_locked():
		return
	# Đồng bộ focus bàn phím theo con trỏ chuột để không bao giờ sáng 2 thẻ cùng lúc.
	if card.has_focus():
		_on_card_hover(entry_idx, true)
	else:
		card.grab_focus()


func _on_card_mouse_exited(entry_idx: int) -> void:
	if entry_idx < 0 or entry_idx >= _card_entries.size():
		return
	var card: Button = _card_entries[entry_idx].button
	if card.disabled or is_locked():
		return
	if not card.has_focus():
		_on_card_hover(entry_idx, false)


func _on_card_hover(entry_idx: int, hovered: bool) -> void:
	if entry_idx < 0 or entry_idx >= _card_entries.size():
		return
	var entry: Dictionary = _card_entries[entry_idx]
	var card: Button = entry.button
	var slot: Control = entry.slot
	if card.disabled or is_locked():
		return
	if hovered:
		AudioManager.play_sfx(&"ui_hover")
		_style_cta(entry.cta_pill, entry.cta_label, "CHỌN", entry.accent, entry.accent, Color("#0c1520"))
	else:
		_style_cta(entry.cta_pill, entry.cta_label, "CHỌN", Color(entry.accent.r, entry.accent.g, entry.accent.b, 0.16), Color(entry.accent, 0.55), COLOR_INK)
	_kill_entry_tween(entry)
	slot.pivot_offset = slot.size * 0.5
	var tw := slot.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(slot, "scale", Vector2(1.025, 1.025) if hovered else Vector2.ONE, 0.09).set_trans(Tween.TRANS_SINE)
	entry["hover_tween"] = tw


func _on_card_pressed(entry_idx: int) -> void:
	if is_locked() or entry_idx < 0 or entry_idx >= _card_entries.size():
		return
	var entry: Dictionary = _card_entries[entry_idx]
	if not bool(entry.valid) or bool(entry.disabled):
		return

	var card_id: StringName = entry.id
	_submitting = true
	_selected_card_id = card_id
	_set_error("")
	AudioManager.play_sfx(&"ui_click")
	_lock_all_cards(entry_idx)

	var accepted := _submit_choice_to_backend(card_id)
	if accepted:
		card_selected.emit(card_id)
		card_chosen.emit(card_id)
	else:
		# Backend từ chối: mở khóa lại các thẻ hợp lệ và báo lỗi rõ ràng.
		_submitting = false
		_selected_card_id = &""
		_unlock_valid_cards()
		_set_error("Không thể chọn thẻ '%s'. Hãy thử thẻ khác." % String(card_id))


func _submit_choice_to_backend(card_id: StringName) -> bool:
	if _choose_card_fn.is_valid():
		return bool(_choose_card_fn.call(card_id))
	if GameManager.has_method("choose_card"):
		return bool(GameManager.call("choose_card", card_id))
	push_error("RewardPopup: Backend chưa cung cấp GameManager.choose_card(card_id).")
	return false


func _lock_all_cards(selected_idx: int) -> void:
	for i in range(_card_entries.size()):
		var entry: Dictionary = _card_entries[i]
		_kill_entry_tween(entry)
		var card: Button = entry.button
		var slot: Control = entry.slot
		var is_sel := (i == selected_idx)
		card.disabled = true
		slot.scale = Vector2.ONE
		_apply_card_styleboxes(card, entry.accent, is_sel, not is_sel)
		slot.modulate = Color.WHITE if is_sel else Color(1.0, 1.0, 1.0, 0.52)
		if is_sel:
			_style_cta(entry.cta_pill, entry.cta_label, "ĐÃ CHỌN", COLOR_GOLD, COLOR_GOLD, Color("#0c1520"))
		elif not bool(entry.valid):
			_style_cta(entry.cta_pill, entry.cta_label, "KHÔNG HỢP LỆ", Color(0.28, 0.08, 0.10, 0.8), COLOR_ERROR, COLOR_ERROR)
		elif bool(entry.disabled):
			_style_cta(entry.cta_pill, entry.cta_label, String(entry.disabled_reason), Color("#111b26"), COLOR_CARD_DISABLED_BORDER, COLOR_MUTED)
		else:
			_style_cta(entry.cta_pill, entry.cta_label, "CHỌN", Color("#111b26"), COLOR_CARD_DISABLED_BORDER, COLOR_MUTED)


func _unlock_valid_cards() -> void:
	for entry in _card_entries:
		_kill_entry_tween(entry)
		var card: Button = entry.button
		var slot: Control = entry.slot
		var is_disabled := (not bool(entry.valid)) or bool(entry.disabled)
		card.disabled = is_disabled
		slot.scale = Vector2.ONE
		_apply_card_styleboxes(card, entry.accent, false, is_disabled)
		slot.modulate = Color(1.0, 1.0, 1.0, 0.56 if is_disabled else 1.0)
		if not is_disabled:
			_style_cta(entry.cta_pill, entry.cta_label, "CHỌN", Color(entry.accent.r, entry.accent.g, entry.accent.b, 0.16), Color(entry.accent, 0.55), COLOR_INK)


func _clear_cards() -> void:
	_card_entries.clear()
	if _cards_grid == null:
		return
	for child in _cards_grid.get_children():
		_cards_grid.remove_child(child)
		child.queue_free()


func _set_error(msg: String) -> void:
	_error_message = msg
	if _error_banner != null and _error_label != null:
		_error_label.text = msg
		_error_banner.visible = not msg.is_empty()


func _wire_focus_neighbors() -> void:
	var focusable: Array[Button] = []
	for entry in _card_entries:
		var card: Button = entry.button
		if not card.disabled:
			focusable.append(card)
	for i in range(focusable.size()):
		var prev_card := focusable[(i - 1 + focusable.size()) % focusable.size()]
		var next_card := focusable[(i + 1) % focusable.size()]
		focusable[i].focus_neighbor_left = prev_card.get_path()
		focusable[i].focus_neighbor_right = next_card.get_path()


func _focus_first_selectable() -> void:
	for entry in _card_entries:
		var card: Button = entry.button
		if not card.disabled and card.is_inside_tree() and visible:
			card.grab_focus()
			return


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_focus_first_selectable()
		accept_event()


# Chặn phím tắt / con lăn lọt xuống bản đồ, EdgeDrawer hoặc GameManager khi đang mở màn chọn thẻ.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey or event is InputEventMouseButton:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _play_pop_in() -> void:
	if _root_vbox == null or not is_visible_in_tree():
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_root_vbox.pivot_offset = _root_vbox.size * 0.5
	_root_vbox.scale = Vector2(0.96, 0.96)
	_root_vbox.modulate.a = 0.0
	_pop_tween = create_tween()
	_pop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pop_tween.tween_property(_root_vbox, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.parallel().tween_property(_root_vbox, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_SINE)


func _on_visibility_changed() -> void:
	if visible:
		_syncing_visibility = true
		_update_responsive_layout()
		if _offers.is_empty():
			if _get_offers_fn.is_valid():
				var snap = _get_offers_fn.call()
				if snap is Array and not (snap as Array).is_empty():
					set_offers(snap)
			elif GameManager.has_method("get_card_offers"):
				var snap = GameManager.call("get_card_offers")
				if snap is Array and not (snap as Array).is_empty():
					set_offers(snap)
		_focus_first_selectable()
		_syncing_visibility = false
		_play_pop_in.call_deferred()


func _update_responsive_layout() -> void:
	if _margin == null or _cards_grid == null:
		return
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		var r := get_viewport_rect().size
		vp = r if r.x > 0.0 and r.y > 0.0 else Vector2(1920.0, 1200.0)

	var cols := EXPECTED_CARD_COUNT if vp.x >= 960.0 else 2
	_cards_grid.columns = cols

	# Hệ số tỷ lệ liên tục theo kích thước màn hình (chuẩn 1920×1200 -> 1.0, không bị chặn trần ở 2K/4K).
	var ui_scale := maxf(0.45, minf(vp.x / 1920.0, vp.y / 1200.0))
	if cols == 2:
		ui_scale = maxf(0.45, minf(vp.x / 1080.0, vp.y / 1320.0))

	var pad_x := maxi(16, int(roundf(vp.x * 0.048)))
	var pad_y := maxi(14, int(roundf(vp.y * 0.038)))
	_margin.add_theme_constant_override("margin_left", pad_x)
	_margin.add_theme_constant_override("margin_right", pad_x)
	_margin.add_theme_constant_override("margin_top", pad_y)
	_margin.add_theme_constant_override("margin_bottom", pad_y)
	_root_vbox.add_theme_constant_override("separation", maxi(10, int(roundf(22.0 * ui_scale))))

	var h_sep := maxi(10, int(roundf(vp.x * 0.014)))
	var v_sep := maxi(10, int(roundf(18.0 * ui_scale)))
	_cards_grid.add_theme_constant_override("h_separation", h_sep)
	_cards_grid.add_theme_constant_override("v_separation", v_sep)

	var avail_w := maxf(280.0, vp.x - float(pad_x * 2) - float(h_sep * (cols - 1)))
	var max_card_w := 385.0 * maxf(ui_scale, vp.x / 1920.0 * 0.92)
	var card_w := clampf(floorf(avail_w / float(cols)), 180.0 * ui_scale, max_card_w)
	var base_card_h := floorf(vp.y * (0.39 if cols == 4 else 0.31))

	var inner_pad := maxi(10, int(roundf(20.0 * ui_scale)))
	var emblem_outer := roundf(88.0 * ui_scale)
	var emblem_inner := roundf(64.0 * ui_scale)
	var card_title_fs := maxi(13, int(roundf(21.0 * ui_scale)))
	var row_fs := maxi(11, int(roundf(16.0 * ui_scale)))
	var cta_fs := maxi(11, int(roundf(15.0 * ui_scale)))
	var cta_h := maxf(26.0, roundf(38.0 * ui_scale))
	var mini_sz := maxf(18.0, roundf(26.0 * ui_scale))
	var vbox_sep := maxi(6, int(roundf(14.0 * ui_scale)))
	var row_sep := maxi(6, int(roundf(10.0 * ui_scale)))

	for entry in _card_entries:
		var slot: PanelContainer = entry.slot
		var card: Button = entry.button
		var pad: MarginContainer = entry.pad
		var emblem_bg: PanelContainer = entry.emblem_bg
		var emblem: Control = entry.emblem
		var title_lbl: Label = entry.title_lbl
		var vbox: VBoxContainer = entry.vbox
		var rewards_list: VBoxContainer = entry.rewards_list
		var cta_pill: PanelContainer = entry.cta_pill
		var cta_label: Label = entry.cta_label
		var row_refs: Array = entry.row_refs

		pad.add_theme_constant_override("margin_left", inner_pad)
		pad.add_theme_constant_override("margin_right", inner_pad)
		pad.add_theme_constant_override("margin_top", inner_pad)
		pad.add_theme_constant_override("margin_bottom", inner_pad)
		vbox.add_theme_constant_override("separation", vbox_sep)
		rewards_list.add_theme_constant_override("separation", row_sep)
		emblem_bg.custom_minimum_size = Vector2(emblem_outer, emblem_outer)
		emblem.custom_minimum_size = Vector2(emblem_inner, emblem_inner)
		title_lbl.add_theme_font_size_override("font_size", card_title_fs)
		cta_pill.custom_minimum_size = Vector2(0, cta_h)
		cta_label.add_theme_font_size_override("font_size", cta_fs)
		for rr in row_refs:
			(rr.mini_icon as Control).custom_minimum_size = Vector2(mini_sz, mini_sz)
			(rr.name_lbl as Label).add_theme_font_size_override("font_size", row_fs)
			(rr.qty_lbl as Label).add_theme_font_size_override("font_size", row_fs)
			(rr.row as HBoxContainer).add_theme_constant_override("separation", row_sep)

		slot.custom_minimum_size = Vector2(card_w, base_card_h)
		card.custom_minimum_size = Vector2(card_w, base_card_h)
		slot.modulate = Color(1.0, 1.0, 1.0, 0.56 if card.disabled and not is_locked() else 1.0)

	if _eyebrow_label != null:
		_eyebrow_label.add_theme_font_size_override("font_size", maxi(11, int(roundf(15.0 * ui_scale))))
	if _title_label != null:
		_title_label.add_theme_font_size_override("font_size", maxi(20, int(roundf(36.0 * ui_scale))))
	if _error_label != null:
		_error_label.add_theme_font_size_override("font_size", maxi(12, int(roundf(16.0 * ui_scale))))
	if _footer_label != null:
		_footer_label.add_theme_font_size_override("font_size", maxi(11, int(roundf(15.0 * ui_scale))))
		_footer_label.visible = vp.y >= 620.0

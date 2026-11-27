extends Node
## Bộ test tự động chuyên sâu cho phần việc Người E:
## - Cấu hình viewport 16:10 (1920×1200), map 16:9 chính giữa không méo, nền đệm #151e28.
## - Camera StageView: zoom hướng con trỏ (kể cả bước chạm trần 2×), không trôi khi quá trần,
##   tự căn tâm ở min zoom, khóa khi pause, thích ứng đổi độ phân giải, phối hợp vẽ đường & click SOS khi đang zoom.
## - Card Draft UI (RewardPopup): 4 thẻ, bundle nhiều reward, 8 template baseline, chặn double-click,
##   chỉ phát card_selected khi backend chấp nhận, mở khóa khi từ chối, bắt lỗi kiểu dữ liệu chặt chẽ,
##   không tràn nội dung ra ngoài viền thẻ ở 1920×1200 / 1280×720 / 900×700, chặn rò phím/chuột xuống map.
## - UIRoot: chịu được cả hai thứ tự tín hiệu (state->offers và offers->state), phủ dim kín toàn khung 16:10.

const StageViewScript := preload("res://game/stage_view.gd")
const EdgeDrawerScript := preload("res://graph/edge_drawer.gd")
const RewardPopupScene := preload("res://ui/reward_popup.tscn")
const UIRootScene := preload("res://ui/ui_root.tscn")
const FIXTURE_MAP := "res://data/map_01.json"

var _passed := 0
var _failed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	_test_viewport_settings()
	await _test_stage_view_camera_and_zoom()
	await _test_zoomed_road_drawing_and_sos_hit()
	await _test_card_draft_valid_and_lock()
	await _test_card_draft_validation_and_edge_cases()
	await _test_card_draft_no_inner_overflow_and_responsive()
	await _test_card_draft_input_isolation()
	await _test_ui_root_framing_and_signal_order()
	print("\nKết quả test Người E: %d đạt, %d trượt" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_viewport_settings() -> void:
	print("\n== 1. Cấu hình viewport 16:10 trong project.godot")
	var vw := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var vh := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var stretch_mode := String(ProjectSettings.get_setting("display/window/stretch/mode"))
	var stretch_aspect := String(ProjectSettings.get_setting("display/window/stretch/aspect"))
	var clear_col: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	_check(vw == 1920 and vh == 1200, "viewport mục tiêu là 1920×1200 (hiện tại %d×%d)" % [vw, vh])
	_check(stretch_mode == "canvas_items", "stretch mode là canvas_items (%s)" % stretch_mode)
	_check(stretch_aspect == "expand", "stretch aspect là expand để không kéo giãn map (%s)" % stretch_aspect)
	_check(clear_col.is_equal_approx(StageViewScript.BACKDROP_COLOR), "default_clear_color khớp màu nền đệm #151e28")


func _test_stage_view_camera_and_zoom() -> void:
	print("\n== 2. StageView: căn giữa map 16:9, nền đệm và zoom theo con trỏ ở 1920×1200")
	_check(is_equal_approx(StageViewScript.compute_fit_zoom(Vector2(1920, 1200)), 1.5),
			"fit_zoom ở 1920×1200 bằng 1.5 (map 1280×720 chiếm 1920×1080 giữa màn hình)")
	_check(is_equal_approx(StageViewScript.compute_fit_zoom(Vector2(1280, 720)), 1.0),
			"fit_zoom ở 1280×720 bằng 1.0")
	_check(is_equal_approx(StageViewScript.compute_fit_zoom(Vector2(1600, 1200)), 1.25),
			"fit_zoom ở 1600×1200 (4:3) bằng 1.25")
	_check(is_equal_approx(StageViewScript.compute_fit_zoom(Vector2(1440, 900)), 1.125),
			"fit_zoom ở 1440×900 (16:10 nhỏ) bằng 1.125")
	_check(is_equal_approx(StageViewScript.MIN_ZOOM_FACTOR, 1.0) and is_equal_approx(StageViewScript.MAX_ZOOM_FACTOR, 2.0),
			"giới hạn zoom prototype là 1×..2× mức fit-map")

	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(1920, 1200)
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub_vp)

	var sv: Node2D = StageViewScript.new()
	sv.only_in_round = false
	sub_vp.add_child(sv)
	await _frames(2)

	var backdrop := sv.get_node_or_null("Backdrop") as Node2D
	_check(backdrop != null and backdrop.z_index < -20,
			"có lớp nền đệm Backdrop nằm dưới Terrain (z_index=%d)" % (backdrop.z_index if backdrop != null else 0))

	var fit: float = sv.get_fit_zoom()
	_check(is_equal_approx(fit, 1.5), "SubViewport 1920×1200 có fit_zoom = 1.5 (%.3f)" % fit)
	_check(is_equal_approx(sv.camera.zoom.x, fit) and is_equal_approx(sv.camera.zoom.y, fit),
			"khởi tạo camera ở đúng mức min zoom không méo (%.3f, %.3f)" % [sv.camera.zoom.x, sv.camera.zoom.y])
	_check(sv.camera.position.is_equal_approx(StageViewScript.MAP_SIZE * 0.5),
			"khởi tạo camera nằm chính giữa bản đồ (%.1f, %.1f)" % [sv.camera.position.x, sv.camera.position.y])

	var vp_size := Vector2(1920.0, 1200.0)
	var cursor := vp_size * Vector2(0.62, 0.42)
	var world_before := StageViewScript.screen_to_world(cursor, sv.camera.position, sv.camera.zoom.x, vp_size)
	var zoomed: bool = sv.zoom_at_screen_pos(cursor, StageViewScript.ZOOM_STEP)
	var world_after := StageViewScript.screen_to_world(cursor, sv.camera.position, sv.camera.zoom.x, vp_size)
	_check(zoomed and sv.camera.zoom.x > fit and is_equal_approx(sv.camera.zoom.x, sv.camera.zoom.y),
			"phóng to tăng zoom đồng đều hai trục (%.3f -> %.3f)" % [fit, sv.camera.zoom.x])
	_check(world_before.distance_to(world_after) < 0.5,
			"điểm bản đồ dưới con trỏ được giữ nguyên khi phóng to ở 1920×1200 (lệch %.3f px)" % world_before.distance_to(world_after))

	# Kiểm tra bước phóng lẻ chạm đúng trần 2× (ví dụ từ 1.92× lên 2.0×): điểm dưới con trỏ vẫn không lệch.
	sv.apply({"center": [640, 360], "zoom": 1.92}, false)
	var near_cursor := vp_size * Vector2(0.56, 0.46)
	var pre_cap_world := StageViewScript.screen_to_world(near_cursor, sv.camera.position, sv.camera.zoom.x, vp_size)
	sv.zoom_at_screen_pos(near_cursor, StageViewScript.ZOOM_STEP)
	var post_cap_world := StageViewScript.screen_to_world(near_cursor, sv.camera.position, sv.camera.zoom.x, vp_size)
	_check(is_equal_approx(sv.camera.zoom.x, sv.get_max_zoom()) and pre_cap_world.distance_to(post_cap_world) < 0.5,
			"bước phóng chạm trần 2× vẫn giữ chính xác điểm dưới con trỏ (lệch %.3f px)" % pre_cap_world.distance_to(post_cap_world))

	# Đang ở max zoom mà tiếp tục lăn lên ở góc khác: camera.position không được trôi.
	var pos_at_max: Vector2 = sv.camera.position
	var extra_zoom: bool = sv.zoom_at_screen_pos(vp_size * Vector2(0.85, 0.2), StageViewScript.ZOOM_STEP)
	_check(not extra_zoom and sv.camera.position.is_equal_approx(pos_at_max),
			"lăn phóng tiếp khi đã đạt max zoom không làm trôi tâm camera")

	# Thu nhỏ quá mức -> chạm sàn đúng 1× fit_zoom và tự căn lại giữa bản đồ.
	for i in range(25):
		sv.zoom_at_screen_pos(cursor, 1.0 / StageViewScript.ZOOM_STEP)
	_check(is_equal_approx(sv.camera.zoom.x, sv.get_min_zoom()) and is_equal_approx(sv.camera.zoom.y, sv.get_min_zoom()),
			"zoom nhỏ nhất bị chặn đúng tại 1× fit-map (%.3f)" % sv.camera.zoom.x)
	_check(sv.camera.position.is_equal_approx(StageViewScript.MAP_SIZE * 0.5),
			"khi thu về min zoom, camera tự quay về tâm bản đồ (%.1f, %.1f)" % [sv.camera.position.x, sv.camera.position.y])

	# Đổi kích thước viewport sang 1280×720 rồi 1600×1000: camera tự thích ứng, không méo.
	sub_vp.size = Vector2i(1280, 720)
	await _frames(2)
	_check(is_equal_approx(sv.camera.zoom.x, 1.0) and is_equal_approx(sv.camera.zoom.y, 1.0),
			"khi đổi viewport sang 1280×720, min zoom cập nhật thành 1.0 đều 2 trục (%.3f)" % sv.camera.zoom.x)
	sub_vp.size = Vector2i(1600, 1000)
	await _frames(2)
	_check(is_equal_approx(sv.camera.zoom.x, 1.25) and is_equal_approx(sv.camera.zoom.y, 1.25),
			"khi đổi viewport sang 1600×1000 (16:10), min zoom cập nhật thành 1.25 đều 2 trục (%.3f)" % sv.camera.zoom.x)

	sub_vp.size = Vector2i(1920, 1200)
	await _frames(2)
	sv.apply({"center": [622, 245], "zoom": 1.8}, false)
	_check(is_equal_approx(sv.camera.zoom.x, 1.5 * 1.8) and is_equal_approx(sv.camera.zoom.y, 1.5 * 1.8),
			"apply(stage) nhân theo fit_zoom và giữ tỷ lệ 1:1 (%.3f)" % sv.camera.zoom.x)

	sub_vp.queue_free()
	await _frames(1)

	# Kiểm tra sự kiện con lăn chuột thật qua _unhandled_input trên viewport chính + chặn khi paused.
	var sv_root: Node2D = StageViewScript.new()
	sv_root.only_in_round = false
	add_child(sv_root)
	await _frames(2)

	var root_vp: Vector2 = sv_root.get_viewport_rect().size
	var root_cursor := root_vp * Vector2(0.60, 0.50)
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = get_viewport().get_final_transform() * root_cursor
	Input.parse_input_event(wheel_up)
	await _frames(2)
	var after_wheel: float = sv_root.camera.zoom.x
	_check(after_wheel > sv_root.get_min_zoom(), "con lăn chuột lên phóng to được qua _unhandled_input")

	get_tree().paused = true
	var wheel_paused := InputEventMouseButton.new()
	wheel_paused.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_paused.pressed = true
	wheel_paused.position = get_viewport().get_final_transform() * root_cursor
	Input.parse_input_event(wheel_paused)
	await _frames(2)
	_check(is_equal_approx(sv_root.camera.zoom.x, after_wheel), "khi game tạm dừng / mở draft, con lăn không làm đổi zoom")
	get_tree().paused = false

	sv_root.queue_free()
	await _frames(1)


func _test_zoomed_road_drawing_and_sos_hit() -> void:
	print("\n== 3. Tương tác vẽ đường và bong bóng SOS khi đang zoom lệch tâm ở 1920×1200")
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	await _frames(2)

	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(1920, 1200)
	sub_vp.handle_input_locally = true
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub_vp)

	var world := Node2D.new()
	sub_vp.add_child(world)

	var sv: Node2D = StageViewScript.new()
	sv.only_in_round = false
	world.add_child(sv)

	var drawer: Node2D = EdgeDrawerScript.new()
	drawer.only_in_round = false
	world.add_child(drawer)

	var ui_root: CanvasLayer = UIRootScene.instantiate()
	sub_vp.add_child(ui_root)
	ui_root.call("_show", "hud")
	await _frames(2)

	# Zoom 3 nấc vào vùng lệch tâm trước khi kéo vẽ đường.
	for i in range(3):
		sv.zoom_at_screen_pos(Vector2(1280, 760), StageViewScript.ZOOM_STEP)
	await _frames(2)

	var xf := sub_vp.get_canvas_transform()
	var p_from := xf * GraphManager.cell_center(Vector2i(15, 12))
	var p_to := xf * GraphManager.cell_center(Vector2i(17, 12))
	_push_subvp_mouse_btn(sub_vp, p_from, MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	_push_subvp_mouse_motion(sub_vp, p_to)
	await _frames(1)
	_push_subvp_mouse_btn(sub_vp, p_to, MOUSE_BUTTON_LEFT, false)
	await _frames(1)
	_check(GraphManager.road_at(Vector2i(15, 12)) != -1 and GraphManager.road_at(Vector2i(16, 12)) != -1 and GraphManager.road_at(Vector2i(17, 12)) != -1,
			"kéo chuột khi đang zoom lệch tâm ở 1920×1200 vẫn tô trúng chính xác các ô (15..17, 12)")

	# Sinh một SOS giả và kiểm tra bong bóng SOS bù scale đúng theo camera zoom + hit-test chuẩn.
	EventBus.sos_spawned.emit(9001, 3, Types.SupplyType.FOOD, 30.0)
	await _frames(2)
	var sos_layer := ui_root.get("sos") as Node2D
	var markers: Dictionary = sos_layer.get("markers")
	var marker: Node2D = markers.get(9001, null)
	var expected_scale: float = 1.0 / float(sv.camera.zoom.x)
	_check(marker != null and is_equal_approx(marker.scale.x, expected_scale) and is_equal_approx(marker.scale.y, expected_scale),
			"bong bóng SOS tự bù scale nghịch đảo theo camera zoom (%.3f)" % (marker.scale.x if marker != null else 0.0))
	if marker != null:
		var bubble_world_center: Vector2 = marker.position + Vector2(0, -54) * marker.scale
		_check(bool(marker.call("hit", bubble_world_center)) and not bool(marker.call("hit", marker.position)),
				"hit-test bong bóng SOS trúng tâm bong bóng và không chặn tâm tòa nhà khi đang zoom")
	EventBus.sos_failed.emit(9001)

	sub_vp.queue_free()
	await _frames(2)


func _test_card_draft_valid_and_lock() -> void:
	print("\n== 4. Card Draft UI: 4 thẻ, gói nhiều phần thưởng, khóa chọn trùng khi pause")
	var popup: Control = RewardPopupScene.instantiate()
	add_child(popup)
	await _frames(2)

	_check(popup.process_mode == Node.PROCESS_MODE_ALWAYS, "RewardPopup dùng PROCESS_MODE_ALWAYS")

	var offers_wave_1 := [
		{
			"id": &"road_supply",
			"title": "TIẾP TẾ ĐƯỜNG",
			"icon_key": &"road_supply",
			"rewards": [{"reward_id": 0, "amount": 20}],
		},
		{
			"id": &"boat_fleet_ferry",
			"title": "ĐỘI CA-NÔ & PHÀ",
			"icon_key": &"boat_fleet_ferry",
			"rewards": [{"reward_id": 2, "amount": 2}, {"reward_id": 8, "amount": 1}],
		},
		{
			"id": &"junction_kit",
			"title": "BỘ ĐIỀU TIẾT NGÃ TƯ",
			"icon_key": &"junction_kit",
			"rewards": [{"reward_id": 5, "amount": 1}, {"reward_id": 6, "amount": 1}],
		},
		{
			"id": &"highway_ferry",
			"title": "CAO TỐC & PHÀ",
			"icon_key": &"highway_ferry",
			"rewards": [{"reward_id": 7, "amount": 1}, {"reward_id": 8, "amount": 1}],
		},
	]

	var chosen_calls: Array[StringName] = []
	var selected_signals: Array[StringName] = []
	popup.connect("card_selected", func(cid: StringName) -> void: selected_signals.append(cid))
	popup.call("set_backend_hooks",
		func() -> Array: return offers_wave_1,
		func(cid: StringName) -> bool:
			chosen_calls.append(cid)
			return true
	)

	get_tree().paused = true
	var synced: bool = bool(popup.call("sync_from_backend"))
	await _frames(2)
	var buttons: Array[Button] = popup.call("get_card_buttons")
	_check(synced and popup.call("get_last_errors").is_empty(), "sync_from_backend() nạp hợp lệ 4 thẻ từ backend")
	_check(buttons.size() == 4, "hiển thị đúng 4 thẻ lựa chọn (%d)" % buttons.size())
	_check(buttons.all(func(b: Button) -> bool: return b.visible and not b.disabled), "cả 4 thẻ hợp lệ đều bật và sẵn sàng chọn")
	_check(_find_button_by_text(popup, "XONG") == null, "không còn nút XONG để bỏ qua card draft")

	var bundle_rows := buttons[1].get_parent().find_child("RewardRows", true, false)
	_check(bundle_rows != null and bundle_rows.get_child_count() == 2,
			"thẻ gói boat_fleet_ferry hiển thị đủ 2 dòng phần thưởng")

	buttons[1].pressed.emit()
	buttons[1].pressed.emit()
	buttons[2].pressed.emit()
	await _frames(1)
	_check(chosen_calls.size() == 1 and chosen_calls[0] == &"boat_fleet_ferry",
			"chặn chọn trùng/double-click: backend chỉ nhận đúng 1 lựa chọn (%s)" % str(chosen_calls))
	_check(selected_signals == [&"boat_fleet_ferry"], "card_selected phát đúng 1 lần khi được chấp nhận")
	_check(bool(popup.call("is_selection_locked")), "sau khi chọn thành công, mọi thẻ đều bị khóa")
	_check(buttons.all(func(b: Button) -> bool: return b.disabled), "không thể bấm tiếp thẻ khác sau khi đã chọn")

	var offers_wave_8 := [
		{
			"id": &"truck_fleet",
			"title": "ĐỘI XE TẢI",
			"icon_key": &"truck_fleet",
			"rewards": [{"reward_id": 1, "amount": 4}],
		},
		{
			"id": &"boat_capacity",
			"title": "CA-NÔ 2 NGĂN",
			"icon_key": &"boat_capacity",
			"rewards": [{"reward_id": 0, "amount": 40}, {"reward_id": 4, "amount": 1}],
		},
		{
			"id": &"truck_capacity",
			"title": "XE TẢI 2 NGĂN",
			"icon_key": &"truck_capacity",
			"rewards": [{"reward_id": 0, "amount": 40}, {"reward_id": 3, "amount": 1}],
		},
		{
			"id": &"road_highway",
			"title": "ĐƯỜNG & CAO TỐC",
			"icon_key": &"road_highway",
			"rewards": [{"reward_id": 0, "amount": 40}, {"reward_id": 7, "amount": 2}],
		},
	]
	var ok_w8: bool = bool(popup.call("set_offers", offers_wave_8))
	await _frames(1)
	var btns_w8: Array[Button] = popup.call("get_card_buttons")
	_check(ok_w8 and btns_w8.size() == 4 and not bool(popup.call("is_selection_locked")),
			"draft mới mở khóa lại chọn thẻ và render đủ 4 template còn lại với số lượng scale wave 8")

	# Khi backend trả false: không phát card_selected, mở khóa lại thẻ và hiện ErrorBanner.
	selected_signals.clear()
	var reject_calls: Array[StringName] = []
	popup.call("set_backend_hooks",
		func() -> Array: return offers_wave_8,
		func(cid: StringName) -> bool:
			reject_calls.append(cid)
			return false
	)
	btns_w8[0].pressed.emit()
	await _frames(1)
	var err_banner := popup.find_child("ErrorBanner", true, false) as Control
	_check(reject_calls.size() == 1 and selected_signals.is_empty() and not bool(popup.call("is_selection_locked")),
			"khi backend trả false, không phát card_selected và mở khóa lại thẻ")
	_check(err_banner != null and err_banner.visible, "khi backend từ chối, hiện thông báo lỗi rõ ràng")

	get_tree().paused = false
	popup.queue_free()
	await _frames(1)


func _test_card_draft_validation_and_edge_cases() -> void:
	print("\n== 5. Card Draft UI: kiểm tra chặt dữ liệu thiếu/sai kiểu và upgrade đã tối đa")
	var popup: Control = RewardPopupScene.instantiate()
	add_child(popup)
	await _frames(2)

	var calls := 0
	popup.call("set_backend_hooks",
		func() -> Array: return [],
		func(_cid: StringName) -> bool:
			calls += 1
			return true
	)

	var empty_ok: bool = bool(popup.call("set_offers", []))
	var banner := popup.find_child("ErrorBanner", true, false) as Control
	_check(not empty_ok and not popup.call("get_last_errors").is_empty() and banner != null and banner.visible,
			"payload rỗng trả false và hiện khung báo lỗi rõ ràng")

	# Sai số lượng thẻ (3 thẻ thay vì 4).
	var three_cards := [
		{"id": &"c1", "title": "A", "icon_key": &"road_supply", "rewards": [{"reward_id": 0, "amount": 20}]},
		{"id": &"c2", "title": "B", "icon_key": &"truck_fleet", "rewards": [{"reward_id": 1, "amount": 2}]},
		{"id": &"c3", "title": "C", "icon_key": &"junction_kit", "rewards": [{"reward_id": 5, "amount": 1}]},
	]
	_check(not bool(popup.call("set_offers", three_cards)), "payload chỉ có 3 thẻ bị báo lỗi rõ ràng")

	# Thiếu icon_key, reward_id kiểu chuỗi 'abc', trùng id, amount lẻ thập phân.
	var malformed := [
		{"id": &"no_icon", "title": "THIẾU ICON", "rewards": [{"reward_id": 0, "amount": 20}]},
		{"id": &"str_rid", "title": "SAI KIỂU ID", "icon_key": &"truck_fleet", "rewards": [{"reward_id": "abc", "amount": 2}]},
		{"id": &"str_rid", "title": "TRÙNG ID", "icon_key": &"road_supply", "rewards": [{"reward_id": 0, "amount": 20}]},
		{"id": &"frac_amt", "title": "SỐ LẺ", "icon_key": &"road_supply", "rewards": [{"reward_id": 0, "amount": 1.5}]},
	]
	var bad_ok: bool = bool(popup.call("set_offers", malformed))
	await _frames(1)
	var bad_btns: Array[Button] = popup.call("get_card_buttons")
	_check(not bad_ok and popup.call("get_last_errors").size() == 4,
			"bắt đủ 4 lỗi: thiếu icon_key, reward_id chuỗi, trùng id và amount lẻ (%d lỗi)" % popup.call("get_last_errors").size())
	_check(bad_btns.all(func(b: Button) -> bool: return b.disabled),
			"mọi thẻ lỗi đều bị khóa disabled, không hiện thẻ rỗng bấm được")
	bad_btns[0].pressed.emit()
	bad_btns[1].pressed.emit()
	_check(calls == 0, "thẻ lỗi không thể gửi lựa chọn lên backend")

	var prev_truck_cap := GameManager.truck_capacity
	GameManager.truck_capacity = Config.CAPACITY_UPGRADED
	var offers_with_maxed := [
		{"id": &"truck_capacity", "title": "XE TẢI 2 NGĂN", "icon_key": &"truck_capacity", "rewards": [{"reward_id": 0, "amount": 20}, {"reward_id": 3, "amount": 1}]},
		{"id": &"road_supply", "title": "TIẾP TẾ ĐƯỜNG", "icon_key": &"road_supply", "rewards": [{"reward_id": 0, "amount": 20}]},
		{"id": &"junction_kit", "title": "NGÃ TƯ", "icon_key": &"junction_kit", "rewards": [{"reward_id": 5, "amount": 1}, {"reward_id": 6, "amount": 1}]},
		{"id": &"highway_ferry", "title": "CAO TỐC", "icon_key": &"highway_ferry", "rewards": [{"reward_id": 7, "amount": 1}, {"reward_id": 8, "amount": 1}]},
	]
	var max_ok: bool = bool(popup.call("set_offers", offers_with_maxed))
	await _frames(1)
	var max_btns: Array[Button] = popup.call("get_card_buttons")
	_check(max_ok and max_btns[0].disabled and not max_btns[1].disabled,
			"thẻ upgrade đã max bị disable rõ ràng trong khi các thẻ khác vẫn chọn được")
	GameManager.truck_capacity = prev_truck_cap

	popup.queue_free()
	await _frames(1)


func _test_card_draft_no_inner_overflow_and_responsive() -> void:
	print("\n== 6. Card Draft UI: kiểm tra không tràn nội dung ở 1920×1200, 1280×720 và 900×700")
	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(1920, 1200)
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub_vp)

	var popup: Control = RewardPopupScene.instantiate()
	sub_vp.add_child(popup)
	await _frames(2)

	# Gói phức tạp có tới 3 thành phần phần thưởng và tiêu đề dài nhiều từ tiếng Việt.
	var offers := [
		{
			"id": &"road_supply",
			"title": "TIẾP TẾ ĐƯỜNG BỘ KHẨN CẤP",
			"icon_key": &"road_supply",
			"rewards": [{"reward_id": 0, "amount": 60}, {"reward_id": 5, "amount": 2}, {"reward_id": 6, "amount": 2}],
		},
		{
			"id": &"boat_fleet_ferry",
			"title": "ĐỘI CA-NÔ & TUYẾN PHÀ SÔNG",
			"icon_key": &"boat_fleet_ferry",
			"rewards": [{"reward_id": 2, "amount": 4}, {"reward_id": 8, "amount": 2}],
		},
		{
			"id": &"junction_kit",
			"title": "BỘ ĐIỀU TIẾT GIAO LỘ",
			"icon_key": &"junction_kit",
			"rewards": [{"reward_id": 5, "amount": 2}, {"reward_id": 6, "amount": 2}],
		},
		{
			"id": &"highway_ferry",
			"title": "TUYẾN CAO TỐC VƯỢT LŨ",
			"icon_key": &"highway_ferry",
			"rewards": [{"reward_id": 7, "amount": 2}, {"reward_id": 8, "amount": 2}],
		},
	]
	popup.call("set_offers", offers)

	for res in [Vector2i(1920, 1200), Vector2i(1280, 720), Vector2i(900, 700)]:
		sub_vp.size = res
		await _frames(3)
		var grid := popup.find_child("CardsGrid", true, false) as GridContainer
		var root_vbox := popup.find_child("DraftRoot", true, false) as Control
		var btns: Array[Button] = popup.call("get_card_buttons")
		var expected_cols := 4 if res.x >= 960 else 2
		_check(grid.columns == expected_cols,
				"ở %dx%d chia đúng %d cột (%d)" % [res.x, res.y, expected_cols, grid.columns])
		_check(root_vbox.size.x <= float(res.x) + 1.0 and root_vbox.size.y <= float(res.y) + 1.0,
				"ở %dx%d toàn khối DraftRoot nằm gọn trong viewport (%.0f×%.0f)" % [res.x, res.y, root_vbox.size.x, root_vbox.size.y])
		if res == Vector2i(1920, 1200):
			_check(root_vbox.size.y < 720.0,
					"ở 1920×1200 tiêu đề không bị wrap giả cột 0px ở frame đầu (cao %.0f px)" % root_vbox.size.y)
		var no_card_overflow := true
		for b in btns:
			var slot := b.get_parent() as Control
			var pad := slot.find_child("CardPad", false, false) as Control if slot != null else null
			if pad == null or pad.size.y > b.size.y + 1.0 or pad.size.x > b.size.x + 1.0:
				no_card_overflow = false
		_check(no_card_overflow, "ở %dx%d nội dung 3 dòng phần thưởng nằm trọn trong viền từng thẻ" % [res.x, res.y])

	sub_vp.queue_free()
	await _frames(1)


func _test_card_draft_input_isolation() -> void:
	print("\n== 7. Card Draft UI: chặn con lăn và phím tắt lọt xuống bản đồ phía sau")
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	await _frames(1)
	GraphManager.extend_road(-1, Vector2i(10, 10))
	GraphManager.extend_road(GraphManager.road_at(Vector2i(10, 10)), Vector2i(11, 10))

	var sv: Node2D = StageViewScript.new()
	sv.only_in_round = false
	add_child(sv)

	var drawer: Node2D = EdgeDrawerScript.new()
	drawer.only_in_round = false
	add_child(drawer)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var popup: Control = RewardPopupScene.instantiate()
	layer.add_child(popup)
	await _frames(2)

	popup.call("set_offers", [
		{"id": &"road_supply", "title": "ĐƯỜNG", "icon_key": &"road_supply", "rewards": [{"reward_id": 0, "amount": 20}]},
		{"id": &"truck_fleet", "title": "XE TẢI", "icon_key": &"truck_fleet", "rewards": [{"reward_id": 1, "amount": 2}]},
		{"id": &"junction_kit", "title": "NGÃ TƯ", "icon_key": &"junction_kit", "rewards": [{"reward_id": 5, "amount": 1}]},
		{"id": &"highway_ferry", "title": "CAO TỐC", "icon_key": &"highway_ferry", "rewards": [{"reward_id": 7, "amount": 1}]},
	])
	popup.visible = true
	await _frames(2)

	var zoom_before: float = sv.camera.zoom.x
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(600, 400)
	Input.parse_input_event(wheel)
	await _frames(2)
	_check(is_equal_approx(sv.camera.zoom.x, zoom_before),
			"khi RewardPopup đang mở, lăn chuột không làm zoom bản đồ phía sau")

	drawer._hover_cell = Vector2i(10, 10)
	var del_key := InputEventKey.new()
	del_key.keycode = KEY_DELETE
	del_key.pressed = true
	Input.parse_input_event(del_key)
	await _frames(2)
	_check(GraphManager.road_at(Vector2i(10, 10)) != -1,
			"khi RewardPopup đang mở, phím Delete không xóa đường phía sau")

	layer.queue_free()
	drawer.queue_free()
	sv.queue_free()
	await _frames(1)


func _test_ui_root_framing_and_signal_order() -> void:
	print("\n== 8. UIRoot: phủ dim kín toàn màn 16:10 và chịu được mọi thứ tự phát tín hiệu")
	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(1920, 1200)
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub_vp)

	var ui: CanvasLayer = UIRootScene.instantiate()
	sub_vp.add_child(ui)
	await _frames(2)

	var menu_ctrl := ui.get("menu") as Control
	var pause_ctrl := ui.get("pause") as Control
	var reward_ctrl := ui.get("reward") as Control
	var modal_backdrop := ui.get("_modal_backdrop") as ColorRect
	var menu_holder := menu_ctrl.get_parent() as Control
	var pause_holder := pause_ctrl.get_parent() as Control
	_check(menu_holder != null and is_equal_approx(menu_holder.scale.x, 1.5) and is_equal_approx(menu_holder.scale.y, 1.5),
			"holder màn hình Menu cũ ở 1920×1200 có scale đều (1.50, 1.50) và nằm chính giữa")
	_check(pause_holder != null and is_equal_approx(pause_holder.scale.x, 1.5) and is_equal_approx(pause_holder.scale.y, 1.5),
			"holder PauseMenu giữ đúng scale 1.5× không bị Style.pop_in(self) ghi đè")
	_check(reward_ctrl != null and reward_ctrl.anchor_right == 1.0 and reward_ctrl.anchor_bottom == 1.0,
			"RewardPopup dùng full-rect anchors theo toàn viewport")

	# Kiểm tra ModalBackdrop phủ kín toàn bộ 1920×1200 và chặn click xuống HUD khi mở Pause / EndScreen.
	ui.call("_show", "pause")
	await _frames(1)
	_check(modal_backdrop != null and modal_backdrop.visible and modal_backdrop.mouse_filter == Control.MOUSE_FILTER_STOP
			and modal_backdrop.size.distance_to(Vector2(1920, 1200)) < 0.5,
			"ModalBackdrop của PauseMenu phủ kín trọn 1920×1200 và chặn chuột (%.0f×%.0f)" % [modal_backdrop.size.x, modal_backdrop.size.y])
	ui.call("_show", "end")
	await _frames(1)
	_check(modal_backdrop.visible and modal_backdrop.size.distance_to(Vector2(1920, 1200)) < 0.5,
			"ModalBackdrop của EndScreen phủ kín trọn 1920×1200 và chặn click xuống HUD")

	var sample_offers := [
		{"id": &"road_supply", "title": "ĐƯỜNG", "icon_key": &"road_supply", "rewards": [{"reward_id": 0, "amount": 20}]},
		{"id": &"truck_fleet", "title": "XE TẢI", "icon_key": &"truck_fleet", "rewards": [{"reward_id": 1, "amount": 2}]},
		{"id": &"junction_kit", "title": "NGÃ TƯ", "icon_key": &"junction_kit", "rewards": [{"reward_id": 5, "amount": 1}]},
		{"id": &"highway_ferry", "title": "CAO TỐC", "icon_key": &"highway_ferry", "rewards": [{"reward_id": 7, "amount": 1}]},
	]

	# Thứ tự B: state CARD_DRAFT phát trước khi có offers, ngay sau đó card_offers_ready phát trong cùng frame -> không sinh lỗi giả!
	reward_ctrl.call("set_backend_hooks", func() -> Array: return [], func(_cid: StringName) -> bool: return true)
	ui.set("_draft_has_offers", false)
	ui.call("_open_card_draft")
	ui.call("_on_card_offers_ready", sample_offers)
	await _frames(2)
	_check(String(ui.get("current_view")) == "reward" and reward_ctrl.call("get_last_errors").is_empty(),
			"khi state CARD_DRAFT phát trước card_offers_ready trong cùng frame, không bị báo lỗi giả")

	# Thứ tự C: mở draft nhưng backend thực sự không gửi offers cả sau hết frame -> hiện lỗi rõ ràng.
	ui.call("_show", "hud")
	ui.set("_draft_has_offers", false)
	reward_ctrl.set("_offers", [])
	ui.call("_open_card_draft")
	await _frames(2)
	var err_banner := reward_ctrl.find_child("ErrorBanner", true, false) as Control
	_check(not reward_ctrl.call("get_last_errors").is_empty() and err_banner != null and err_banner.visible,
			"khi mở draft mà thực sự thiếu offers sau hết frame, UI báo lỗi rõ ràng")

	sub_vp.queue_free()
	await _frames(1)


func _push_subvp_mouse_btn(vp: SubViewport, pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	vp.push_input(ev)


func _push_subvp_mouse_motion(vp: SubViewport, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	vp.push_input(ev)


func _find_button_by_text(root: Node, caption: String) -> Button:
	for child in root.get_children():
		if child is Button and (child as Button).text == caption:
			return child as Button
		var found := _find_button_by_text(child, caption)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  [ĐẠT]   ", label)
	else:
		_failed += 1
		print("  [TRƯỢT] ", label)

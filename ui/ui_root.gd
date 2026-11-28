extends CanvasLayer
## UI coordinator: all game events are observed via EventBus, no direct access to others' scenes.
const MainMenu = preload("res://ui/main_menu.tscn")
const Guide = preload("res://ui/guide.tscn")
const HUD = preload("res://ui/hud.tscn")
const PauseMenu = preload("res://ui/pause_menu.tscn")
const RewardPopup = preload("res://ui/reward_popup.tscn")
const EndScreen = preload("res://ui/end_screen.tscn")
const AudioSettings = preload("res://ui/audio_settings.tscn")
const SosLayer = preload("res://ui/sos_layer.gd")
const FloodWarningOverlay = preload("res://ui/flood_warning_overlay.gd")
const UITheme = preload("res://ui/theme.tres")

const LEGACY_SCREEN_SIZE := Vector2(1280.0, 720.0)
const BACKDROP_COLOR := Color("#151e28")

var menu
var guide
var hud
var pause
var reward
var ending
var audio
var sos: Node2D
var flood_overlay: Node2D
var _screen_backdrop: ColorRect
var _modal_backdrop: ColorRect
var _legacy_holders: Dictionary = {} # Control screen -> Control holder
var _legacy_screens: Array[Control] = []
var _hud_anchors: Dictionary = {} # "tl"|"tc"|"tr"|"bl"|"bc"|"br" -> Control
var _current_ui_fit: float = 1.0
var current_view: String = "menu"
var _draft_has_offers := false
var _draft_sync_ticket := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen_backdrop = ColorRect.new()
	_screen_backdrop.name = "ScreenBackdrop"
	_screen_backdrop.color = BACKDROP_COLOR
	_screen_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_backdrop)

	menu = _mount_legacy(MainMenu)
	guide = _mount_legacy(Guide)
	hud = _mount(HUD)
	_setup_legacy_hud_scaling()

	_modal_backdrop = ColorRect.new()
	_modal_backdrop.name = "ModalBackdrop"
	_modal_backdrop.color = Color(0.008, 0.025, 0.058, 0.76)
	_modal_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_backdrop)

	pause = _mount_legacy(PauseMenu, true)
	reward = _mount(RewardPopup)
	ending = _mount_legacy(EndScreen, true)
	audio = _mount_legacy(AudioSettings, true)
	_legacy_screens = [menu, guide, pause, ending, audio]

	flood_overlay = Node2D.new()
	flood_overlay.set_script(FloodWarningOverlay)
	add_child(flood_overlay)
	move_child(flood_overlay, 0)
	sos = Node2D.new()
	sos.set_script(SosLayer)
	add_child(sos)
	move_child(sos, 1) # SOS markers and flood highlights stay behind HUD/popups.
	move_child(_screen_backdrop, 2)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_layout_legacy_screens):
		vp.size_changed.connect(_layout_legacy_screens)
	_fit_window_to_screen()
	_layout_legacy_screens()

	menu.connect("start_pressed", _start)
	menu.connect("guide_pressed", func() -> void: _show("guide"))
	menu.connect("audio_pressed", func() -> void: _show("audio"))
	audio.connect("back_pressed", func() -> void: _show("menu"))
	menu.connect("volume_changed", func(value: float) -> void: AudioManager.set_volume(&"Master", value))
	guide.connect("back_pressed", func() -> void: _show("menu"))
	guide.connect("start_pressed", _start)
	hud.connect("pause_pressed", _pause)
	pause.connect("resume_pressed", _resume)
	pause.connect("restart_pressed", _restart)
	pause.connect("menu_pressed", _return_to_menu)
	ending.connect("restart_pressed", _restart)
	ending.connect("menu_pressed", _return_to_menu)
	ending.connect("survey_pressed", _survey)

	EventBus.game_started.connect(_on_started)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	if EventBus.has_signal("card_offers_ready"):
		EventBus.connect("card_offers_ready", _on_card_offers_ready)
	EventBus.game_won.connect(_on_won)
	EventBus.game_lost.connect(_on_lost)
	_show("menu")

# Bong bóng SOS và cảnh báo ngập vẽ theo tọa độ bản đồ: theo camera (vùng chơi theo đợt và zoom con trỏ).
# Bong bóng giữ nguyên kích thước trên màn hình dù camera phóng to.
func _process(_delta: float) -> void:
	var xf := get_viewport().get_canvas_transform()
	sos.transform = xf
	flood_overlay.transform = xf
	var scale_vec := xf.get_scale()
	if scale_vec.x > 0.0001 and scale_vec.y > 0.0001:
		var s := Vector2(1.0 / scale_vec.x, 1.0 / scale_vec.y)
		for m in sos.get_children():
			m.scale = s
	if not _hud_anchors.is_empty() and hud != null:
		var badges = hud.get("badges")
		if badges is Dictionary:
			for pair in (badges as Dictionary).values():
				if pair is Array and (pair as Array).size() > 0 and pair[0] is Control:
					var pill := (pair[0] as Control).get_parent() as Control
					if pill != null:
						pill.pivot_offset = Vector2(pill.size.x * 0.5, 0.0)
						pill.scale = Vector2(_current_ui_fit, _current_ui_fit)

func _mount(scene: PackedScene) -> Control:
	var node: Control = scene.instantiate()
	node.theme = UITheme
	add_child(node)
	return node

# Bọc màn hình 1280×720 cũ trong một holder riêng để hiệu ứng Style.pop_in(self) bên trong màn hình
# (ví dụ PauseMenu) không ghi đè scale căn khung 16:10 của holder.
func _mount_legacy(scene: PackedScene, use_shared_modal_dim: bool = false) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = LEGACY_SCREEN_SIZE
	add_child(holder)

	var node: Control = scene.instantiate()
	node.theme = UITheme
	holder.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if use_shared_modal_dim and node.get_child_count() > 0 and node.get_child(0) is ColorRect:
		(node.get_child(0) as ColorRect).visible = false
	_legacy_holders[node] = holder
	return node

# Tự động neo 6 góc/cạnh và phóng tỷ lệ cho HUD 1280×720 hiện có mà không sửa ui/hud.gd của Người B.
# Khi Người B thay ui/hud.gd sang bản mới dùng anchors gốc (không còn hằng BAR cũ), hàm này tự bỏ qua.
func _setup_legacy_hud_scaling() -> void:
	if hud == null or hud.get("BAR") == null:
		return
	var initial_children: Array = hud.get_children().duplicate()
	for key in ["tl", "tc", "tr", "bl", "bc", "br"]:
		var anchor_box := Control.new()
		anchor_box.name = "HudAnchor_" + key
		anchor_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(anchor_box)
		_hud_anchors[key] = anchor_box
	for node in initial_children:
		var ctrl := node as Control
		if ctrl == null:
			continue
		var v_key := "b" if ctrl.position.y >= 480.0 else "t"
		var h_key := "c"
		if ctrl.position.x + ctrl.size.x <= 320.0:
			h_key = "l"
		elif ctrl.position.x >= 960.0:
			h_key = "r"
		ctrl.reparent(_hud_anchors[v_key + h_key], false)

# Đảm bảo cửa sổ desktop không bao giờ vượt quá vùng hiển thị thật của màn hình (tránh bị cắt mép dưới/taskbar).
func _fit_window_to_screen() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win == null or win.mode != Window.MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen(win.get_window_id())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var frame := DisplayServer.window_get_size_with_decorations(win.get_window_id()) - win.size
	var max_client := Vector2i(maxi(320, usable.size.x - maxi(0, frame.x)), maxi(240, usable.size.y - maxi(0, frame.y)))
	if win.size.x <= max_client.x and win.size.y <= max_client.y:
		return
	var ratio := minf(float(max_client.x) / maxf(1.0, float(win.size.x)), float(max_client.y) / maxf(1.0, float(win.size.y)))
	var new_size := Vector2i(int(floor(float(win.size.x) * ratio)), int(floor(float(win.size.y) * ratio)))
	win.size = new_size
	var total_size := new_size + Vector2i(maxi(0, frame.x), maxi(0, frame.y))
	win.position = usable.position + (usable.size - total_size) / 2

# Căn giữa và phóng đồng tỷ lệ các màn hình 1280×720 cũ trong viewport 16:10 (1920×1200) không kéo giãn.
# RewardPopup (Card Draft) tự scale liên tục theo toàn bộ viewport.
func _layout_legacy_screens() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var fit := minf(vp_size.x / LEGACY_SCREEN_SIZE.x, vp_size.y / LEGACY_SCREEN_SIZE.y)
	if fit <= 0.0001:
		return
	_current_ui_fit = fit
	var pos := (vp_size - LEGACY_SCREEN_SIZE * fit) * 0.5
	var full_local_pos := -pos / fit
	var full_local_size := vp_size / fit
	for screen in _legacy_screens:
		var holder := _legacy_holders.get(screen, null) as Control
		if holder == null:
			continue
		holder.anchor_left = 0.0
		holder.anchor_top = 0.0
		holder.anchor_right = 0.0
		holder.anchor_bottom = 0.0
		holder.size = LEGACY_SCREEN_SIZE
		holder.scale = Vector2(fit, fit)
		holder.position = pos
		if screen == guide:
			for idx in mini(3, screen.get_child_count()):
				var bg_child := screen.get_child(idx) as Control
				if bg_child != null and (bg_child is ColorRect or bg_child is TextureRect):
					bg_child.anchor_left = 0.0
					bg_child.anchor_top = 0.0
					bg_child.anchor_right = 0.0
					bg_child.anchor_bottom = 0.0
					bg_child.position = full_local_pos
					bg_child.size = full_local_size
	if not _hud_anchors.is_empty():
		var s_vec := Vector2(fit, fit)
		var cx := vp_size.x * 0.5 - (LEGACY_SCREEN_SIZE.x * 0.5) * fit
		var rx := vp_size.x - LEGACY_SCREEN_SIZE.x * fit
		var by := vp_size.y - LEGACY_SCREEN_SIZE.y * fit
		var placements := {
			"tl": Vector2(0.0, 0.0),
			"tc": Vector2(cx, 0.0),
			"tr": Vector2(rx, 0.0),
			"bl": Vector2(0.0, by),
			"bc": Vector2(cx, by),
			"br": Vector2(rx, by),
		}
		for key in placements.keys():
			var box := _hud_anchors.get(key, null) as Control
			if box != null:
				box.scale = s_vec
				box.position = placements[key]

func _set_legacy_visible(screen: Control, vis: bool) -> void:
	screen.visible = vis
	var holder := _legacy_holders.get(screen, null) as Control
	if holder != null:
		holder.visible = vis

func _show(name: String) -> void:
	current_view = name
	_set_legacy_visible(menu, name == "menu")
	_set_legacy_visible(guide, name == "guide")
	hud.visible = name in ["hud", "pause", "reward"]
	_set_legacy_visible(pause, name == "pause")
	reward.visible = name == "reward"
	_set_legacy_visible(ending, name == "end")
	_set_legacy_visible(audio, name == "audio")
	sos.visible = name in ["hud", "pause", "reward"]
	flood_overlay.visible = name in ["hud", "pause", "reward"]
	_screen_backdrop.visible = name in ["menu", "guide", "audio"]
	_modal_backdrop.visible = name in ["pause", "end", "audio"]
	hud.set("enabled", name == "hud")

func _start() -> void:
	# Button activation is a user gesture; web browsers then allow music playback.
	GameManager.start_game()
	AudioManager.play_bgm(&"game_bgm")

func _on_started() -> void:
	_draft_has_offers = false
	var card_draft_state := _card_draft_state()
	if card_draft_state != -1 and GameManager.state == card_draft_state:
		_open_card_draft()
	else:
		_show("hud")

func _pause() -> void:
	GameManager.pause_game()

func _resume() -> void:
	GameManager.resume_game()

func _restart() -> void:
	GameManager.restart()

func _return_to_menu() -> void:
	# GameManager freezes the abandoned round and emits game_state_changed(MENU);
	# _on_game_state_changed then stops the music and shows the menu.
	GameManager.exit_to_menu()

func _survey() -> void:
	if not Config.SURVEY_URL.is_empty():
		OS.shell_open(Config.SURVEY_URL)

func _card_draft_state() -> int:
	return int(Types.GameState.get("CARD_DRAFT", -1))

func _open_card_draft() -> void:
	_draft_sync_ticket += 1
	var ticket := _draft_sync_ticket
	if not _draft_has_offers:
		# Nếu backend đã có sẵn snapshot offers khi đổi state sang CARD_DRAFT thì nạp ngay;
		# nếu C phát game_state_changed(CARD_DRAFT) trước rồi mới phát card_offers_ready ở dòng kế tiếp,
		# chờ hết frame hiện tại mới báo thiếu dữ liệu để tránh lỗi giả.
		if GameManager.has_method("get_card_offers"):
			var snap = GameManager.call("get_card_offers")
			if snap is Array and not (snap as Array).is_empty():
				_draft_has_offers = true
				reward.call("set_offers", snap)
		if not _draft_has_offers:
			_deferred_sync_draft.call_deferred(ticket)
	_show("reward")

func _deferred_sync_draft(ticket: int) -> void:
	if ticket != _draft_sync_ticket or _draft_has_offers or current_view != "reward":
		return
	reward.call("sync_from_backend")
	_draft_has_offers = true

func _on_card_offers_ready(offers: Array) -> void:
	_draft_sync_ticket += 1
	_draft_has_offers = true
	reward.call("set_offers", offers)
	if GameManager.state != Types.GameState.WON and GameManager.state != Types.GameState.LOST:
		_show("reward")

func _on_game_state_changed(state: int) -> void:
	var card_draft_state := _card_draft_state()
	if state == Types.GameState.MENU:
		_draft_has_offers = false
		AudioManager.play_bgm(&"")
		_show("menu")
	elif card_draft_state != -1 and state == card_draft_state:
		_open_card_draft()
	elif state == Types.GameState.PAUSED:
		# Keep the map visible; resume and speed controls stay in the compact HUD clock.
		pause.visible = false
		hud.set("enabled", false)
	elif state == Types.GameState.PLAYING or state == Types.GameState.WAVE_BREAK:
		_draft_has_offers = false
		if current_view == "pause" or current_view == "reward":
			_show("hud")
		else:
			hud.set("enabled", current_view in ["hud", "reward"])

func _on_won(stats: Dictionary) -> void:
	_draft_has_offers = false
	AudioManager.play_bgm(&"")
	ending.call("set_result", true, stats)
	_show("end")

func _on_lost(stats: Dictionary) -> void:
	_draft_has_offers = false
	AudioManager.play_bgm(&"")
	ending.call("set_result", false, stats)
	_show("end")

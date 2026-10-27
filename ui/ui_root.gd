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

var menu
var guide
var hud
var pause
var reward
var ending
var audio
var sos: Node2D
var flood_overlay: Node2D
var current_view: String = "menu"
var reward_pending: bool = false # reward offered but not chosen yet; restore its popup after pausing in a break

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu = _mount(MainMenu)
	guide = _mount(Guide)
	hud = _mount(HUD)
	pause = _mount(PauseMenu)
	reward = _mount(RewardPopup)
	ending = _mount(EndScreen)
	audio = _mount(AudioSettings)
	flood_overlay = Node2D.new()
	flood_overlay.set_script(FloodWarningOverlay)
	add_child(flood_overlay)
	move_child(flood_overlay, 0)
	sos = Node2D.new()
	sos.set_script(SosLayer)
	add_child(sos)
	move_child(sos, 1) # SOS markers and flood highlights stay behind HUD/popups.
	# Match the graph coordinate space: 1280×720, unchanged.
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
	reward.connect("reward_pressed", _choose_reward)
	ending.connect("restart_pressed", _restart)
	ending.connect("menu_pressed", _return_to_menu)
	ending.connect("survey_pressed", _survey)
	EventBus.game_started.connect(_on_started)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.reward_offered.connect(_on_reward_offered)
	EventBus.reward_chosen.connect(_on_reward_chosen)
	EventBus.game_won.connect(_on_won)
	EventBus.game_lost.connect(_on_lost)
	_show("menu")

func _mount(scene: PackedScene) -> Control:
	var node: Control = scene.instantiate()
	node.theme = UITheme
	add_child(node)
	return node

func _show(name: String) -> void:
	current_view = name
	menu.visible = name == "menu"
	guide.visible = name == "guide"
	hud.visible = name in ["hud", "pause", "reward"]
	pause.visible = name == "pause"
	reward.visible = name == "reward"
	ending.visible = name == "end"
	audio.visible = name == "audio"
	sos.visible = name in ["hud", "pause", "reward"]
	flood_overlay.visible = name in ["hud", "pause", "reward"]
	hud.set("enabled", name == "hud" or name == "reward")

func _start() -> void:
	# Button activation is a user gesture; web browsers then allow music playback.
	GameManager.start_game()
	AudioManager.play_bgm(&"game_bgm")

func _on_started() -> void:
	reward_pending = false
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

func _choose_reward(choice: int) -> void:
	GameManager.choose_reward(choice)

func _survey() -> void:
	if not Config.SURVEY_URL.is_empty():
		OS.shell_open(Config.SURVEY_URL)

func _on_game_state_changed(state: int) -> void:
	if state == Types.GameState.MENU:
		AudioManager.play_bgm(&"")
		_show("menu")
	elif state == Types.GameState.PAUSED:
		_show("pause")
	elif (state == Types.GameState.PLAYING or state == Types.GameState.WAVE_BREAK) and current_view == "pause":
		_show("reward" if reward_pending else "hud")

func _on_reward_offered(options: Array) -> void:
	reward_pending = true
	reward.call("set_options", options)
	_show("reward")

func _on_reward_chosen(_choice: int) -> void:
	reward_pending = false
	_show("hud")

func _on_won(stats: Dictionary) -> void:
	AudioManager.play_bgm(&"")
	ending.call("set_result", true, stats)
	_show("end")

func _on_lost(stats: Dictionary) -> void:
	AudioManager.play_bgm(&"")
	ending.call("set_result", false, stats)
	_show("end")

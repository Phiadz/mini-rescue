extends Control
signal back_pressed
const Style = preload("res://ui/style.gd")
const BUSES: Array[StringName] = [&"Master", &"BGM", &"SFX"]
const TITLES := ["MASTER", "BGM", "SFX"]
var sliders: Array[HSlider] = []
var numbers: Array[Label] = []
var initial: Array[float] = []

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    add_child(dim)
    Style.full(dim)
    dim.color = Color(0, 0.02, 0.05, 0.77)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    Style.rect(self, 185, 83, 910, 554, Color("#0c2035"), Style.CYAN, 20)
    Style.text(self, "CÀI ĐẶT ÂM THANH", 250, 109, 780, 65, 42, Style.WHITE, true)
    Style.text(self, "Điều chỉnh âm lượng cho trò chơi", 340, 175, 600, 32, 18, Style.MUTED, true)
    for i in range(3):
        var y: int = 223 + i * 100
        Style.rect(self, 227, y, 825, 84, Color("#12304d"), Color("#255e8c"), 13)
        Style.text(self, TITLES[i], 260, y + 17, 200, 51, 27, Style.WHITE)
        var value := _get_bus_value(BUSES[i])
        initial.append(value)
        var slider := HSlider.new()
        add_child(slider)
        slider.position = Vector2(484, y + 20)
        slider.size = Vector2(397, 45)
        slider.min_value = 0.0
        slider.max_value = 100.0
        slider.step = 1.0
        slider.value = roundi(value * 100)
        slider.add_theme_stylebox_override("slider", Style.rounded(Color("#071b2c"), Color("#1689cd"), 7, 1))
        slider.add_theme_stylebox_override("grabber_area", Style.rounded(Color("#168de6"), Color.TRANSPARENT, 7, 0))
        slider.add_theme_stylebox_override("grabber_area_highlight", Style.rounded(Style.CYAN, Color.TRANSPARENT, 7, 0))
        slider.value_changed.connect(_on_change.bind(i))
        # Preview a click when the user finishes adjusting this slider.
        # It stays audible while BGM is muted, provided Master and SFX are enabled.
        slider.drag_ended.connect(_on_slider_drag_ended)
        sliders.append(slider)
        numbers.append(Style.text(self, "%d%%" % roundi(value * 100), 918, y + 19, 110, 45, 24, Style.YELLOW, true))
    var back := Style.button(self, "QUAY LẠI", 253, 551, 352, 60, Color("#27547a"), 24)
    back.pressed.connect(_cancel)
    var apply := Style.button(self, "ÁP DỤNG", 670, 551, 354, 60, Color("#efbf35"), 24, Color("#142235"))
    apply.pressed.connect(_apply)

func _on_slider_drag_ended(_value_changed: bool) -> void:
    AudioManager.play_sfx(&"ui_click")

func _get_bus_value(name: StringName) -> float:
    var idx := AudioServer.get_bus_index(name)
    if idx < 0: return 1.0
    return 0.0 if AudioServer.is_bus_mute(idx) else clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)

func _on_change(value: float, idx: int) -> void:
    numbers[idx].text = "%d%%" % roundi(value)
    AudioManager.set_volume(BUSES[idx], value / 100.0)

func _cancel() -> void:
    for i in range(BUSES.size()):
        AudioManager.set_volume(BUSES[i], initial[i])
        sliders[i].set_value_no_signal(roundi(initial[i] * 100.0))
        numbers[i].text = "%d%%" % roundi(initial[i] * 100.0)
    back_pressed.emit()

func _apply() -> void:
    for i in range(BUSES.size()):
        initial[i] = float(sliders[i].value) / 100.0
    back_pressed.emit()

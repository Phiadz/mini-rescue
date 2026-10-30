extends Control
signal reward_pressed(reward: int)
const Style = preload("res://ui/style.gd")
const ICONS := ["res://assets/icons/road_dry.svg", "res://assets/icons/truck.svg", "res://assets/icons/boat.svg"]
const TITLES := ["+2 HẠN MỨC TUYẾN", "+1 XE TẢI", "+1 CA-NÔ"]
const DETAILS := ["Tăng 2 tuyến đường có thể xây.", "Thêm 1 xe tải vận chuyển hàng.", "Thêm 1 ca-nô cứu hộ trên nước."]
var timer_label: Label
var options: Array = [0, 1, 2]
var cards: Array[Button] = []
var selected: int = 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    add_child(dim)
    Style.full(dim)
    dim.color = Color(0.0, 0.02, 0.05, 0.76)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    Style.rect(self, 235, 35, 810, 652, Color("#0c2035"), Style.CYAN, 20)
    Style.text(self, "CHỌN PHẦN THƯỞNG", 305, 81, 670, 55, 40, Style.YELLOW, true)
    Style.text(self, "Hết đợt lũ. Chọn 1 phần thưởng trước khi đợt mới bắt đầu.", 295, 143, 690, 38, 18, Style.WHITE, true)
    Style.rect(self, 836, 48, 154, 48, Color("#112b45"), Style.YELLOW, 12)
    timer_label = Style.text(self, "15s", 845, 50, 136, 43, 25, Style.YELLOW, true)
    for i in range(3):
        var y: int = 200 + i * 123
        var card := Style.button(self, "", 280, y, 720, 110, Color("#133451"), 22)
        card.add_theme_stylebox_override("normal", Style.rounded(Color("#133451"), Style.BORDER, 14, 2))
        card.pressed.connect(_select.bind(i))
        cards.append(card)
        var icon := TextureRect.new()
        card.add_child(icon)
        icon.position = Vector2(24, 8)
        icon.size = Vector2(125, 90)
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.texture = load(ICONS[i])
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        Style.text(card, TITLES[i], 184, 14, 500, 45, 27, Style.YELLOW)
        Style.text(card, DETAILS[i], 184, 57, 500, 39, 19, Style.WHITE)
    var skip := Style.button(self, "BỎ QUA", 281, 592, 333, 64, Color("#294a70"), 23)
    skip.pressed.connect(_skip)
    var accept := Style.button(self, "XÁC NHẬN", 634, 592, 366, 64, Color("#f5bd34"), 23, Color("#152135"))
    accept.pressed.connect(_confirm)
    _refresh_selection()

func set_options(new_options: Array) -> void:
    options = new_options.duplicate()
    selected = 0
    if not cards.is_empty():
        _refresh_selection()

func _process(_delta: float) -> void:
    if timer_label != null:
        timer_label.text = "%ds" % ceili(maxf(0.0, GameManager.break_left))

func _select(idx: int) -> void:
    if idx >= options.size(): return
    selected = idx
    _refresh_selection()

func _refresh_selection() -> void:
    for i in range(cards.size()):
        cards[i].disabled = i >= options.size()
        var outline := Style.YELLOW if i == selected else Style.BORDER
        cards[i].add_theme_stylebox_override("normal", Style.rounded(Color("#174064") if i == selected else Color("#133451"), outline, 14, 3 if i == selected else 2))
        cards[i].add_theme_stylebox_override("hover", Style.rounded(Color("#205078"), Style.CYAN, 14, 3))

func _confirm() -> void:
    if selected < options.size():
        reward_pressed.emit(int(options[selected]))

func _skip() -> void:
    if not options.is_empty():
        reward_pressed.emit(int(options[0]))

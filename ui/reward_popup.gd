extends Control
signal reward_pressed(reward: int)
const Style = preload("res://ui/style.gd")
var countdown: float = 15.0
var timer_label: Label
var options: Array = []
var cards: Array[Button] = []

func _ready() -> void:
	var bg := ColorRect.new()
	add_child(bg)
	Style.full(bg)
	bg.color = Color(0.0,0.025,0.055,0.88)
	Style.text(self, "CHỌN PHẦN THƯỞNG", 70, 30, 1020, 80, 52, Style.WHITE)
	Style.separator(self, 112)
	Style.text(self, "Chọn 1 trong 3 phần thưởng để tiếp tục", 75, 124, 800, 55, 27)
	Style.rect(self, 1050, 106, 135, 114, Color("#0b2b4b"), Style.YELLOW, 58)
	timer_label = Style.text(self, "15", 1050, 111, 135, 100, 44, Style.WHITE, true)
	for i in range(3):
		var x: int = 114 + i*362
		var label: String = ["+2 TUYẾN", "+1 XE TẢI", "+1 CA-NÔ"][i]
		var symbol: String = ["▰▰", "▣", "▰"][i]
		var border: Color = Style.ORANGE if i == 1 else Style.CYAN
		Style.rect(self, x, 242, 335, 331, Color(0.0, 0.08, 0.17, 0.97), border, 16)
		if i == 0:
			Style.text(self, symbol, x+65, 272, 210, 86, 74, border, true)
		else:
			var picture := TextureRect.new()
			add_child(picture)
			# Allow TextureRect to shrink below the PNG's native 640x400 size.
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.texture = load("res://assets/icons/rescue_truck.png") if i == 1 else load("res://assets/icons/rescue_boat.png")
			picture.position = Vector2(x + 65, 255)
			picture.size = Vector2(205, 105)
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Style.text(self, label, x+12, 370, 311, 60, 36, Style.YELLOW if i == 1 else Style.CYAN, true)
		var detail: String = ["Tăng thêm 2 tuyến đường\ncó thể xây dựng.", "Tăng thêm 1 xe tải cứu hộ.", "Thêm 1 ca-nô di chuyển\nđược qua vùng ngập sâu."][i]
		Style.text(self, detail, x+25, 434, 290, 80, 22, Style.WHITE, true)
		var choose := Style.button(self, "CHỌN", x+35, 517, 265, 50, Style.BLUE, 20)
		choose.pressed.connect(_choose.bind(i))
		cards.append(choose)

func set_options(new_options: Array) -> void:
	options = new_options.duplicate()
	countdown = 15.0
	for i in range(cards.size()):
		cards[i].disabled = i >= options.size()

func _process(delta: float) -> void:
	countdown = maxf(0.0, countdown-delta)
	timer_label.text = "%d" % int(ceil(countdown))

func _choose(idx: int) -> void:
	if idx < options.size():
		reward_pressed.emit(int(options[idx]))

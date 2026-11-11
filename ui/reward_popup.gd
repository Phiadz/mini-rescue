extends Control
## Cửa hàng cứu trợ, mở trong lượt nghỉ giữa hai đợt.
## Bấm một thẻ là mua món đó (GameManager.choose_reward trừ quỹ). Mua được nhiều món; giá mỗi món tăng sau mỗi lần mua.
## Quỹ cộng theo điểm mỗi SOS cứu được; quỹ thừa giữ sang lượt nghỉ sau. Bấm XONG để quay lại bản đồ.
signal reward_pressed(reward: int)
signal done_pressed
const Style = preload("res://ui/style.gd")
const ICONS := ["res://assets/icons/road_dry.svg", "res://assets/icons/truck.svg", "res://assets/icons/boat.svg"]
var titles: Array = ["+%d Ô ĐƯỜNG" % Config.REWARD_EDGE_BONUS, "+1 XE TẢI", "+1 CA-NÔ"]
var details: Array = ["Thêm %d ô đường có thể xây." % Config.REWARD_EDGE_BONUS, "Thêm 1 xe tải vận chuyển hàng.", "Thêm 1 ca-nô cứu hộ trên nước."]
var timer_label: Label
var funds_label: Label
var options: Array = [0, 1, 2]
var cards: Array[Button] = []
var price_labels: Array[Label] = []
var count_labels: Array[Label] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	add_child(dim)
	Style.full(dim)
	dim.color = Color(0.0, 0.02, 0.05, 0.76)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	Style.rect(self, 235, 35, 810, 652, Color("#0c2035"), Style.CYAN, 20)
	Style.text(self, "CỬA HÀNG CỨU TRỢ", 305, 98, 670, 52, 38, Style.YELLOW, true)
	Style.text(self, "Mỗi SOS cứu được cộng vào quỹ. Mua bao nhiêu tùy ý, quỹ thừa giữ sang lần sau.", 285, 150, 710, 36, 17, Style.WHITE, true)
	Style.rect(self, 290, 50, 190, 42, Color("#112b45"), Style.YELLOW, 12)
	funds_label = Style.text(self, "QUỸ 0", 295, 50, 180, 42, 24, Style.YELLOW, true)
	Style.rect(self, 836, 50, 154, 42, Color("#112b45"), Style.YELLOW, 12)
	timer_label = Style.text(self, "15s", 845, 50, 136, 42, 25, Style.YELLOW, true)
	for i in range(3):
		var y: int = 200 + i * 123
		var card := Style.button(self, "", 280, y, 720, 110, Color("#133451"), 22)
		card.focus_mode = Control.FOCUS_NONE
		card.pressed.connect(func() -> void: reward_pressed.emit(int(options[i])))
		cards.append(card)
		var icon := TextureRect.new()
		card.add_child(icon)
		icon.position = Vector2(24, 8)
		icon.size = Vector2(125, 90)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(ICONS[i])
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Style.text(card, titles[i], 170, 14, 360, 45, 27, Style.YELLOW)
		Style.text(card, details[i], 170, 54, 360, 28, 19, Style.WHITE)
		count_labels.append(Style.text(card, "", 170, 82, 360, 26, 15, Style.MUTED))
		price_labels.append(Style.text(card, "", 540, 20, 160, 70, 34, Style.YELLOW, true))
	var done := Style.button(self, "XONG", 450, 592, 380, 64, Color("#f5bd34"), 23, Color("#152135"))
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(func() -> void: done_pressed.emit())
	refresh()


func set_options(new_options: Array) -> void:
	options = new_options.duplicate()
	refresh()


func _process(_delta: float) -> void:
	if timer_label != null:
		timer_label.text = "%ds" % ceili(maxf(0.0, GameManager.break_left))
	if visible:
		refresh()  # quỹ có thể tăng khi xe giao hàng xong trong lượt nghỉ


# Cập nhật quỹ, giá, số lần đã mua; thẻ nào không đủ quỹ thì mờ đi và không bấm được.
func refresh() -> void:
	if cards.is_empty():
		return
	var funds: int = GameManager.get_funds()
	funds_label.text = "QUỸ %d" % funds
	for i in range(cards.size()):
		var has_item := i < options.size()
		var price: int = GameManager.get_price(int(options[i])) if has_item else 0
		var can_buy := has_item and funds >= price
		cards[i].disabled = not can_buy
		cards[i].modulate.a = 1.0 if can_buy else 0.45
		price_labels[i].text = str(price) if has_item else ""
		var bought: int = GameManager.get_bought_count(int(options[i])) if has_item else 0
		count_labels[i].text = ("Đã mua %d lần trong ván" % bought) if bought > 0 else ""
		var outline := Style.YELLOW if can_buy else Style.BORDER
		cards[i].add_theme_stylebox_override("normal", Style.rounded(Color("#133451"), outline, 14, 2))
		cards[i].add_theme_stylebox_override("hover", Style.rounded(Color("#205078"), Style.CYAN, 14, 3))
		cards[i].add_theme_stylebox_override("disabled", Style.rounded(Color("#0f2236"), Style.BORDER, 14, 1))

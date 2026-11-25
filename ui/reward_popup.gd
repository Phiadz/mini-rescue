
extends Control

## Cửa hàng cứu trợ, mở trong lượt nghỉ giữa hai đợt.
## Bấm thẻ để mua thông qua GameManager.choose_reward().
## Ba món cũ mua nhiều lần; hai nâng cấp sức chứa chỉ mua một lần mỗi ván.

signal reward_pressed(reward: int)
signal done_pressed

const Style = preload("res://ui/style.gd")

const ICONS := [
	"res://assets/icons/road_dry.svg",
	"res://assets/icons/truck.svg",
	"res://assets/icons/boat.svg",
	"res://assets/icons/upgrade_up.svg",
	"res://assets/icons/upgrade_up.svg"
]

var titles: Array = [
	"+%d Ô ĐƯỜNG" % Config.REWARD_EDGE_BONUS,
	"+%d XE TẢI" % Config.REWARD_VEHICLE_BONUS,
	"+%d CA-NÔ" % Config.REWARD_VEHICLE_BONUS,
	"⬆ XE TẢI 2 NGĂN",
	"⬆ CA-NÔ 2 NGĂN"
]

var details: Array = [
	"Thêm %d ô đường có thể xây." % Config.REWARD_EDGE_BONUS,
	"Thêm %d xe tải vận chuyển hàng." % Config.REWARD_VEHICLE_BONUS,
	"Thêm %d ca-nô cứu hộ trên nước." % Config.REWARD_VEHICLE_BONUS,
	"Nâng sức chứa từ 1 lên 2 kiện tiếp tế.",
	"Nâng sức chứa từ 1 lên 2 kiện tiếp tế."
]

var timer_label: Label
var funds_label: Label

# ID tương ứng Types.Reward: 0, 1, 2, 3, 4
var options: Array = [0, 1, 2, 3, 4]

var cards: Array[Button] = []
var price_labels: Array[Label] = []
var count_labels: Array[Label] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Nền tối phía sau Shop
	var dim := ColorRect.new()
	add_child(dim)
	Style.full(dim)
	dim.color = Color(0.0, 0.02, 0.05, 0.76)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP

	# Khung Shop
	Style.rect(
		self, 235, 35, 810, 652,
		Color("#0c2035"), Style.CYAN, 20
	)

	# Tiêu đề
	Style.text(
		self, "CỬA HÀNG CỨU TRỢ",
		305, 98, 670, 52, 38,
		Style.YELLOW, true
	)

	Style.text(
		self,
		"Mỗi SOS cứu được, nhà nước và nhà hảo tâm cấp thêm kinh phí cứu trợ.",
		285, 150, 710, 36, 17,
		Style.WHITE, true
	)

	# Hiển thị Quỹ
	Style.rect(
		self, 290, 50, 230, 42,
		Color("#112b45"), Style.YELLOW, 12
	)

	funds_label = Style.text(
		self, "QUỸ 0",
		295, 50, 220, 42, 22,
		Style.YELLOW, true
	)

	# Đồng hồ đếm ngược
	Style.rect(
		self, 836, 50, 154, 42,
		Color("#112b45"), Style.YELLOW, 12
	)

	timer_label = Style.text(
		self, "15s",
		845, 50, 136, 42, 25,
		Style.YELLOW, true
	)

	# Tạo 5 thẻ Shop
	for i in range(5):
		var y: int = 195 + i * 76

		var card := Style.button(
			self, "",
			280, y, 720, 70,
			Color("#133451"), 16
		)

		card.focus_mode = Control.FOCUS_NONE

		# Gửi đúng ID món hàng được bấm
		var reward_id: int = i
		card.pressed.connect(
			func() -> void:
				if reward_id < options.size():
					reward_pressed.emit(int(options[reward_id]))
		)

		cards.append(card)

		# Icon
		var icon := TextureRect.new()
		card.add_child(icon)

		icon.position = Vector2(16, 7)
		icon.size = Vector2(76, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(ICONS[i])
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Tên sản phẩm
		Style.text(
			card, titles[i],
			105, 5, 425, 27, 21,
			Style.YELLOW
		)

		# Mô tả sản phẩm
		Style.text(
			card, details[i],
			105, 31, 425, 22, 14,
			Style.WHITE
		)

		# Trạng thái đã mua
		var count_label := Style.text(
			card, "",
			105, 51, 425, 17, 12,
			Style.MUTED
		)
		count_labels.append(count_label)

		# Giá sản phẩm
		var price_label := Style.text(
			card, "",
			540, 8, 165, 52, 21,
			Style.YELLOW, true
		)
		price_labels.append(price_label)

	# Nút XONG
	var done := Style.button(
		self, "XONG",
		450, 592, 380, 64,
		Color("#f5bd34"), 23,
		Color("#152135")
	)

	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(
		func() -> void:
			done_pressed.emit()
	)

	refresh()
	Style.pop_in(self)


# Đổi Quỹ sang đơn vị tiền Việt
static func money_text(units: int) -> String:
	var vnd: int = units * Config.FUND_UNIT_VND

	if vnd >= 1000000000:
		var s := "%.2f" % (vnd / 1000000000.0)
		s = s.rstrip("0").rstrip(".")
		return s.replace(".", ",") + " tỷ"

	if vnd >= 1000000:
		return "%d triệu" % (vnd / 1000000)

	return "0 đồng" if vnd == 0 else "%d đồng" % vnd


# Nhận danh sách sản phẩm được phép hiển thị
func set_options(new_options: Array) -> void:
	options = new_options.duplicate()
	refresh()


func _process(_delta: float) -> void:
	if timer_label != null:
		timer_label.text = "%ds" % ceili(
			maxf(0.0, GameManager.break_left)
		)

	if visible:
		refresh()


# Kiểm tra sản phẩm có phải nâng cấp sức chứa không
func is_capacity_upgrade(reward: int) -> bool:
	return reward == Types.Reward.UPGRADE_TRUCK_CAP \
		or reward == Types.Reward.UPGRADE_BOAT_CAP


# Cập nhật giá, Quỹ và trạng thái các thẻ
func refresh() -> void:
	if cards.is_empty():
		return

	var funds: int = GameManager.get_funds()
	funds_label.text = "QUỸ " + money_text(funds)

	for i in range(cards.size()):
		var has_item: bool = i < options.size()

		if not has_item:
			cards[i].disabled = true
			cards[i].visible = false
			continue

		cards[i].visible = true

		var reward: int = int(options[i])
		var price: int = GameManager.get_price(reward)
		var bought: int = GameManager.get_bought_count(reward)

		var upgrade: bool = is_capacity_upgrade(reward)
		var owned: bool = upgrade and bought > 0

		# Chỉ cho mua khi đủ Quỹ và chưa sở hữu nâng cấp
		var can_buy: bool = funds >= price and not owned

		cards[i].disabled = not can_buy
		cards[i].modulate.a = 1.0 if can_buy else 0.55

		# Hiển thị trạng thái và giá
		if owned:
			price_labels[i].text = "✓ ĐÃ SỞ HỮU"
			count_labels[i].text = "Đã nâng cấp trong ván này"
		else:
			price_labels[i].text = money_text(price)

			if bought > 0:
				count_labels[i].text = "Đã mua %d lần trong ván" % bought
			else:
				count_labels[i].text = ""

		# Viền thẻ
		var outline := Style.YELLOW if can_buy else Style.BORDER

		cards[i].add_theme_stylebox_override(
			"normal",
			Style.rounded(Color("#133451"), outline, 14, 2)
		)

		cards[i].add_theme_stylebox_override(
			"hover",
			Style.rounded(Color("#205078"), Style.CYAN, 14, 3)
		)

		cards[i].add_theme_stylebox_override(
			"disabled",
			Style.rounded(Color("#0f2236"), Style.BORDER, 14, 1)
		)

extends Control
signal back_pressed
signal start_pressed
const Style = preload("res://ui/style.gd")
var page: int = 0
var title_label: Label
var cards: Array[Panel] = []
var numbered: Array[Label] = []
var headings: Array[Label] = []
var descriptions: Array[Label] = []
var symbols: Array[Label] = []
var guide_boat_icon: TextureRect

const ITEMS := [
	["Kéo nối tuyến đường", "Kéo nối các nhà, kho để tạo tuyến đường cứu hộ.", "⌂  ━━━━━  ⌂"],
	["SOS (yêu cầu cứu hộ)", "Kết nối tuyến đường đến các điểm SOS để cứu người dân.", "● SOS  ⚑"],
	["Nước lũ làm ngập đường", "Mực nước dâng cao sẽ làm ngập các tuyến đường, không thể đi qua.", "≈≈≈  ⌂  ≈≈≈"],
	["Ca-nô đi đường ngập sâu", "Sử dụng ca-nô để di chuyển qua các khu vực ngập sâu.", "≈  ◀▰▶  ≈"],
	["Ưu tiên yêu cầu SOS", "Bấm vào biểu tượng SOS để ưu tiên. Tối đa 2 yêu cầu cùng lúc.", "★  SOS  ★"],
	["Lũ dâng theo 3 đợt", "Đường bộ bị ngập dần. Tìm tuyến khác hoặc cho ca-nô hoạt động.", "↑  ≈≈≈  ↑"],
	["Cứu hộ tự tìm đường", "Phương tiện tự tìm đường trên các tuyến bạn đã nối. Không lái xe thủ công.", "⌂ ━ ▶ ━ ⚑"],
	["Thắng và thua", "Sống sót qua đợt 3 để thắng. Thất bại khi có 3 SOS quá hạn.", "★ ★ ★"],
]

func _ready() -> void:
	Style.background(self, Color(0.0, 0.05, 0.13, 0.77))
	Style.text(self, "HƯỚNG DẪN NHANH", 54, 22, 820, 80, 52, Style.WHITE)
	title_label = Style.text(self, "1/2", 1030, 26, 170, 74, 36, Style.CYAN, true)
	Style.separator(self, 104)
	for i in range(4):
		var x: int = 65 + (i % 2) * 590
		var y: int = 127 + int(i / 2) * 242
		var card := Style.rect(self, x, y, 560, 217, Color(0.0, 0.1, 0.23, 0.88), Style.BORDER, 12)
		cards.append(card)
		var n := Style.text(card, str(i+1), 18, 12, 48, 38, 25, Style.NIGHT, true)
		var badge := Style.rect(card, 15, 10, 50, 40, Style.CYAN, Style.CYAN, 6)
		badge.move_to_front()
		n.move_to_front()
		numbered.append(n)
		headings.append(Style.text(card, "", 79, 10, 460, 40, 24, Style.WHITE))
		descriptions.append(Style.text(card, "", 22, 57, 515, 65, 19, Style.MUTED))
		symbols.append(Style.text(card, "", 45, 130, 470, 70, 35, Style.CYAN, true))
		if i == 3:
			guide_boat_icon = TextureRect.new()
			card.add_child(guide_boat_icon)
			guide_boat_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			guide_boat_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			guide_boat_icon.texture = load("res://assets/icons/rescue_boat.png")
			guide_boat_icon.position = Vector2(160, 126)
			guide_boat_icon.size = Vector2(240, 82)
			guide_boat_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Style.button(self, "‹   QUAY LẠI", 65, 629, 275, 62, Style.NIGHT, 24)
	back.pressed.connect(_on_back)
	var next := Style.button(self, "TIẾP THEO   ›", 944, 629, 275, 62, Style.BLUE, 24)
	next.pressed.connect(_on_next)
	var start := Style.button(self, "▶ CHƠI NGAY", 450, 632, 380, 57, Style.YELLOW, 24, Style.NIGHT)
	start.pressed.connect(func() -> void: start_pressed.emit())
	start.hide() # Shown only on page 2.
	set_meta("next_button", next)
	set_meta("start_button", start)
	_redraw()

func _redraw() -> void:
	title_label.text = "%d/2" % (page + 1)
	for i in range(4):
		var it: Array = ITEMS[page*4+i]
		numbered[i].text = str(page*4+i+1)
		headings[i].text = str(it[0])
		descriptions[i].text = str(it[1])
		symbols[i].text = str(it[2])
		symbols[i].visible = not (page == 0 and i == 3)
	guide_boat_icon.visible = page == 0
	(get_meta("next_button") as Button).visible = page == 0
	(get_meta("start_button") as Button).visible = page == 1

func _on_next() -> void:
	page = 1
	_redraw()

func _on_back() -> void:
	if page == 1:
		page = 0
		_redraw()
	else:
		back_pressed.emit()

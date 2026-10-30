extends Control
## UI-only tutorial. Does not call gameplay logic or mutate GameManager.
signal back_pressed
signal start_pressed

const Style = preload("res://ui/style.gd")
const ICON_PATH := "res://assets/icons/%s.svg"
const ART_TOP := 124.0
const ART_H := 83.0
var page: int = 0
var page_label: Label
var cards: Array[Panel] = []
var badges: Array[Label] = []
var headings: Array[Label] = []
var descriptions: Array[Label] = []
var visuals: Array[Control] = []
var next_button: Button
var start_button: Button

const ITEMS := [
	["Kéo nối tuyến đường", "Giữ chuột trái ở một điểm, kéo đến điểm khác để nối tuyến."],
	["SOS (yêu cầu cứu hộ)", "Lương thực: hình tròn. Y tế: dấu cộng trắng."],
	["Nước lũ làm ngập đường", "Đường khô chuyển sang ngập nhẹ, rồi ngập sâu khi nước dâng."],
	["Ca-nô đi đường ngập sâu", "Ca-nô đi được tuyến ngập nhẹ và sâu; không đi đường khô."],
	["Ưu tiên yêu cầu SOS", "Bấm vào SOS đang chờ để ưu tiên, tối đa 2 yêu cầu cùng lúc."],
	["Lũ dâng theo 3 đợt", "Lũ tăng qua 3 đợt. Nếu đường bị chặn, hãy nối tuyến khác."],
	["Cứu hộ tự tìm đường", "Xe và ca-nô tự tìm đường trên các tuyến đã nối; không lái trực tiếp."],
	["Thắng và thua", "Thắng: qua đợt 3. Thua: tích lũy 3 SOS thất bại."]
]

func _ready() -> void:
	Style.background(self, Color(0.0, 0.05, 0.13, 0.77))
	Style.text(self, "HƯỚNG DẪN NHANH", 54, 22, 820, 80, 52, Style.WHITE)
	page_label = Style.text(self, "1/2", 1030, 26, 170, 74, 36, Style.CYAN, true)
	Style.separator(self, 104)
	for i in range(4):
		var x := 65 + (i % 2) * 590
		var y := 127 + int(i / 2) * 242
		var card := Style.rect(self, x, y, 560, 217, Color(0.0, 0.1, 0.23, 0.88), Style.BORDER, 12)
		cards.append(card)
		Style.rect(card, 15, 10, 50, 40, Style.CYAN, Style.CYAN, 6)
		badges.append(Style.text(card, "", 16, 10, 48, 40, 25, Style.NIGHT, true))
		headings.append(Style.text(card, "", 79, 10, 460, 40, 24, Style.WHITE))
		var desc := Style.text(card, "", 22, 55, 516, 68, 18, Style.MUTED)
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		descriptions.append(desc)
		var visual := Control.new()
		card.add_child(visual)
		visual.position = Vector2(20, ART_TOP)
		visual.size = Vector2(520, ART_H)
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visuals.append(visual)
	var back := Style.button(self, "‹   QUAY LẠI", 65, 629, 275, 62, Style.NIGHT, 24)
	back.pressed.connect(_on_back)
	next_button = Style.button(self, "TIẾP THEO   ›", 944, 629, 275, 62, Style.BLUE, 24)
	next_button.pressed.connect(_on_next)
	start_button = Style.button(self, "▶ CHƠI NGAY", 450, 632, 380, 57, Style.YELLOW, 24, Style.NIGHT)
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	_refresh()

func _icon(parent: Control, name: String, pos: Vector2, box_size: Vector2) -> void:
	var rect := TextureRect.new()
	parent.add_child(rect)
	rect.position = pos
	rect.size = box_size
	rect.texture = load(ICON_PATH % name) as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _line(parent: Control, x: float, y: float, length: float, color: Color, dotted: bool = false) -> void:
	var seg_count := 9 if dotted else 1
	for i in range(seg_count):
		var p := ColorRect.new()
		parent.add_child(p)
		p.color = color
		p.position = Vector2(x + (length / float(seg_count)) * i, y)
		p.size = Vector2(length / float(seg_count) * (0.58 if dotted else 1.0), 5.0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _tag(parent: Control, text: String, x: float, y: float, width: float, color: Color = Style.MUTED) -> void:
	var l := Style.text(parent, text, x, y, width, 19, 13, color, true)
	l.clip_text = true

func _art(parent: Control, index: int) -> void:
	match index:
		0:
			_icon(parent, "hub_north", Vector2(54, 0), Vector2(92, 78))
			_line(parent, 159, 40, 187, Style.YELLOW)
			_icon(parent, "house_blue", Vector2(362, 0), Vector2(92, 78))
		1:
			_icon(parent, "sos", Vector2(128, 0), Vector2(77, 58))
			_icon(parent, "sos_medical", Vector2(316, 0), Vector2(77, 58))
			_tag(parent, "LƯƠNG THỰC", 105, 58, 122)
			_tag(parent, "Y TẾ", 307, 58, 95)
		2:
			_line(parent, 35, 29, 126, Style.YELLOW)
			_line(parent, 199, 29, 126, Color("#E8B366"), true)
			_line(parent, 360, 29, 126, Color("#268CDB"))
			_tag(parent, "KHÔ", 35, 43, 126)
			_tag(parent, "NGẬP NHẸ", 199, 43, 126)
			_tag(parent, "NGẬP SÂU", 360, 43, 126)
		3:
			_line(parent, 91, 45, 337, Color("#268CDB"))
			_icon(parent, "boat", Vector2(217, 0), Vector2(90, 77))
		4:
			_icon(parent, "sos", Vector2(206, 0), Vector2(108, 65))
			_tag(parent, "CHẠM SOS ĐỂ ƯU TIÊN", 157, 64, 207, Style.YELLOW)
		5:
			for i in range(3):
				_line(parent, 39 + i * 168, 34 - i * 8, 112, Color("#399BE3"))
				_tag(parent, "ĐỢT %d" % (i + 1), 39 + i * 168, 48, 112)
		6:
			_icon(parent, "hub_north", Vector2(4, 0), Vector2(96, 78))
			_line(parent, 101, 38, 105, Style.YELLOW)
			_icon(parent, "truck", Vector2(204, 8), Vector2(99, 64))
			_line(parent, 303, 38, 107, Style.YELLOW)
			_icon(parent, "sos", Vector2(423, 5), Vector2(68, 62))
		7:
			_tag(parent, "THẮNG: QUA 3 ĐỢT", 20, 26, 225, Color("#6DE6B5"))
			_tag(parent, "THUA: 3 SOS THẤT BẠI", 262, 26, 245, Color("#FF8A92"))

func _refresh() -> void:
	page_label.text = "%d/2" % (page + 1)
	for i in range(4):
		var idx := page * 4 + i
		badges[i].text = str(idx + 1)
		headings[i].text = ITEMS[idx][0]
		descriptions[i].text = ITEMS[idx][1]
		for child in visuals[i].get_children():
			child.free()
		_art(visuals[i], idx)
	next_button.visible = page == 0
	start_button.visible = page == 1

func _on_next() -> void:
	page = 1
	_refresh()

func _on_back() -> void:
	if page == 1:
		page = 0
		_refresh()
	else:
		back_pressed.emit()

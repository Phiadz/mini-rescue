extends Control
signal restart_pressed
signal survey_pressed
const Style = preload("res://ui/style.gd")
var won: bool = true
var stats: Dictionary = {}
var result_label: Label
var star_label: Label
var caption_label: Label
var numbers: Array[Label] = []
var survey_button: Button

func _ready() -> void:
	Style.background(self, Color(0.0, 0.04, 0.12, 0.60))
	Style.text(self, "KẾT QUẢ CỨU HỘ", 55, 30, 750, 74, 50)
	Style.separator(self, 111)
	Style.rect(self, 78, 154, 643, 396, Color(0.01,0.055,0.11,0.82), Style.BORDER, 14)
	result_label = Style.text(self, "THẮNG LỢI", 105, 172, 583, 81, 65, Style.YELLOW, true)
	star_label = Style.text(self, "★ ★ ☆", 140, 259, 500, 93, 79, Style.YELLOW, true)
	caption_label = Style.text(self, "Bạn đã cứu được nhiều người dân!", 117, 378, 570, 63, 25, Style.YELLOW, true)
	Style.rect(self, 748, 153, 459, 405, Color(0.0, 0.07, 0.14, 0.94), Style.BORDER, 12)
	var titles := ["★  Điểm", "⌂  SOS cứu được", "✕  Số lần thất bại", "◷  Thời gian sống sót", "⚑  Đợt đạt tới"]
	for i in range(5):
		var y: int = 172 + i*76
		Style.text(self, titles[i], 774, y, 279, 56, 23, Style.WHITE)
		numbers.append(Style.text(self, "0", 1050, y, 125, 56, 25, Style.YELLOW, true))
		Style.rect(self, 764, y+65, 432, 1, Style.BORDER, Style.BORDER, 0)
	var restart := Style.button(self, "↻   CHƠI LẠI", 260, 588, 350, 75, Style.BLUE, 30)
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	survey_button = Style.button(self, "▤   KHẢO SÁT", 682, 588, 350, 75, Style.NIGHT, 30)
	survey_button.pressed.connect(func() -> void: survey_pressed.emit())
	survey_button.disabled = Config.SURVEY_URL.is_empty()
	if survey_button.disabled:
		survey_button.tooltip_text = "Nhóm chưa điền Config.SURVEY_URL"

func set_result(is_win: bool, data: Dictionary) -> void:
	won = is_win
	stats = data.duplicate()
	if not is_node_ready():
		return
	result_label.text = "THẮNG LỢI" if won else "THẤT BẠI"
	result_label.add_theme_color_override("font_color", Style.YELLOW if won else Style.ORANGE)
	var stars: int = clampi(int(stats.get("stars", 0)), 0, 3)
	var star_text := ""
	for i in range(3):
		star_text += ("★" if i < stars else "☆") + " "
	star_label.text = star_text.strip_edges() if won else "✕ ✕ ✕"
	caption_label.text = "Bạn đã cứu được nhiều người dân!" if won else "Hãy thử thay đổi tuyến cứu hộ!"
	var ts: int = int(stats.get("time_survived", 0))
	var values := [str(stats.get("score", 0)), str(stats.get("saved", 0)), "%d / 3" % int(stats.get("failed", 0)), "%02d:%02d" % [int(ts / 60), ts % 60], "%d / 3" % int(stats.get("wave_reached", 0))]
	for i in range(numbers.size()):
		numbers[i].text = values[i]

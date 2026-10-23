extends Control
signal start_pressed
signal guide_pressed
signal volume_changed(value: float)
const Style = preload("res://ui/style.gd")

func _ready() -> void:
	Style.background(self, Color(0.0, 0.05, 0.12, 0.38))
	Style.text(self, "FLOODLINE", 260, 95, 760, 120, 94, Style.YELLOW, true)
	Style.text(self, "﹏﹏﹏  CỨU HỘ 0 GIỜ  ﹏﹏﹏", 355, 221, 570, 60, 30, Style.CYAN, true)
	Style.rect(self, 414, 402, 452, 250, Color(0.01, 0.08, 0.17, 0.83), Color("#2086c3"), 18)
	var play := Style.button(self, "▶   CHƠI", 455, 423, 370, 64, Style.YELLOW, 32, Style.NIGHT)
	play.pressed.connect(func() -> void: start_pressed.emit())
	var help := Style.button(self, "▣   HƯỚNG DẪN", 455, 501, 370, 63, Style.NIGHT, 27)
	help.pressed.connect(func() -> void: guide_pressed.emit())
	Style.text(self, "◖))   ÂM LƯỢNG", 471, 583, 214, 42, 21, Style.WHITE)
	var slider := HSlider.new()
	add_child(slider)
	slider.position = Vector2(678, 589)
	slider.size = Vector2(126, 35)
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 65
	slider.value_changed.connect(func(v: float) -> void: volume_changed.emit(v / 100.0))
	Style.text(self, "LẬP KẾ HOẠCH  •  CỨU HỘ  •  CHẠY ĐUA VỚI LŨ", 290, 663, 700, 37, 19, Style.MUTED, true)

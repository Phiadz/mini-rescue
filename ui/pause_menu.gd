extends Control
signal resume_pressed
signal restart_pressed
signal menu_pressed
const Style = preload("res://ui/style.gd")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	add_child(dim)
	Style.full(dim)
	dim.color = Color(0.0, 0.015, 0.05, 0.79)
	Style.rect(self, 335, 133, 610, 466, Color("#061c38"), Style.CYAN, 22)
	Style.text(self, "TẠM DỪNG", 385, 164, 510, 90, 55, Style.WHITE, true)
	Style.text(self, "Trò chơi đang tạm dừng", 395, 243, 490, 38, 21, Style.MUTED, true)
	var go := Style.button(self, "▶   TIẾP TỤC", 414, 306, 452, 71, Style.YELLOW, 30, Style.NIGHT)
	go.pressed.connect(func() -> void: resume_pressed.emit())
	var retry := Style.button(self, "⟳   CHƠI LẠI", 414, 406, 452, 67, Color("#0b3157"), 27)
	retry.pressed.connect(func() -> void: restart_pressed.emit())
	var home := Style.button(self, "⌂   VỀ MENU", 414, 494, 452, 67, Color("#0b3157"), 27)
	home.pressed.connect(func() -> void: menu_pressed.emit())

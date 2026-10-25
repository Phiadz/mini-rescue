extends Control
signal resume_pressed
signal restart_pressed
signal menu_pressed
const Style = preload("res://ui/style.gd")

func _ready() -> void:
	var bg := ColorRect.new()
	add_child(bg)
	Style.full(bg)
	bg.color = Color(0.0, 0.02, 0.06, 0.77)
	Style.rect(self, 413, 190, 454, 350, Color("#05172b"), Style.BORDER, 18)
	Style.text(self, "TẠM DỪNG", 430, 220, 421, 70, 51, Style.WHITE, true)
	var resume := Style.button(self, "▶   TIẾP TỤC", 458, 312, 366, 66, Style.YELLOW, 29, Style.NIGHT)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	var restart := Style.button(self, "↻   CHƠI LẠI", 458, 395, 366, 60, Style.NIGHT, 27)
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	var menu := Style.button(self, "⌂   VỀ MENU", 458, 471, 366, 54, Style.NIGHT, 25)
	menu.pressed.connect(func() -> void: menu_pressed.emit())

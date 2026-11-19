extends Control
## Màn khởi động (scene chạy đầu tiên): hiện "ĐANG TẢI…", làm nóng shader (ShaderWarmup vẽ sau nền che kín) và nạp sẵn
## scene game, xong mới chuyển sang game/main.tscn, nơi UIRoot hiện menu. Menu hiện ra là bấm được ngay, không đứng
## nửa giây vì trình duyệt đang biên dịch shader; việc này chỉ chạy một lần mỗi lần mở game.

const Style = preload("res://ui/style.gd")
const Warmup = preload("res://ui/shader_warmup.gd")
const BG := Color("#06142a")


func _ready() -> void:
	var warm := Warmup.new()
	add_child(warm)  # con đầu tiên: vẽ trước nền nên bị che kín
	var bg := ColorRect.new()
	add_child(bg)
	Style.full(bg)
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.text(self, "ĐANG TẢI…", 0, 330, 1280, 60, 26, Style.MUTED, true)
	warm.finished.connect(_enter_game)


func _enter_game() -> void:
	var main := GameManager.preload_main_scene()
	if main != null:
		get_tree().change_scene_to_packed(main)
	else:
		get_tree().change_scene_to_file(GameManager.MAIN_SCENE)

extends Control
## FLOODLINE - result overlay. Everything is native Godot UI; map remains visible behind.
signal restart_pressed
signal menu_pressed
signal survey_pressed

const C_NAVY := Color("#081b31")
const C_PANEL := Color("#0b213b")
const C_LINE := Color("#3174a7")
const C_WHITE := Color("#ecf7ff")
const C_GOLD := Color("#ffda55")
const C_RED := Color("#ff626c")
const C_LIGHT := Color("#a7d9f2")
var won: bool = true
var stats: Dictionary = {}
var shade: ColorRect
var frame: Panel
var content: Control
var outcome_art: Control
var title_label: Label
var subtitle_label: Label
var stat_values: Array[Label] = []
var stat_names: Array[Label] = []
var replay_button: Button
var heading: Label

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade = ColorRect.new()
    shade.color = Color(0.012,0.035,0.072,0.66)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(shade)
    content = Control.new()
    content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(content)
    frame = Panel.new()
    frame.position = Vector2(344,74)
    frame.size = Vector2(592,584)
    frame.add_theme_stylebox_override("panel", _style(C_PANEL, C_LINE, 18, 2))
    content.add_child(frame)
    var inner: Panel = Panel.new()
    inner.position = Vector2(16,16)
    inner.size = Vector2(560,552)
    inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    inner.add_theme_stylebox_override("panel", _style(Color("#0a1c33"), Color("#173f63"), 12, 1))
    frame.add_child(inner)
    outcome_art = Control.new()
    outcome_art.position = Vector2(196, 21)
    outcome_art.size = Vector2(200, 140)
    outcome_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.add_child(outcome_art)
    title_label = _label(frame,"",Vector2(24,169),Vector2(544,62),51,C_GOLD,true)
    subtitle_label = _label(frame,"",Vector2(36,237),Vector2(520,30),19,C_WHITE,true)
    var stats_box: Panel = Panel.new()
    stats_box.position = Vector2(37,285)
    stats_box.size = Vector2(518,178)
    stats_box.add_theme_stylebox_override("panel", _style(Color("#07172c"), Color("#2d5982"), 11, 1))
    frame.add_child(stats_box)
    var labels: Array[String] = ["SOS đã cứu", "Dân được cứu", "Thời gian"]
    for i in range(3):
        var y: float = 13.0 + float(i)*55.0
        var symbol: String = ["◎", "●", "◷"][i]
        _label(stats_box,symbol,Vector2(17,y+1),Vector2(36,45),27,C_LIGHT,true)
        stat_names.append(_label(stats_box,labels[i],Vector2(61,y+5),Vector2(282,40),21,C_WHITE,false))
        stat_values.append(_label(stats_box,"0",Vector2(353,y+1),Vector2(144,44),26,C_GOLD,true))
        if i < 2:
            var line := ColorRect.new()
            line.position = Vector2(20,y+51)
            line.size = Vector2(477,1)
            line.color = Color("#295071")
            line.mouse_filter = Control.MOUSE_FILTER_IGNORE
            stats_box.add_child(line)
    _action(frame,"⌂  VỀ MENU",Vector2(37,489),Vector2(245,67),false,func() -> void: menu_pressed.emit())
    replay_button = _action(frame,"⟳  CHƠI LẠI",Vector2(311,489),Vector2(244,67),true,func() -> void: restart_pressed.emit())
    set_result(won,stats)

func _style(bg: Color, border: Color, radius: int, line_width: int) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(line_width)
    s.set_corner_radius_all(radius)
    s.shadow_color = Color(0,0,0,0.45)
    s.shadow_size = 7
    return s

func _label(parent: Node, text: String, pos: Vector2, sz: Vector2, font_size: int, color: Color, centered: bool) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.size = sz
    l.add_theme_font_size_override("font_size",font_size)
    l.add_theme_color_override("font_color",color)
    l.add_theme_color_override("font_shadow_color",Color(0,0,0,0.54))
    l.add_theme_constant_override("shadow_offset_x",1)
    l.add_theme_constant_override("shadow_offset_y",2)
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(l)
    return l

func _action(parent: Node, title: String, pos: Vector2, sz: Vector2, accent: bool, callback: Callable) -> Button:
    var b := Button.new()
    b.position = pos
    b.size = sz
    b.text = title
    b.add_theme_font_size_override("font_size",22)
    b.add_theme_color_override("font_color",Color("#11223a") if accent else C_WHITE)
    b.add_theme_color_override("font_hover_color",Color("#11223a") if accent else Color.WHITE)
    b.add_theme_stylebox_override("normal",_style(C_GOLD if accent else Color("#244d83"),Color("#fbed95") if accent else Color("#5685b6"),12,2))
    b.add_theme_stylebox_override("hover",_style(Color("#ffe983") if accent else Color("#3263a0"),Color.WHITE,12,2))
    b.add_theme_stylebox_override("pressed",_style(Color("#f7bc37") if accent else Color("#173963"),Color.WHITE,12,2))
    b.pressed.connect(callback)
    parent.add_child(b)
    return b

func _draw_art() -> void:
    for child in outcome_art.get_children():
        child.queue_free()
    if won:
        # A trophy constructed from UI shapes (not a flattened background image).
        var halo: Label = _label(outcome_art,"✦   ✧     ✦",Vector2(-40,4),Vector2(280,90),31,C_GOLD,true)
        halo.modulate.a = 0.9
        var trophy := TextureRect.new()
        trophy.texture = preload("res://assets/icons/result_trophy.svg")
        trophy.position = Vector2(10,-15)
        trophy.size = Vector2(180,145)
        trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
        outcome_art.add_child(trophy)
        _label(outcome_art,"✦         ✦",Vector2(-21,96),Vector2(242,38),23,C_GOLD,true)
    else:
        var danger := _label(outcome_art,"!",Vector2(71,3),Vector2(69,69),54,C_RED,true)
        var circle := Panel.new()
        circle.position = Vector2(78,14)
        circle.size = Vector2(55,55)
        circle.add_theme_stylebox_override("panel",_style(Color("#ff5c65"),Color("#ff8c94"),27,1))
        outcome_art.add_child(circle)
        danger.move_to_front()
        danger.add_theme_color_override("font_color",Color("#101b30"))
        var house := TextureRect.new()
        house.texture = preload("res://assets/icons/house_coral.svg")
        house.position = Vector2(43,52)
        house.size = Vector2(122,88)
        house.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        house.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        house.mouse_filter = Control.MOUSE_FILTER_IGNORE
        outcome_art.add_child(house)
        _label(outcome_art,"≈  ≈  ≈",Vector2(1,113),Vector2(198,28),29,Color("#17b9e9"),true)

func set_result(is_win: bool, data: Dictionary) -> void:
    won = is_win
    stats = data.duplicate()
    if not is_node_ready():
        return
    _draw_art()
    title_label.text = "CHIẾN THẮNG" if won else "THẤT BẠI"
    title_label.add_theme_color_override("font_color", C_GOLD if won else C_RED)
    subtitle_label.text = ("Bạn đã vượt qua %d đợt lũ!" % (int(stats.get("wave_reached", Config.WAVE_COUNT - 1)) + 1)) if won else ("Đã có %d yêu cầu SOS quá hạn." % int(stats.get("failed",3)))
    replay_button.add_theme_stylebox_override("normal",_style(C_GOLD if won else Color("#e94151"),Color("#fbed95") if won else Color("#ff8c96"),12,2))
    replay_button.add_theme_stylebox_override("hover",_style(Color("#ffe983") if won else Color("#ff6874"),Color.WHITE,12,2))
    replay_button.add_theme_color_override("font_color",Color("#11223a") if won else Color.WHITE)
    var rescued: int = int(stats.get("saved",0))
    var people: int = int(stats.get("people_saved",rescued*3))
    var sec: int = maxi(0,int(stats.get("time_survived",0)))
    stat_values[0].text = str(rescued)
    stat_values[1].text = str(people)
    stat_values[2].text = "%02d:%02d" % [int(sec/60),sec%60]
    for value in stat_values:
        value.add_theme_color_override("font_color",C_GOLD if won else C_LIGHT)
    if not won:
        stat_values[0].add_theme_color_override("font_color",C_RED)

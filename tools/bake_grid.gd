extends Node
# Tính độ cao từng ô lưới từ height_field.png rồi ghi vào data/map_01.json (khóa "grid").
# Đọc sẵn vào json vì lúc chạy trên web không đọc pixel của ảnh đã nhập được.
# Chạy lại khi đổi bản đồ độ cao hoặc kích thước ô (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/bake_grid.tscn
# height_field.png: 16 bit, kênh đỏ là byte cao, kênh xanh lá là byte thấp, thang 0-100.
# Đổi về thang độ cao của game: ảnh = H0 + SCALE × độ cao (đo từ 10 điểm trong map_01.json).

const SOURCE := 'res://assets/icons/terrain/height_field.png'
const MAP := 'res://data/map_01.json'
const H0 := 16.7
const SCALE := 0.667


func _ready() -> void:
	var field: Image = load(SOURCE).get_image()
	field.convert(Image.FORMAT_RGBA8)
	var rows: PackedStringArray = []
	var values: Array[float] = []
	for y in Config.GRID_ROWS:
		var row: PackedStringArray = []
		for x in Config.GRID_COLS:
			var v := _cell_elevation(field, x, y)
			values.append(v)
			row.append('%.1f' % v)
		rows.append('      ' + ', '.join(row))
	_write(',\n'.join(rows))
	_report(values)
	get_tree().quit()


func _cell_elevation(field: Image, cx: int, cy: int) -> float:
	var sum := 0.0
	for y in Config.CELL_SIZE:
		for x in Config.CELL_SIZE:
			sum += _height(field, cx * Config.CELL_SIZE + x, cy * Config.CELL_SIZE + y)
	var h := sum / float(Config.CELL_SIZE * Config.CELL_SIZE)
	return clampf((h - H0) / SCALE, 0.0, 100.0)


func _height(field: Image, x: int, y: int) -> float:
	var c := field.get_pixel(mini(x, field.get_width() - 1), mini(y, field.get_height() - 1))
	return (int(round(c.r * 255.0)) * 256 + int(round(c.g * 255.0))) / 65535.0 * 100.0


# Giữ nguyên phần "nodes", chỉ thay khóa "grid" ở cuối tệp.
func _write(rows: String) -> void:
	var text := FileAccess.get_file_as_string(MAP).replace('\r\n', '\n')
	var cut := text.find(',\n  "grid"')
	if cut != -1:
		text = text.substr(0, cut) + '\n}\n'
	var end := text.rfind(']')
	var grid := ',\n  "grid": {\n    "elevation": [\n%s\n    ]\n  }\n}\n' % rows
	var file := FileAccess.open(MAP, FileAccess.WRITE)
	file.store_string(text.substr(0, end + 1) + grid)
	file.close()


# In độ cao ô tại 10 điểm để đối chiếu với độ cao ghi trong json.
func _report(values: Array[float]) -> void:
	var nodes: Array = JSON.parse_string(FileAccess.get_file_as_string(MAP))['nodes']
	for n in nodes:
		var c := Vector2i(int(n['x']) / Config.CELL_SIZE, int(n['y']) / Config.CELL_SIZE)
		print('%-18s json %5.1f   ô %5.1f' % [n['name'], float(n['elevation']), values[c.y * Config.GRID_COLS + c.x]])
	var sorted := values.duplicate()
	sorted.sort()
	print('Độ cao ô: nhỏ nhất %.1f, trung vị %.1f, lớn nhất %.1f' % [sorted[0], sorted[sorted.size() / 2], sorted[-1]])

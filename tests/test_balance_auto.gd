extends Node
# Tự chơi nhiều ván trên mạng đường cố định để chỉnh hạn mức, đồng thời đo thời gian tìm đường.
# Không có kiểm tra đạt/trượt: chỉ in số liệu. Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_balance_auto.tscn
# Chạy ít ván hơn để dò nhanh: thêm "-- games=4" vào cuối lệnh. Đo khung hình ở tốc độ thật: "-- games=1 speed=1 seconds=150"
# (speed: hệ số tua, mặc định SPEED; seconds: dừng ván sau chừng ấy giây chơi).
# Chụp màn hình lúc dừng (chạy có cửa sổ, bỏ --headless): thêm "shot=D:/duong/dan/anh.png".
# Cách chơi cố định: nối sẵn các tuyến, không sửa đường, không chọn thưởng. Không thay cho người chơi thật.
# Bản đồ có cổng: tuyến nối từ ô cổng tới ô cổng theo đường ngắn nhất (đi lại trên đường có sẵn không tốn hạn mức),
# chừa HOUSE_RESERVE ô để nối nhà mọc thêm; nhà mới mọc thì tự nối cổng nhà tới đường gần nhất;
# mỗi lượt nghỉ mua thêm ô đường nếu đủ quỹ.

const SPEED := 10.0
const GAMES := 10
# 16 tuyến đầu nối hết 17 điểm; các tuyến sau là đường vòng, tô tới khi hết hạn mức.
const ROUTES := [[0, 16], [16, 5], [5, 10], [10, 3], [3, 2], [3, 6], [6, 11], [11, 7], [2, 14], [7, 8], [8, 12], [12, 13],
		[13, 1], [14, 9], [2, 4], [4, 15], [6, 14], [7, 12], [8, 10], [0, 5], [11, 13], [4, 9]]
const TREE_ROUTES := 16
const HOUSE_RESERVE := 16   # bản đồ có cổng: chừa chừng này ô hạn mức cho nhà mọc thêm
const HOUSE_LINK_MAX := 6   # nối nhà mới tới đường có sẵn trong chừng này ô
const NB8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var _stats := {}
var _won := false
var _moving := 0.0  # tổng thời gian xe chạy trên đường (giây × xe)
var _jammed := 0.0
var _frame_ms := 0.0  # tổng thời gian thực giữa hai khung hình (ms); TIME_PROCESS của Godot sai khi chạy headless với --fixed-fps
var _frame_max := 0.0
var _frames := 0
var _last_tick := 0
var _sos_node := {}     # mã SOS -> nút có SOS
var _sos_taken := {}    # mã SOS đã có xe nhận
var _fail_why := {}     # lý do SOS thất bại -> số lần


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	reparent(get_tree().root)  # start_game() đổi sang main.tscn, node này phải sống sót
	EventBus.game_won.connect(func(st: Dictionary) -> void:
		_stats = st
		_won = true)
	EventBus.game_lost.connect(func(st: Dictionary) -> void:
		_stats = st
		_won = false)
	EventBus.wave_ended.connect(_print_states)
	EventBus.point_added.connect(func(id: int) -> void: _link_house.call_deferred(id))
	EventBus.card_offers_ready.connect(func(offers: Array) -> void: _pick_card.call_deferred(offers))
	EventBus.sos_spawned.connect(func(rid: int, node: int, _sup: int, _t: float) -> void: _sos_node[rid] = node)
	EventBus.sos_assigned.connect(func(rid: int, _vid: int) -> void: _sos_taken[rid] = true)
	EventBus.sos_failed.connect(_on_sos_failed)
	var games := GAMES
	var speed := SPEED
	var limit := 0.0
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("games="):
			games = maxi(1, int(arg.trim_prefix("games=")))
		elif arg.begins_with("speed="):
			speed = maxf(0.1, float(arg.trim_prefix("speed=")))
		elif arg.begins_with("seconds="):
			limit = float(arg.trim_prefix("seconds="))
		elif arg.begins_with("shot="):
			shot = arg.trim_prefix("shot=")
	Engine.time_scale = speed
	var wins := 0
	var scores := 0
	var jam_total := 0.0
	for i in games:
		_stats = {}
		await GameManager.start_game()
		_build()
		var used: int = GraphManager.get_edge_budget().used
		_moving = 0.0
		_jammed = 0.0
		_frame_ms = 0.0
		_frame_max = 0.0
		_frames = 0
		_last_tick = Time.get_ticks_usec()
		_fail_why.clear()
		while _stats.is_empty():
			await get_tree().process_frame
			_count_jams()
			if limit > 0.0 and GameManager.get_time_survived() >= limit:
				print('Dừng ở %.0f giây (tốc độ x%.1f): %d xe đang chạy, %d nhà, khung hình trung bình %.2f ms, lâu nhất %.1f ms' % [
						GameManager.get_time_survived(), speed, RescueManager._vehicles.values().filter(func(v) -> bool: return v.is_moving()).size(),
						GraphManager.get_node_ids().size() - 17, _frame_ms / maxf(_frames, 1), _frame_max])
				if not shot.is_empty():
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(shot)
					print('Đã chụp ', shot)
				get_tree().quit()
				return
		wins += 1 if _won else 0
		scores += _stats.score
		jam_total += _jammed / maxf(_moving, 0.001)
		print('Ván %2d: %-5s %4d điểm, cứu %2d, thất bại %d, %3.0f giây, %d ô đường, kẹt %4.1f%% thời gian chạy' % [
			i + 1, 'thắng' if _won else 'thua', _stats.score, _stats.saved, _stats.failed, _stats.time_survived, used, 100.0 * _jammed / maxf(_moving, 0.001)])
		print('        khung hình (thời gian thực): trung bình %.2f ms, lâu nhất %.1f ms; SOS thất bại vì: %s' % [_frame_ms / maxf(_frames, 1), _frame_max, str(_fail_why)])
	print('Tổng: thắng %d/%d, điểm trung bình %.0f, kẹt trung bình %.1f%% thời gian chạy (%d xe tải, %d ca-nô lúc đầu)' % [
			wins, games, float(scores) / games, 100.0 * jam_total / games, RescueManager.START_TRUCKS, RescueManager.START_BOATS])
	_time_find_path()
	get_tree().quit()


# SOS hết giờ: ghi lý do (không xe nào tới được, có đường nhưng chưa xe nhận, đã có xe nhận nhưng tới trễ), kèm loại điểm.
func _on_sos_failed(rid: int) -> void:
	var node: int = _sos_node.get(rid, -1)
	var n := GraphManager.get_map_node(node)
	var where := 'nhà' if n != null and n.name.is_empty() else 'khu'
	var why := 'xe tới trễ'
	if not _sos_taken.has(rid):
		var truck := GraphManager.find_path(RescueManager._hub_for(Types.VehicleType.TRUCK), node, Types.VehicleType.TRUCK).found
		var boat := GraphManager.find_path(RescueManager._hub_for(Types.VehicleType.BOAT), node, Types.VehicleType.BOAT).found
		why = 'chưa xe nhận' if truck or boat else 'không có đường'
	var key := '%s (%s)' % [why, where]
	_fail_why[key] = int(_fail_why.get(key, 0)) + 1


# Mỗi khung hình: cộng thời gian chạy và thời gian bị kẹt của các xe đang trên đường.
func _count_jams() -> void:
	var dt := get_process_delta_time()
	var now := Time.get_ticks_usec()
	var ms := (now - _last_tick) / 1000.0
	_last_tick = now
	_frame_ms += ms
	_frame_max = maxf(_frame_max, ms)
	_frames += 1
	for v in RescueManager._vehicles.values():
		if v.is_moving():
			_moving += dt
			if v.jammed:
				_jammed += dt


func _build() -> void:
	if GraphManager.uses_gates():
		_build_gated()
		return
	for r in ROUTES:
		var from := _cell(r[0])
		var to := _cell(r[1])
		var last: int = r[0]
		var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
		for i in range(1, steps + 1):
			var cell := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / steps).round())
			last = GraphManager.extend_road(last, cell)
			if last == -1:
				return  # hết hạn mức


func _build_gated() -> void:
	for i in ROUTES.size():
		var b: Dictionary = GraphManager.get_edge_budget()
		if i >= TREE_ROUTES and b.limit - b.used <= HOUSE_RESERVE:
			return  # chừa hạn mức cho nhà mọc thêm
		var r: Array = ROUTES[i]
		var to: int = _entry(r[1])
		_connect(_entry(r[0]), func(c: Vector2i) -> bool: return GraphManager.road_at(c) == to, 64)


# Ô đường ngay trước lối vào của điểm: kho có ô cổng sẵn; khu, nhà chưa nối thì tô một ô theo hướng lối vào
# (thử các hướng khác nếu ô đó không tô được). -1 nếu không tô được.
func _entry(id: int) -> int:
	var g := GraphManager.get_gate_node(id)
	if g != -1:
		return g
	var n := GraphManager.get_map_node(id)
	var c := GraphManager.cell_of(n.pos)
	for d in [n.gate, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if d == Vector2i.ZERO:
			continue
		var r := GraphManager.extend_road(id, c + d)
		if r != -1:
			return r
	return -1


# Nhà mới mọc: tô ô trước lối vào rồi nối tới ô đường gần nhất đã nối vào mạng (không phải ô còn lẻ).
func _link_house(id: int) -> void:
	var gate := _entry(id)
	if gate == -1 or GraphManager.get_edges_of(gate).size() >= 2:
		return  # không tô được, hoặc nhà mọc sát đường: ô trước lối vào đã nằm trong mạng
	_connect(gate, func(c: Vector2i) -> bool:
		var road := GraphManager.road_at(c)
		return road != -1 and road != gate and GraphManager.get_edges_of(road).size() >= 2, HOUSE_LINK_MAX)


# Tô đường từ nút from_id tới ô gần nhất thỏa is_target, theo BFS 0-1 trên lưới 8 hướng: bước lên ô đã có đường
# tốn 0, ô mới tốn 1 (đỡ hạn mức); tránh ô của điểm. Dừng nếu cần quá max_new ô mới hoặc hết hạn mức.
func _connect(from_id: int, is_target: Callable, max_new: int) -> bool:
	if from_id == -1:
		return false
	var start := GraphManager.cell_of(GraphManager.get_map_node(from_id).pos)
	var cost := {start: 0}
	var prev := {}
	var deque: Array[Vector2i] = [start]
	var goal := Vector2i(-1, -1)
	while not deque.is_empty():
		var c: Vector2i = deque.pop_front()
		if c != start and is_target.call(c):
			goal = c
			break
		for d in NB8:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= Config.GRID_COLS or n.y >= Config.GRID_ROWS or GraphManager._point_cells.has(n):
				continue
			if GraphManager.is_lot_cell(n) or not GraphManager.diagonal_ok(c, n):
				continue  # ô bãi kho, hoặc bước chéo cắt góc công trình
			var step := 0 if GraphManager.road_at(n) != -1 else 1
			var nc: int = cost[c] + step
			if nc > max_new or nc >= int(cost.get(n, 1 << 30)):
				continue
			cost[n] = nc
			prev[n] = c
			if step == 0:
				deque.push_front(n)
			else:
				deque.push_back(n)
	if goal == Vector2i(-1, -1):
		return false
	var path: Array[Vector2i] = []
	var cur := goal
	while cur != start:
		path.push_front(cur)
		cur = prev[cur]
	var last := from_id
	for c in path:
		last = GraphManager.extend_road(last, c)
		if last == -1:
			return false  # hết hạn mức
	return true


func _pick_card(offers: Array) -> void:
	if offers.is_empty():
		return
	for o in offers:
		if o.id == &'road_supply':
			GameManager.choose_card(o.id)
			return
	GameManager.choose_card(offers[0].id)


# Số cạnh đường theo trạng thái khi hết mỗi đợt, để so độ ngập với kỳ vọng.
func _print_states(wave: int) -> void:
	var count := [0, 0, 0]
	for e in GraphManager.get_edge_ids():
		count[GraphManager.get_edge(e).state] += 1
	print('  hết đợt %d: nước %.0f, khô %d, ngập nhẹ %d, ngập sâu %d' % [wave + 1, FloodManager.water_level, count[0], count[1], count[2]])


func _cell(point: int) -> Vector2i:
	return GraphManager.cell_of(GraphManager.get_map_node(point).pos)


# Đường dài nhất trên bản đồ: giữa hai kho.
func _time_find_path() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()
	_build()
	var start := Time.get_ticks_usec()
	for i in 100:
		GraphManager.find_path(0, 1, Types.VehicleType.TRUCK)
	var usec := (Time.get_ticks_usec() - start) / 100.0
	print('find_path: %.0f micro giây mỗi lần, %d nút đường, %d cạnh' % [
		usec, GraphManager.get_road_ids().size(), GraphManager.get_edge_ids().size()])

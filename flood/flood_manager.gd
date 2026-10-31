extends Node

var water_level := 0.0
var _rate := 0.0
var _rising := false
var _accum := 0.0
var _warned := {}

func _ready() -> void:
	if has_node("/root/EventBus"):
		EventBus.game_started.connect(reset)
		EventBus.wave_started.connect(start_wave)
		EventBus.wave_ended.connect(_on_wave_ended)
		EventBus.edge_added.connect(_on_edge_added)

func reset() -> void:
	water_level = 0.0
	_rate = 0.0
	_rising = false
	_accum = 0.0
	_warned.clear()
	if has_node("/root/EventBus"):
		EventBus.water_level_changed.emit(water_level)

func reset_flood() -> void:
	reset()

func start_wave(index: int) -> void:
	if index >= 0 and index < Config.WAVES.size():
		_rate = Config.WAVES[index].water_delta / Config.WAVE_DURATION
		_rising = true

func stop_rising() -> void:
	_rising = false

func _on_wave_ended(_index: int) -> void:
	stop_rising()

func get_water_level() -> float:
	return water_level

func _process(delta: float) -> void:
	if not _rising:
		return
	water_level = minf(water_level + _rate * delta, 100.0)
	_accum += delta
	if _accum >= Config.FLOOD_TICK:
		_accum = 0.0
		if has_node("/root/EventBus"):
			EventBus.water_level_changed.emit(water_level)
		_update_edges()

func _update_edges() -> void:
	if not has_node("/root/GraphManager"):
		return
	for eid in GraphManager.get_edge_ids():
		var e = GraphManager.get_edge(eid)
		if e == null:
			continue
		var s := compute_state(e.elevation)
		if s != e.state:
			GraphManager.set_edge_state(eid, s)
		_check_warning(e)

func _on_edge_added(edge_id: int) -> void:
	if not has_node("/root/GraphManager"):
		return
	var e = GraphManager.get_edge(edge_id)
	if e != null:
		GraphManager.set_edge_state(edge_id, compute_state(e.elevation))

func compute_state(edge_elevation: float) -> int:
	var d := water_level - edge_elevation
	if d < 0.0:
		return Types.EdgeState.DRY
	if d < Config.SHALLOW_MAX:
		return Types.EdgeState.SHALLOW
	return Types.EdgeState.DEEP

func _check_warning(e) -> void:
	if e == null or e.state >= 2 or _rate <= 0.0:
		return
	var threshold: float = e.elevation if e.state == 0 else (e.elevation + Config.SHALLOW_MAX)
	var seconds_left: float = (threshold - water_level) / _rate
	var key := Vector2i(e.id, e.state + 1)
	if seconds_left <= Config.WARNING_SECONDS and not _warned.has(key):
		_warned[key] = true
		if has_node("/root/EventBus"):
			EventBus.flood_warning.emit(e.id, seconds_left)

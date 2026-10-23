extends Node
## DEMO ONLY. Never instance this script into game/main.tscn.
var elapsed: float = 0.0
var last_sos_time: float = -6.0
var spawn_count: int = 0
var scheduled_rescues: Dictionary = {}

func _ready() -> void:
	EventBus.game_started.connect(_reset)

func _reset() -> void:
	elapsed = 0.0
	last_sos_time = -6.0
	spawn_count = 0
	scheduled_rescues.clear()
	RescueManager.marked.clear()

func _process(delta: float) -> void:
	if GameManager.state != Types.GameState.PLAYING:
		return
	elapsed += delta
	if elapsed-last_sos_time > 8.5:
		_spawn()
		last_sos_time = elapsed
	EventBus.water_level_changed.emit(minf(90.0, elapsed*0.13))
	if fmod(elapsed, 22.0) < delta:
		EventBus.flood_warning.emit(12, 4.9)
	for req_id in scheduled_rescues.keys():
		if elapsed > float(scheduled_rescues[req_id]):
			EventBus.sos_rescued.emit(int(req_id), 20)
			EventBus.score_changed.emit(20*int(req_id))
			scheduled_rescues.erase(req_id)

func _spawn() -> void:
	spawn_count += 1
	var req_id: int = spawn_count
	var targets := [2, 4, 7, 5, 9]
	var node_id: int = targets[(req_id-1) % targets.size()]
	var kind: int = 1 if node_id == 5 else req_id % 2
	EventBus.sos_spawned.emit(req_id, node_id, kind, 45.0)
	scheduled_rescues[req_id] = elapsed + 6.5
	# Mimic the assignment event. The actual game decides the vehicle via Dijkstra.
	EventBus.sos_assigned.emit(req_id, req_id)

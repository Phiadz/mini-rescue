extends Node
# EventBus: chỉ khai báo tín hiệu, KHÔNG có logic.
# Không đặt class_name trong file này (vì sẽ đăng ký thành autoload).
# Quy tắc: chỉ module ghi ở cột "Phát" (Tài liệu chốt mục 2.4) được emit tín hiệu.

# --- Module A (Graph) ---
signal edge_added(edge_id: int)
signal edge_removed(edge_id: int)
signal edge_state_changed(edge_id: int, state: int)
signal edge_budget_changed(used: int, limit: int)

# --- Module B (Flood) ---
signal water_level_changed(level: float)
signal flood_warning(edge_id: int, seconds_left: float)

# --- Module C (Rescue) ---
signal sos_spawned(req_id: int, node_id: int, supply: int, time_total: float)
signal sos_assigned(req_id: int, vehicle_id: int)
signal sos_rescued(req_id: int, points: int)
signal sos_failed(req_id: int)
signal vehicle_added(vehicle_id: int, type: int, hub_id: int)
signal vehicle_state_changed(vehicle_id: int, state: int)
signal stock_changed(hub_id: int, supply: int, qty: int)

# --- Module E (Game Manager) ---
signal game_started
signal game_state_changed(state: int)
signal wave_started(index: int)
signal wave_ended(index: int)
signal break_started(seconds: float)
signal reward_offered(options: Array)
signal reward_chosen(reward: int)
signal score_changed(score: int)
signal failed_changed(count: int, max_failed: int)
signal game_won(stats: Dictionary)
signal game_lost(stats: Dictionary)

# Các module khác sẽ phát bằng EventBus.edge_added.emit(id) 
# và lắng nghe bằng EventBus.edge_added.connect(ham_xu_ly)

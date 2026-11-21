extends Node
# Script autoload KHÔNG đặt class_name.
enum EdgeState { DRY, SHALLOW, DEEP }
enum VehicleType { TRUCK, BOAT, MOTORBIKE, CAR }  # MOTORBIKE, CAR: xe dân của từng nhà
enum VehicleState { IDLE, EN_ROUTE, DELIVERING, RETURNING, STRANDED }
enum SupplyType { FOOD, MEDICAL }
enum NodeKind { HUB, DISTRICT, ROAD, WATER }  # WATER: ô sông cho ca-nô (GraphManager, không phải điểm)
enum SosState { PENDING, ASSIGNED, RESCUED, FAILED }
enum GameState { MENU, PLAYING, WAVE_BREAK, PAUSED, WON, LOST }
enum Reward { MORE_EDGES, EXTRA_TRUCK, EXTRA_BOAT, UPGRADE_TRUCK_CAP, UPGRADE_BOAT_CAP }
extends Node
# Script autoload KHÔNG đặt class_name.
enum EdgeState { DRY, SHALLOW, DEEP }
enum VehicleType { TRUCK, BOAT }
enum VehicleState { IDLE, EN_ROUTE, DELIVERING, RETURNING, STRANDED }
enum SupplyType { FOOD, MEDICAL }
enum NodeKind { HUB, DISTRICT }
enum SosState { PENDING, ASSIGNED, RESCUED, FAILED }
enum GameState { MENU, PLAYING, WAVE_BREAK, PAUSED, WON, LOST }
enum Reward { MORE_EDGES, EXTRA_TRUCK, EXTRA_BOAT }

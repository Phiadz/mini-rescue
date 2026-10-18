class_name MapNode extends RefCounted
# Một điểm trên bản đồ: kho (HUB) hoặc khu dân cư (DISTRICT).
var id: int
var name: String
var pos: Vector2
var kind: int = 0          # Types.NodeKind: 0 HUB, 1 DISTRICT
var elevation: float = 0.0 # thang 0-100

class_name MapNode extends RefCounted
# Một điểm trên bản đồ: kho (HUB) hoặc khu dân cư (DISTRICT).
var id: int
var name: String
var pos: Vector2
var kind: int = 0          # Types.NodeKind: 0 HUB, 1 DISTRICT
var elevation: float = 0.0 # thang 0-100
var icon: String = ''      # tên icon trong res://assets/icons/ (không đuôi), NodeLayer của E vẽ; rỗng thì vẽ hình khối
var gate := Vector2i.ZERO  # hướng ô cổng tính từ ô của điểm (bản đồ bật "gates"); ZERO = không có cổng
var parent := -1           # nhà mọc thêm trong ván: id khu mẹ; điểm có sẵn trong bản đồ là -1

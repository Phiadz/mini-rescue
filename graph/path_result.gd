class_name PathResult extends RefCounted
# Kết quả của GraphManager.find_path.
var found := false
var node_ids: Array[int] = []
var edge_ids: Array[int] = []
var cost := 0.0

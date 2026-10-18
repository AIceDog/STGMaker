@tool
extends RefCounted
## 校验消息的可选定位信息。普通运行校验不创建索引；编辑器按稳定 ID 跳转。
static func mark(issues: PackedStringArray, start: int, locations: Variant, collection: String, id: String, scope: Array = [], field: String = "") -> void:
	if locations == null: return
	for index in range(start, issues.size()):
		# 内层阶段 / 节点的位置比外层资源精确，外层补齐时不能覆盖它。
		if not locations.has(index):
			locations[index] = {"collection": collection, "id": id, "scope": scope.duplicate(), "field": field}

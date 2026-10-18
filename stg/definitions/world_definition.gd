@tool
class_name STGWorldDefinition
extends Resource
## 地图只组织入口与解锁；每个战斗关卡继续使用独立时间轴。
@export var locations: Array[STGWorldLocation] = []

func find(id: String) -> STGWorldLocation:
	for location in locations:
		if location != null and location.id == id:
			return location
	return null

func validate(library: STGProject) -> PackedStringArray:
	var errors = PackedStringArray()
	var identifiers = {}
	if locations.is_empty():
		errors.append("世界地图至少需要一个地点")
	for location in locations:
		if location == null:
			errors.append("世界地图存在空地点")
			continue
		if location.id.is_empty() or identifiers.has(location.id):
			errors.append("地图地点 ID 为空或重复：%s" % location.id)
		identifiers[location.id] = true
		if location.title.strip_edges().is_empty():
			errors.append("地图地点 %s 缺少名称" % location.id)
		if not location.map_position.is_finite() or location.reward < 0:
			errors.append("地图地点 %s 的位置或奖励无效" % location.id)
		if library == null or library.find("levels", location.level_id) == null:
			errors.append("地图地点 %s 引用了不存在的关卡：%s" % [location.id, location.level_id])
	for location in locations:
		if location == null:
			continue
		for prerequisite in location.requires_completion:
			if prerequisite == location.id or not identifiers.has(prerequisite):
				errors.append("地图地点 %s 的前置地点无效：%s" % [location.id, prerequisite])
	# 拓扑推进可发现互相等待的解锁环，也发现被该环间接阻塞的地点。
	var reachable = {}
	for _pass in locations.size():
		for location in locations:
			if location == null or reachable.has(location.id):
				continue
			var ready = true
			for prerequisite in location.requires_completion:
				ready = ready and reachable.has(prerequisite)
			if ready:
				reachable[location.id] = true
	for location in locations:
		if location != null and not reachable.has(location.id):
			errors.append("地图地点 %s 的解锁关系无法推进" % location.id)
	return errors

@tool
extends RefCounted
## 将制作库编译为当前游戏实际引用的配置。只读筛选引用闭包，再复制选中配置。
## 未使用的坏资源不会阻止构建，也不会因复制大型无关模板库而拖慢招式预览。
const References = preload("res://stg/definitions/resource_references.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")

static func compile(game: STGGameDefinition) -> Dictionary:
	if game == null or game.library == null or game.world == null or game.player == null:
		return {"issue": "游戏缺少资源库、主角或世界地图定义。"}
	var roots: Array[Dictionary] = []
	var ids = {}
	for location in game.world.locations:
		if location == null or location.id.is_empty() or ids.has(location.id):
			return {"issue": "世界地图存在空地点或重复地点 ID。"}
		ids[location.id] = true
		if not location.level_id.is_empty():
			roots.append({"collection": "levels", "id": location.level_id})
	if roots.is_empty():
		return {"issue": "世界地图至少需要一个战斗关卡入口。"}
	if not game.start_location_id.is_empty() and not ids.has(game.start_location_id):
		return {"issue": "开始地点不存在：" + game.start_location_id}
	for location in game.world.locations:
		for required in location.requires_completion:
			if not ids.has(required):
				return {"issue": location.title + "：解锁条件引用了不存在的地点 " + required}
	roots.append_array(References.collect(game.player).map(func(reference): return {"collection": reference.collection, "id": reference.id}))
	var closure = compile_library(game.library, roots)
	if not closure.issue.is_empty():
		return closure
	# 战斗库已经按引用闭包复制；复制游戏其他字段时不能再次遍历完整制作库。
	var fields: STGGameDefinition = game.duplicate(false)
	fields.library = null
	var result: STGGameDefinition = Copy.copy(fields)
	result.library = closure.library
	var issues = result.validate()
	if not issues.is_empty():
		return {"issue": "\n".join(issues)}
	return {"game": result, "issue": "", "counts": closure.counts}

## 预制体导出同样使用此接口，根可以是子弹、招式、敌人或关卡。
static func compile_library(source: STGProject, roots: Array[Dictionary]) -> Dictionary:
	if source == null:
		return {"issue": "没有可编译的资源库。"}
	if source.schema_version != STGProject.VERSION:
		return {"issue": "资源库不是当前格式。"}
	var prepared = source
	var index = {}
	var duplicate_ids = {}
	for collection in References.COLLECTIONS:
		index[collection] = {}
		for resource in prepared.get(collection):
			if resource == null:
				continue
			if index[collection].has(resource.id):
				duplicate_ids[collection + ":" + resource.id] = true
			index[collection][resource.id] = resource
	var selected = {}
	var pending = roots.duplicate(true)
	while not pending.is_empty():
		var reference: Dictionary = pending.pop_front()
		var collection: String = reference.get("collection", "")
		var id: String = reference.get("id", "")
		var key = collection + ":" + id
		if selected.has(key):
			continue
		if not index.has(collection) or id.is_empty() or not index[collection].has(id):
			return {"issue": "游戏引用缺失：" + key}
		if duplicate_ids.has(key):
			return {"issue": "游戏引用的资源 ID 重复：" + key}
		var resource: Resource = index[collection][id]
		selected[key] = true
		for dependency in References.collect(resource):
			pending.append({"collection": dependency.collection, "id": dependency.id})
	var result = STGProject.create()
	result.schema_version = STGProject.VERSION
	var counts = {}
	# 保留原制作库顺序，确保重复构建生成稳定的内容排列。
	for collection in References.COLLECTIONS:
		for resource in prepared.get(collection):
			if resource != null and selected.has(collection + ":" + resource.id):
				result.get(collection).append(resource)
		counts[collection] = result.get(collection).size()
	# 只复制选中的配置，实例与编辑会话不共享可变资产。
	result = result.snapshot()
	var issues = result.validate()
	if not issues.is_empty():
		return {"issue": "\n".join(issues)}
	return {"library": result, "issue": "", "counts": counts}

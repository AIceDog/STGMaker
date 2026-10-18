@tool
extends RefCounted
const References = preload("res://stg/definitions/resource_references.gd")
## 禁止敌人通过招式或分裂后继递归召唤自己；单个实例的数量上限不代替引用校验。
static func check(project, issues: PackedStringArray, locations: Variant = null) -> void:
	var graph = {}
	for boss in project.bosses:
		if boss == null: continue
		var targets: Array = []
		_collect(project, boss, targets, {})
		graph[boss.id] = targets
	for id in graph:
		if _cycle(id, graph, []):
			var start = issues.size()
			issues.append("召唤敌人引用形成循环：" + id)
			preload("res://stg/definitions/validation_locations.gd").mark(issues, start, locations, "bosses", id)

static func _cycle(id: String, graph: Dictionary, path: Array) -> bool:
	if id in path: return true
	var next = path + [id]
	for child in graph.get(id, []):
		if _cycle(child, graph, next): return true
	return false

static func _collect(project, value: Variant, targets: Array, visited: Dictionary) -> void:
	if not value is Resource or visited.has(value.get_instance_id()): return
	visited[value.get_instance_id()] = true
	for reference in References.collect(value):
		if reference.collection == "bosses":
			if not reference.id in targets: targets.append(reference.id)
		elif reference.collection in ["bullets", "barrages", "behaviors"]:
			_collect(project, project.find(reference.collection, reference.id), targets, visited)

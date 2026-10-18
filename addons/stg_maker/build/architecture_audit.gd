@tool
extends RefCounted
const Policy = preload("res://addons/stg_maker/build/dependency_policy.gd")
const Scripts = preload("res://addons/stg_maker/build/script_dependencies.gd")

static func check() -> PackedStringArray:
	var issues: PackedStringArray = []
	for root in ["res://stg", "res://game/extensions"]: _scan(root, issues)
	_check_definition_cycles(issues)
	return issues

static func _scan(directory: String, issues: PackedStringArray) -> void:
	var folder = DirAccess.open(directory)
	if folder == null: return
	for file in folder.get_files():
		if file.ends_with(".gd"):
			var path = directory.path_join(file)
			issues.append_array(Policy.check_source(path, FileAccess.get_file_as_string(path)))
			for dependency in ResourceLoader.get_dependencies(path):
				var target = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
				var problem = Policy.issue(path, target)
				if not problem.is_empty(): issues.append(path + " → " + target + "：" + problem)
	for child in folder.get_directories():
		if not child.begins_with("."): _scan(directory.path_join(child), issues)

## 资源模型、校验和引用图必须无环，避免类型回指导致加载/释放次序不稳定。
static func _check_definition_cycles(issues: PackedStringArray) -> void:
	var classes = {}
	for entry in ProjectSettings.get_global_class_list():
		if str(entry.path).begins_with("res://stg/definitions/"): classes[str(entry.class)] = entry.path
	var graph = {}
	var directory = DirAccess.open("res://stg/definitions")
	for name in directory.get_files():
		if not name.ends_with(".gd"): continue
		var source = "res://stg/definitions/" + name
		var text = FileAccess.get_file_as_string(source)
		var edges = {}
		for target in Scripts.collect(source, text):
			if target.begins_with("res://stg/definitions/") and target.ends_with(".gd") and target != source: edges[target] = true
		for identifier in Scripts.identifiers(text):
			if classes.has(identifier) and classes[identifier] != source: edges[classes[identifier]] = true
		graph[source] = edges.keys()
	var visited = {}
	for source in graph: _visit_definition(source, graph, [], visited, issues)

static func _visit_definition(source: String, graph: Dictionary, ancestors: Array, visited: Dictionary, issues: PackedStringArray) -> void:
	if source in ancestors:
		issues.append("资产定义依赖形成环：" + " → ".join(ancestors.slice(ancestors.find(source)) + [source]))
		return
	if visited.has(source): return
	visited[source] = true
	for target in graph.get(source, []): _visit_definition(target, graph, ancestors + [source], visited, issues)

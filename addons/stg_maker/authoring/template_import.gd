@tool
extends RefCounted
## 模板导入只准备资源副本；调用者在同一次会话编辑中提交，整套依赖可以一次撤销。
const Copy = preload("res://stg/definitions/config_copy.gd")
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const References = preload("res://stg/definitions/resource_references.gd")

static func copy_bundle(project: STGProject, source: STGProject, collection: String, id: String, id_prefix: String = "") -> Dictionary:
	var state = {"project": project, "source": source, "ids": {}, "entries": [], "issues": PackedStringArray(), "prefix": id_prefix}
	var selected_id = _collect(state, collection, id)
	return {"entries": state.entries if state.issues.is_empty() else [], "selected_id": selected_id, "issues": state.issues}

static func _collect(state: Dictionary, collection: String, id: String) -> String:
	if id.is_empty(): return ""
	var key = collection + "/" + id
	if state.ids.has(key): return state.ids[key]
	if not state.prefix.is_empty() and state.project.find(collection, state.prefix + id) != null:
		return state.prefix + id
	var original = state.source.find(collection, id)
	if original == null:
		state.issues.append("模板引用不存在：" + key)
		return ""
	var item: Resource = Copy.copy(original)
	var new_id = Defaults.uid("template") if state.prefix.is_empty() else state.prefix + id
	while state.project.find(collection, new_id) != null or new_id in state.ids.values():
		new_id = Defaults.uid("template")
	item.id = new_id
	item.title = _available_title(state, collection, item.title)
	# 先登记再沿引用递归，允许子弹命中招式再次发射同一种子弹。
	state.ids[key] = new_id
	state.entries.append([collection, item])
	_rewrite(state, item)
	return new_id

static func _available_title(state: Dictionary, collection: String, title: String) -> String:
	var titles = {}
	for item in state.project.get(collection): titles[item.title] = true
	for entry in state.entries:
		if entry[0] == collection: titles[entry[1].title] = true
	var result = title
	var index = 2
	while titles.has(result):
		result = "%s（%d）" % [title, index]
		index += 1
	return result

static func _rewrite(state: Dictionary, value: Variant) -> void:
	for reference in References.collect(value):
		var id = _collect(state, reference.collection, reference.id)
		if reference.owner is Resource: reference.owner.set(reference.key, id)
		else: reference.owner[reference.key] = id

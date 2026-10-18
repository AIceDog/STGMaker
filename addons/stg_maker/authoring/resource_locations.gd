@tool
extends RefCounted
## 资源位置由稳定 ID 和属性路径组成，显示名称相同也能定位到正确对象。
const References = preload("res://stg/definitions/resource_references.gd")
const Validation = preload("res://stg/definitions/validation.gd")

static func usages(project: STGProject, collection: String, id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind in References.COLLECTIONS:
		for item in project.get(kind):
			if item == null: continue
			_visit(item, [], [], func(scope, field, target_kind, target_id):
				if target_kind == collection and target_id == id:
					result.append({"collection": kind, "id": item.id, "scope": scope.duplicate(), "field": field}))
	return result

static func diagnostics(project: STGProject) -> Array[Dictionary]:
	return Validation.diagnostics(project)

static func _visit(value: Variant, scope: Array, ancestors: Array, found: Callable) -> void:
	if value is Texture2D or value is AudioStream or value is PackedScene or value is Script: return
	if value is Resource:
		if value.get_instance_id() in ancestors: return
		var next = ancestors + [value.get_instance_id()]
		for property in value.get_property_list():
			if property.name == "script" or not property.usage & PROPERTY_USAGE_STORAGE or not References.active_property(value, property.name): continue
			_field(value.get(property.name), property.name, scope, next, found)
	elif value is Array:
		for index in value.size(): _visit(value[index], scope + [index], ancestors, found)
	elif value is Dictionary:
		for key in value: _field(value[key], key, scope, ancestors, found)

static func _field(value: Variant, key: Variant, scope: Array, ancestors: Array, found: Callable) -> void:
	if References.FIELDS.has(key) and value is String and not value.is_empty():
		found.call(scope, str(key), References.FIELDS[key], value)
	else:
		_visit(value, scope + [key], ancestors, found)

static func caption(project: STGProject, location: Dictionary) -> String:
	var collection: String = location.get("collection", "")
	if not collection in References.COLLECTIONS: return "项目整体配置"
	var item = project.find(collection, location.get("id", ""))
	if item == null: return References.LABELS[collection] + " · 资源已不存在"
	var parts: Array[String] = [References.LABELS[collection], item.title]
	var target: Variant = item
	var scope: Array = location.get("scope", [])
	for key in scope:
		if target == null: continue
		if target is Array:
			if not key is int or key < 0 or key >= target.size(): break
			target = target[key]
			if target is Resource and target.get("title") is String:
				parts.append("%d. %s" % [key + 1, target.title])
		else:
			target = target.get(key)
	return " › ".join(parts)

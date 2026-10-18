@tool
extends RefCounted
## 所有能力复用同一个元数据表单；每次提交读取当前快照，支持撤销后的继续编辑。
const Catalog = preload("res://addons/stg_maker/authoring/extension_catalog.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const Factory = preload("res://stg/definitions/definition_factory.gd")

static func slot(host, box, scope: Array, key: String, kind: String, title: String, optional: bool = true) -> void:
	build(box, kind, title, host.session.project, func(): return host.config_at(scope).get(key), func(value, rebuild): host.edit_path(scope, key, value, rebuild), optional)

static func build(box, kind: String, title: String, library: STGProject, get_binding: Callable, change: Callable, optional: bool = true) -> void:
	var binding: STGExtensionBinding = get_binding.call()
	var selected = binding.definition if binding != null else null
	var available = Catalog.list_definitions(kind)
	if selected != null and not available.has(selected): available.append(selected)
	var ids: Array = [""]
	var names: Array = ["使用内置逻辑" if optional else "请选择扩展"]
	for item in available:
		ids.append(_key(item))
		names.append(item.title)
	var selector = F.select(box, title, _key(selected), ids, names, func(identifier):
		var definition: STGExtensionDefinition
		for candidate in available:
			if _key(candidate) == identifier: definition = candidate; break
		change.call(null if definition == null else Factory.extension_binding(definition), true))
	F.help(selector, "选择技术策划提供的能力模块。\n参数随当前资产保存；预览和正式游戏使用相同实现。")
	if selected == null: return
	if not selected.help.is_empty(): F.note(box, selected.help)
	var issues = selected.validate_fields()
	if not issues.is_empty():
		for issue in issues: F.note(box, "扩展定义需要修正：" + issue)
		return
	var parameters = selected.parameters_with_defaults(binding.parameters)
	for field in selected.fields:
		var key = str(field.name)
		var label = str(field.get("label", key))
		var update = func(value):
			var current: STGExtensionBinding = get_binding.call()
			if current == null or current.definition != selected: return
			var next: STGExtensionBinding = Copy.copy(current)
			next.parameters[key] = value
			change.call(next, false)
		var control
		match str(field.type):
			"float", "int":
				var value = parameters.get(key)
				if not STGExtensionDefinition._finite_number(value): value = field.default
				control = F.number(box, label, float(value), update, float(field.get("min", -100000)), float(field.get("max", 100000)), float(field.get("step", 1 if field.type == "int" else 0.1)))
			"bool":
				var value = parameters.get(key)
				control = F.toggle(box, label, value if typeof(value) == TYPE_BOOL else field.default, update)
			"string": control = F.text(box, label, str(parameters.get(key, "")), update)
			"resource_id":
				var entries: Array = library.get(field.collection) if library != null else []
				var keys: Array = [""]
				var labels: Array = ["请选择资源"]
				for entry in entries:
					if entry != null: keys.append(entry.id); labels.append(entry.title)
				var value = str(parameters.get(key, ""))
				if not value in keys: keys.append(value); labels.append("引用已丢失：" + value)
				control = F.select(box, label, value, keys, labels, update)
		if control != null: F.help(control, str(field.get("help", "")))
	for issue in selected.validate(binding.parameters, kind): F.note(box, "配置需要修正：" + issue)

static func effects(host, parent, scope: Array, bullet: STGAttackLifecycle) -> void:
	var box = F.fold(parent, "脚本命中效果", not bullet.hit_effects.is_empty(), "bullet.effects")
	F.note(box, "命中后依次执行；基础伤害和现有命中招式仍按各自配置生效。")
	for index in bullet.hit_effects.size():
		var row = F.group(box, "效果 %d" % (index + 1))
		build(row, "effect", "效果模块", host.session.project, func(): return host.config_at(scope).hit_effects[index], func(value, rebuild):
			R.edit(host, scope, func(target, _project): target.hit_effects[index] = value)
			if rebuild: host.refresh(true), false)
		F.button(row, "删除效果", func(): R.edit(host, scope, func(target, _project): target.hit_effects.remove_at(index)))
	F.button(box, "＋ 添加命中效果", func(): R.edit(host, scope, func(target, _project): target.hit_effects.append(STGExtensionBinding.new())))

static func _key(definition: STGExtensionDefinition) -> String:
	if definition == null: return ""
	return definition.resource_path if not definition.resource_path.is_empty() else "@" + str(definition.get_instance_id())

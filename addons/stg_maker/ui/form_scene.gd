@tool
extends RefCounted
## 表单场景的查找与缩放。绑定键独立于文字和节点路径，布局可在 Godot 中调整。
const DIRECTORY = "res://addons/stg_maker/ui/forms/"

static func root_of(parent: Node) -> Node:
	var node = parent
	while node != null:
		if node.get_meta("form_dynamic_zone", false): return null
		if node.get_meta("form_root", false): return node
		node = node.get_parent()
	return null

static func lookup(parent: Node, kind: String, title: String) -> Control:
	var root = root_of(parent)
	var key = str(parent.get_meta("form_scope", "")) + "/" + kind + ":" + title
	var control: Control = root.get_meta("form_registry").get(key)
	assert(control != null, "表单场景缺少绑定：" + key + "（" + root.scene_file_path + "）")
	control.show()
	return control

static func part(field: Node, key: String) -> Control:
	if field.get_meta("form_part", "") == key: return field
	for node in field.find_children("*", "Control", true, false):
		if node.get_meta("form_part", "") == key: return node
	assert(false, "表单组件缺少角色：" + key)
	return null

static func snapshot(node: Control) -> void:
	var entries = []
	for control in [node] + node.find_children("*", "Control", true, false):
		control.set_meta("authored_control", true)
		var overrides = {}
		for property in control.get_property_list():
			var key = str(property.name)
			if key.begins_with("theme_override_constants/") or key.begins_with("theme_override_font_sizes/") or key.begins_with("theme_override_styles/"):
				var value = control.get(key)
				if value != null: overrides[key] = value.duplicate(true) if value is Resource else value
		entries.append({"node": control, "minimum": control.custom_minimum_size, "overrides": overrides})
	node.set_meta("form_design", entries)

static func open(host, parent: Node, name: String) -> Control:
	var view: Control = load(name if name.begins_with("res://") or name.begins_with("user://") else DIRECTORY + name + ".tscn").instantiate()
	view.theme = null # 实际工坊继承已缩放的主题，设计场景本身保留可预览的主题。
	var registry = {}
	for node in view.find_children("*", "Control", true, false):
		if node.has_meta("form_key"):
			var key = str(node.get_meta("form_key"))
			assert(not registry.has(key), "重复表单绑定：" + key)
			registry[key] = node
			for alias in node.get_meta("form_aliases", []):
				assert(not registry.has(alias), "重复表单别名：" + str(alias))
				registry[alias] = node
			node.hide()
	view.set_meta("form_registry", registry)
	snapshot(view)
	parent.add_child(view)
	view.set_meta("form_host", host)
	apply_display(view, host.get_meta("display_unit", 1.0), host.Display)
	return view

static func fragment(name: String, parent: Node) -> Control:
	var field: Control = load(DIRECTORY + "components/" + name + ".tscn").instantiate()
	field.set_meta("form_fragment", true)
	snapshot(field)
	parent.add_child(field)
	return field

static func apply_display(view: Control, unit: float, display) -> void:
	if is_equal_approx(view.get_meta("form_unit", -1.0), unit): return
	view.set_meta("form_unit", unit)
	for entry in view.get_meta("form_design", []):
		if not is_instance_valid(entry.node): continue
		var control: Control = entry.node
		control.custom_minimum_size = entry.minimum * unit
		for key in entry.overrides:
			var value = entry.overrides[key]
			control.set(key, display.scale_style(value, unit) if value is StyleBox else roundi(value * unit))

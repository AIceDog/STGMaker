@tool
extends RefCounted
## UI 的编辑命令接口；只修改会话快照，不操作运行节点。结构变化后由 Studio 刷新选择。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const PrefabRoot = preload("res://stg/runtime/prefab_root.gd")
const ConfigPath = preload("res://addons/stg_maker/authoring/config_path.gd")
const LevelCommands = preload("res://addons/stg_maker/ui/level_commands.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const TemplateImport = preload("res://addons/stg_maker/authoring/template_import.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")

static func add_template(host, source: STGProject, id: String) -> void:
	var collection: String = host.collection
	var bundle = TemplateImport.copy_bundle(host.session.project, source, collection, id)
	if not bundle.issues.is_empty():
		host.message("无法导入模板：\n" + "\n".join(bundle.issues))
		return
	host.inspector_dirty = true
	host.selected_id = bundle.selected_id
	host.reset_selection()
	host.session.edit(func(project):
		for entry in bundle.entries: project.get(entry[0]).append(entry[1]))

static func set_field(host, path: Array, key: String, value, rebuild: bool = false) -> void:
	host.edit_configuration(path, func(target, _project): target.set(key, Copy.copy(value)), rebuild, key)

static func add(host, template: String = "moving") -> void:
	host.inspector_dirty = true
	var item: Resource
	var dependencies: Array = []
	match host.collection:
		"obstacles": item = Defaults.obstacle()
		"levels": item = LevelCommands.create_level(host, template, dependencies)
		"waves": item = LevelCommands.create_wave(host, template == "obstacle_wave", dependencies)
		"bullets": item = Defaults.bullet(template)
		"behaviors":
			item = Defaults.flow()
			item.id = Defaults.uid("behavior")
			item.title = "新行为子流程"
		"barrages":item=Defaults.barrage("",template)
		"bosses":item=Defaults.boss()
	if item == null: return
	host.selected_id = item.id
	host.reset_selection()
	host.session.edit(func(project):
		for entry in dependencies: project.get(entry[0]).append(entry[1])
		project.get(host.collection).append(item))

static func duplicate(host) -> void:
	if host.current() == null: return
	var item = Copy.copy(host.current())
	item.id = Defaults.uid("copy")
	item.title += " 副本"
	host.inspector_dirty = true
	host.selected_id = item.id
	host.inspected_key = host.collection + "/" + item.id # 副本保留当前属性页，便于继续调整。
	host.session.edit(func(project): project.get(host.collection).append(item))

static func remove(host) -> void:
	var id: String = host.selected_id
	var issue = removal_issue(host.session.project, host.collection, id)
	if not issue.is_empty():
		host.message(issue)
		return
	host.inspector_dirty = true
	host.session.edit(func(project):
		var entries = project.get(host.collection)
		for i in range(entries.size() - 1, -1, -1):
			if entries[i].id == id:
				entries.remove_at(i))

static func removal_issue(project: STGProject, collection: String, id: String) -> String:
	if id.is_empty(): return "先选择要删除的资源。"
	var callers = References.users(project, collection, id)
	if callers.is_empty(): return ""
	var caller = callers[0]
	return "%s正在被%s「%s」使用，请先更换引用。" % [References.LABELS[collection], References.LABELS[caller.collection], caller.asset.title]

static func edit_list(host, path: Array, operation: String, factory: Callable, selected: int, move_to: int = -1) -> void:
	var items = host.config_at(path)
	if operation != "add" and (selected < 0 or selected >= items.size()):
		return
	var issue = _list_edit_issue(host, path, operation, items, selected)
	if not issue.is_empty():
		host.message(issue)
		return
	host.inspector_dirty = true
	# 所有元素与关联 ID 在一个 next 快照里修改；恢复选择只写工作台状态。
	host.edit_configuration(path, func(target, _project):
		match operation:
			"add": target.append(factory.call())
			"copy": target.insert(selected + 1, _copy_list_item(target[selected]))
			"remove":
				var keep_last = not _can_remove_last(host.current(), path)
				if target.size() > 1 or not keep_last:
					target.remove_at(selected)
					if path == ["phases"]:
						target[0].enter_hp = 100
			"move":
				if move_to >= 0 and move_to < target.size():
					var item = target.pop_at(selected)
					target.insert(move_to, item)
	)
	_restore_list_selection(host, path, operation, selected, move_to)

static func _list_edit_issue(host, path: Array, operation: String, items: Array, selected: int) -> String:
	if str(path[-1]) == "events" and operation == "remove":
		var owner_segment = ConfigPath.resolve(host.current(), path.slice(0, path.size() - 1))
		var rule = owner_segment.exit_rule
		if rule.mode != "time" and rule.condition == "defeat_target" and rule.target_event_id == items[selected].id:
			return "请先更换阶段的击败目标，再删除这个事件。"
	if path == ["phases"] and operation == "add" and host.current().phases[-1].enter_hp <= 1:
		return "最低血量阶段已到 1%，请先调整最后一个阶段的阈值。"
	return ""

static func _can_remove_last(resource: Resource, path: Array) -> bool:
	if path[-1] in ["events", "background_layers"]:
		return true
	return false

static func _copy_list_item(item: Resource) -> Resource:
	var copy = Copy.copy(item)
	if copy is STGLevelSegment:
		copy.id = Defaults.uid("segment")
		var event_ids = {}
		for event in copy.events:
			var old_id = event.id
			event.id = Defaults.uid("event")
			event_ids[old_id] = event.id
		# 击败目标属于复制后的阶段，不能继续引用原阶段的事件。
		copy.exit_rule.target_event_id = event_ids.get(copy.exit_rule.target_event_id, copy.exit_rule.target_event_id)
	elif copy is STGLevelEvent:
		copy.id = Defaults.uid("event")
	return copy

static func _restore_list_selection(host, path: Array, operation: String, selected: int, move_to: int) -> void:
	var selected_index = selected
	var root = host.config_at(path)
	if operation == "add": selected_index = root.size() - 1
	elif operation == "copy": selected_index = selected + 1
	elif operation == "move" and move_to >= 0 and move_to < root.size(): selected_index = move_to
	selected_index = clampi(selected_index, 0, root.size() - 1)
	if str(path[-1]) == "events":
		host.event_id = root[selected_index].id if not root.is_empty() else ""
		return
	match path[0]:
		"projectile": host.stage_index = selected_index
		"phases":
			host.phase_index = selected_index
			host.flow_node_id = ""
		"segments":
			host.segment_index = selected_index
			host.event_id = ""
		"background_layers": host.background_index = selected_index

static func export_prefab(host, path: String) -> String:
	var compiled = Compiler.compile_library(host.session.project, [{"collection": host.collection, "id": host.selected_id}])
	if not compiled.issue.is_empty(): return "导出前请修复配置：\n" + compiled.issue
	var node = Node2D.new()
	node.set_script(PrefabRoot)
	node.name = "LevelPrefab" if host.collection in ["levels", "waves", "obstacles"] else ("BossPrefab" if host.collection == "bosses" else "AttackPrefab")
	node.library = compiled.library
	node.kind = host.collection
	node.resource_id = host.selected_id
	var scene = PackedScene.new()
	var error = scene.pack(node) # Godot 内置：把节点打包为可复用场景
	if error == OK: error = ResourceSaver.save(scene, path)
	node.free()
	return "" if error == OK else "导出失败：" + error_string(error)

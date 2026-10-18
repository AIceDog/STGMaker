extends SceneTree
## 同名资源、内嵌步骤和跨资源引用都通过稳定位置导航；折叠和定位不生成制作历史。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const Locations = preload("res://addons/stg_maker/authoring/resource_locations.gd")
const Tools = preload("res://addons/stg_maker/ui/resource_tools.gd")
const Structure = preload("res://addons/stg_maker/authoring/document_structure.gd")
const Section = preload("res://addons/stg_maker/ui/form_section.gd")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 8: await process_frame

func find(node: Node, predicate: Callable):
	if predicate.call(node): return node
	for child in node.get_children():
		var found = find(child, predicate)
		if found != null: return found
	return null

func all_sections(node: Node) -> Array:
	var result = []
	if node.get_script() == Section: result.append(node)
	for child in node.get_children(): result.append_array(all_sections(child))
	return result

func run() -> void:
	var project = STGProject.create()
	D.populate(project)
	var wave = D.wave(project.bosses[0].id)
	project.waves.append(wave)
	var level = D.level(wave.id)
	project.levels.append(level)
	check(project.validate().is_empty(), "定位测试使用合法的完整资源库")
	var skill = project.barrages[0]
	var twin = Copy.copy(skill)
	twin.id = D.uid("barrage")
	twin.title = skill.title
	project.barrages.append(twin)
	skill.projectile.bullet_id = "missing_bullet"
	twin.projectile.motion_stages[0].duration = -1
	level.segments[0].events[0].at = level.segments[0].duration + 1
	var errors = Locations.diagnostics(project)
	var messages = PackedStringArray()
	for error in errors: messages.append(error.message)
	check(messages == project.validate(), "带定位校验和普通运行校验使用相同规则与消息顺序")
	var missing = errors.filter(func(item): return item.get("id", "") == skill.id and item.get("scope", []) == ["projectile"])
	check(not missing.is_empty(), "第二个发射组的无效引用指向精确组索引")
	var motion = errors.filter(func(item): return item.get("id", "") == twin.id and item.get("scope", []) == ["projectile", "motion_stages", 0])
	check(not motion.is_empty(), "同名招式按ID区分，内联运动问题指向当前组步骤")
	var event = errors.filter(func(item): return item.get("id", "") == level.id and item.get("scope", []) == ["segments", 0, "events", 0])
	check(not event.is_empty(), "关卡问题包含阶段和出场事件路径")
	var usages = Locations.usages(project, "bullets", twin.projectile.bullet_id)
	check(usages.any(func(item): return item.id == twin.id and item.scope == ["projectile"] and item.field == "bullet_id"), "使用位置保留调用方ID、组与字段")
	check(usages.any(func(item): return item.id == twin.id), "同名调用方分别列出")
	for usage in usages:
		check(not Locations.caption(project, usage).is_empty(), "混合字符串和数字路径可生成中文位置说明")
	check(Locations.usages(project, "bullets", "unused").is_empty(), "未使用素材列表为空")
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://diagnostics_ui.cfg"
	studio.show_trajectories = false
	root.add_child(studio)
	await settle()
	var preview_id = studio.selected_id
	studio.canvas.seek_preview(0.4)
	while studio.canvas.is_seeking(): studio.canvas._advance_seek()
	var preview_time = studio.canvas.world.time
	studio.select_inspector_tab(1)
	check(is_equal_approx(studio.canvas.world.time, preview_time), "切换生命周期属性页保留预览时间")
	check(studio.canvas.world.actors.any(func(actor): return actor.get_meta("source_skill", "") == preview_id), "实际子弹保留招式来源")
	for i in 200:
		if not studio.canvas.trajectory.running: break
		studio.canvas.trajectory.advance(240, 0)
	studio.session.project = project
	studio.show_collection("barrages", skill.id)
	await settle()
	studio.set_process(false)
	var history = studio.session.undo_stack.size()
	check(Tools.navigate(studio, {"collection": "barrages", "id": twin.id, "scope": ["projectile", "motion_stages", 0]}), "问题跳转成功")
	await settle()
	check(studio.selected_id == twin.id and studio.stage_index == 0, "定位同名招式及正确飞行步骤")
	check(studio.session.project == project and studio.session.undo_stack.size() == history, "定位不复制配置或进入撤销历史")
	check(Tools.navigate(studio, event[0]), "关卡事件问题可跳转")
	await settle()
	check(studio.collection == "levels" and studio.event_id == level.segments[0].events[0].id and studio.inspector_tab == 0, "定位到事件属性页")
	var sections = all_sections(studio.inspector)
	check(not sections.is_empty(), "事件属性有父级分组")
	check(sections.all(func(item): return item.collapsible and item.heading is Button), "所有父级属性分组均可折叠")
	Tools.set_expanded(studio.inspector, false)
	check(sections.all(func(item): return not item.expanded), "全部收起覆盖所有层级")
	studio.refresh(true)
	await settle()
	check(all_sections(studio.inspector).all(func(item): return not item.expanded), "属性刷新保留父级折叠状态")
	Tools.set_expanded(studio.inspector, true)
	check(all_sections(studio.inspector).all(func(item): return item.expanded), "一键展开所有层级")
	check(studio.session.undo_stack.size() == history, "折叠父级不进入撤销栈")
	var boss = project.bosses[0]
	boss.phases.clear()
	studio.show_collection("bosses", boss.id)
	await settle()
	check(not Structure.issue(studio.current()).is_empty(), "空敌人阶段可保留为待修复草稿")
	var repair = find(studio.inspector, func(node): return node is Button and node.text == "补齐缺失结构（可撤销）")
	check(repair != null, "空结构提供明确修复操作")
	if repair != null: repair.pressed.emit()
	await settle()
	check(studio.current().phases.size() == 1 and Structure.issue(studio.current()).is_empty(), "显式补齐后可以继续编辑")
	check(studio.session.undo_stack.size() == history + 1, "结构补齐只有一次撤销")
	studio.undo_edit()
	await settle()
	check(studio.current().phases.is_empty(), "可撤销回原始未完成结构")
	studio.queue_free()
	for i in 12: await process_frame
	print("PLANNER DIAGNOSTICS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

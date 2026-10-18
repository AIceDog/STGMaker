extends SceneTree
## 真控件多选、整批事务、阶段归属与只读目标账本验收。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const Timing = preload("res://stg/definitions/level_timing.gd")
const Selection = preload("res://addons/stg_maker/ui/timeline_selection.gd")
const Tools = preload("res://addons/stg_maker/ui/timeline_tools.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(title)
func settle() -> void:
	for i in 8: await process_frame
func mouse(control: Control, at: Vector2, pressed: bool, additive: bool = false) -> void:
	var event = InputEventMouseButton.new()
	event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.ctrl_pressed = additive
	control._gui_input(event)
func click(control: Control, at: Vector2, additive: bool = false) -> void:
	mouse(control, at, true, additive); mouse(control, at, false, additive)
func drag(control: Control, from: Vector2, to: Vector2) -> void:
	mouse(control, from, true)
	var event = InputEventMouseMotion.new(); event.position = to; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	control._gui_input(event); mouse(control, to, false)
func find_event(level: STGLevelDefinition, id: String):
	for segment in level.segments:
		for event in segment.events:
			if event.id == id: return event
	return null
func advance(world, duration: float) -> void:
	for i in ceili(duration / STGSimulation.STEP): world.step()
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/timeline_efficiency_" + name + "_actual.png")

func run() -> void:
	root.size = Vector2i(1600, 1000)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false; studio.settings_path = "user://timeline_efficiency.cfg"
	root.add_child(studio); await settle(); studio.set_process(false)
	studio.session.create(); await settle()
	var enemy = D.boss(); enemy.phases.resize(1)
	var wave = D.wave(enemy.id); wave.count = 1; wave.interval = 0
	var level = D.level(wave.id)
	level.segments[0].duration = 4; level.segments[0].events[0].at = 0.5
	level.segments[0].exit_rule.mode = "time"
	var second = D.level_event(wave.id, 1.5); level.segments[0].events.append(second)
	var middle = D.level_segment(wave.id); middle.duration = 6; middle.events[0].at = 1; middle.exit_rule.mode = "time"
	var last = D.level_segment(wave.id); last.duration = 3; last.events[0].at = 2; last.exit_rule.mode = "time"
	level.segments.append(middle); level.segments.append(last)
	studio.session.edit(func(project): project.bosses.append(enemy); project.waves.append(wave); project.levels.append(level))
	studio.switch_collection("levels", level.id); await settle()
	var timeline = studio.level_timeline
	var first_id: String = studio.current().segments[0].events[0].id
	var second_id: String = second.id
	var history: int = studio.session.undo_stack.size()
	click(timeline, timeline.event_rect(0, first_id).get_center())
	click(timeline, timeline.event_rect(0, second_id).get_center(), true)
	check(timeline.selected_event_ids.has(first_id) and timeline.selected_event_ids.has(second_id), "Ctrl 点击保留两个出场事件")
	check(studio.session.undo_stack.size() == history, "选择不修改资源或历史")
	await shot("selection")
	timeline.set_snap_interval(0.5)
	var origin: Vector2 = timeline.event_rect(0, first_id).get_center()
	var grab: float = origin.x - timeline.time_x(0.5)
	drag(timeline, origin, Vector2(timeline.time_x(5.07) + grab, origin.y)); await settle()
	check(studio.current().segments[0].events.is_empty() and studio.current().segments[1].events.size() == 3, "同阶段多条事件一起跨阶段，移除不跳项")
	check(is_equal_approx(find_event(studio.current(), first_id).at, 1) and is_equal_approx(find_event(studio.current(), second_id).at, 2), "以拖动事件吸附，另一条保留一秒间距并保存阶段内时间")
	check(studio.session.undo_stack.size() == history + 1, "多选拖动只有一个撤销事务")
	studio.undo_edit(); await settle()
	check(studio.current().segments[0].events.size() == 2 and is_equal_approx(find_event(studio.current(), first_id).at, 0.5), "一次撤销恢复整批归属和时间")
	check(timeline.selected_event_ids.size() == 2, "撤销后稳定事件 ID 保持多选")
	var end_id: String = studio.current().segments[2].events[0].id
	var bounded = Selection.plan(studio.current(), [first_id, end_id], 500)
	check(is_equal_approx(bounded.delta, 1) and is_equal_approx(bounded.moves[1].at, 3), "批量向右到边界统一停止，不把事件逐条挤在末端")
	var lower = Selection.plan(studio.current(), [first_id, end_id], -500)
	check(is_equal_approx(lower.delta, -0.5) and is_equal_approx(lower.moves[1].at, 1.5), "批量向左统一停止并保留时间间距")
	var no_move = Selection.plan(studio.current(), [first_id], 0)
	check(no_move.moves[0].from == no_move.moves[0].to, "零位移保持原阶段归属")
	timeline.clear_selection()
	var a: Rect2 = timeline.event_rect(0, first_id)
	var b: Rect2 = timeline.event_rect(0, second_id)
	drag(timeline, Vector2(minf(a.position.x, b.position.x) - 3, minf(a.position.y, b.position.y) - 2), Vector2(maxf(a.end.x, b.end.x) + 3, maxf(a.end.y, b.end.y) + 2))
	check(timeline.selected_event_ids.has(first_id) and timeline.selected_event_ids.has(second_id), "从空白处框选真实出场矩形")
	check(studio.session.undo_stack.size() == history, "框选不产生历史")
	click(timeline, timeline.event_rect(0, second_id).get_center(), true)
	check(not timeline.selected_event_ids.has(second_id) and timeline.selected_event_ids.has(first_id), "Ctrl 再次点击取消单条选择")
	timeline.set_snap_interval(0)
	check(is_equal_approx(timeline.snapped_time(1.234), 1.23), "关闭吸附保留百分之一秒时间精度")
	# 目标在跨阶段前整批预检，不能先移动可移动的条，再拒绝其余条。
	studio.session.edit(func(project):
		var segment = project.find("levels", level.id).segments[0]
		segment.exit_rule.mode = "condition"; segment.exit_rule.condition = "defeat_target"; segment.exit_rule.target_event_id = first_id)
	await settle(); history = studio.session.undo_stack.size()
	var moved: bool = studio.LevelCommands.move_events(studio, [second_id, first_id], 5, second_id)
	check(not moved and studio.session.undo_stack.size() == history and studio.current().segments[0].events.size() == 2, "整批包含禁止跨阶段的击败目标时，所有条均保持原位置")
	studio.message_dialog.hide()
	check(studio.session.project.validate().is_empty(), "批量移动与拒绝后项目仍合法")
	studio.test_level(false)
	for i in ceili(0.7 / STGSimulation.STEP): studio.canvas.step_preview()
	studio.update_preview_ui(); await settle()
	if studio.condition_debug != null:
		var section = studio.condition_debug.get_child(1)
		section.heading.button_pressed = true
		var tree: Tree = studio.condition_debug.get_meta("tree")
		if tree.get_root() != null and tree.get_root().get_first_child() != null: tree.get_root().get_first_child().collapsed = false
		await settle()
		var ancestor = studio.condition_debug.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(studio.condition_debug)
			ancestor = ancestor.get_parent()
		await shot("condition")
	studio.queue_free(); await settle()
	await test_goal_snapshot()
	print("TIMELINE EFFICIENCY RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_goal_snapshot() -> void:
	var project = STGProject.create(); D.populate(project)
	var enemy = project.bosses[0]; enemy.phases.resize(1)
	var idle = D.action(); idle.windup = 0; idle.recovery = 0; idle.duration = 20
	enemy.phases[0].behavior_flow = D.flow([idle]); enemy.entity_settings = D.entity_settings()
	var wave = D.wave(enemy.id); wave.count = 3; wave.interval = 0.25; wave.counts_for_clear = false
	project.waves.append(wave)
	var level = D.level(wave.id); level.segments[0].duration = 1
	level.segments[0].events[0].at = 0.05
	level.segments[0].exit_rule.mode = "time_and_condition"; level.segments[0].exit_rule.condition = "defeat_all"
	project.levels.append(level)
	var world = STGLevelSimulation.new(); root.add_child(world); world.reset(project, "levels", level.id)
	check(world.issue.is_empty(), "调试验收使用合法的真实运行器")
	var snapshot: Dictionary = world.goals.inspect(world)
	check(snapshot.pending == 3 and snapshot.alive == 0 and snapshot.events.size() == 1, "尚未触发的整个编队全部计为待生成，全部击败不依赖清场开关")
	check(is_equal_approx(world.time, 0) and world.goals.records.is_empty(), "只读快照不会触发出场、推进时间或生成结果记录")
	advance(world, 0.06); snapshot = world.goals.inspect(world)
	check(snapshot.pending == 2 and snapshot.alive == 1, "真实生成任务反映首个存活实例与两个未生成成员")
	check(snapshot.events[0].instances[0].id == world.entities[0].instance_id, "调试对象编号对应真实实体")
	world.damage_entity(world.entities[0].instance_id, 100); world.step()
	snapshot = world.goals.inspect(world)
	check(snapshot.defeated == 1 and snapshot.alive == 0 and snapshot.pending == 2, "首个成员击败后仍保留两个尚未生成的目标")
	check(world.entities.is_empty() and snapshot.events[0].instances[0].reason == "died", "节点回收后永久结果账本仍提供真实死亡对象")
	snapshot.events[0].instances[0].reason = "changed_snapshot"
	check(world.goals.records.values()[0].reason == "died", "调用方更改快照不会改写真实账本")
	advance(world, 0.25)
	var second_id: int = world.entities[0].instance_id
	world.entities[0].resolve("timeout"); world.step(); snapshot = world.goals.inspect(world)
	check(snapshot.departed == 1 and snapshot.defeated == 1 and snapshot.pending == 1 and snapshot.alive == 0, "超时离场与真实击败分别计数，剩余编队成员仍待生成")
	check(snapshot.blocked == world.goals.evaluate(world).get("blocked", "") and snapshot.blocked.contains("已离场"), "不可达成原因直接复用实际目标判定，不在界面另算推进规则")
	var debug = Tools.build_debug(root)
	Tools.update_debug(debug, world)
	check(debug.visible and debug.get_meta("summary").text.contains("离场 1"), "条件调试面板显示真实汇总")
	var tree: Tree = debug.get_meta("tree")
	var item = tree.get_root().get_first_child(); item.collapsed = false
	Tools.update_debug(debug, world)
	check(not item.collapsed and item.get_child_count() == 3, "重复刷新保留调试树展开状态并展示待生成与已回收对象")
	var seen_timeout = false
	for child in item.get_children():
		if child.get_text(0) == "实例 #%d" % second_id and child.get_text(1) == "超时离场": seen_timeout = true
	check(seen_timeout, "离场对象显示实际原因和实例编号")
	advance(world, 0.3)
	var third = world.entities[0]
	third.simulation.emit_projectile(project.barrages[0].id, Vector2(100, 100), 0, third.simulation.allocate_owner())
	third.resolve("escaped")
	snapshot = world.goals.inspect(world)
	check(snapshot.defeated == 1 and snapshot.departed == 2 and snapshot.finishing == 1 and snapshot.remaining_attacks == 1, "已离场但旧攻击尚未收尾的来源与剩余攻击分别显示")
	check(snapshot.events[0].instances[-1].finishing, "攻击收尾状态关联到原始实例编号")
	debug.free(); world.free()

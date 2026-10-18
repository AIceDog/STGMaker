extends SceneTree
## 完整时间轴的制作验收：真实控件拖动、跨阶段归属、资源拖放、条件表单和实体定义。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const Timing = preload("res://stg/definitions/level_timing.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func settle() -> void:
	for i in 10: await process_frame
func mouse(control: Control, at: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new(); event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	control._gui_input(event)
func drag(control: Control, from: Vector2, to: Vector2) -> void:
	mouse(control, from, true)
	var event = InputEventMouseMotion.new(); event.position = to; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	control._gui_input(event); mouse(control, to, false)
func option(node: Node, title: String) -> OptionButton:
	if node is OptionButton:
		for i in node.item_count:
			if node.get_item_text(i) == title: return node
	for child in node.get_children():
		var found = option(child, title)
		if found != null: return found
	return null
func menu_action(studio, id: int) -> void:
	for control in studio.toolbar.get_children():
		if control is MenuButton and control.text == "项目": control.get_popup().id_pressed.emit(id)

func run() -> void:
	root.size = Vector2i(1440, 1000)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false; studio.settings_path = "user://timeline_checks.cfg"
	root.add_child(studio); await settle(); studio.set_process(false)
	# 通过通用打开项目检查时间轴和资源文档。
	studio.open_project("res://presets/timeline_demo.tres"); studio.switch_collection("levels")
	await settle()
	check(studio.collection == "levels" and studio.session.project.schema_version == STGProject.VERSION and not studio.session.project.levels.is_empty(), "通用打开项目读取新版整关时间轴")
	studio.message_dialog.hide()
	menu_action(studio, 3); await settle(); studio.message_dialog.hide()
	check(studio.collection == "bosses" and studio.current() is STGBossDefinition and not studio.session.file_path.is_empty(), "当前敌人库打开后切到敌人页并保留文档路径")
	studio.open_project("res://presets/level_demo.tres"); studio.switch_collection("levels"); await settle(); studio.message_dialog.hide()
	check(studio.collection == "levels" and studio.current() is STGLevelDefinition and not studio.session.file_path.is_empty(), "当前关卡库打开后切到关卡页并保留文档路径")
	studio.session.create(); await settle()
	var enemy = D.boss(); enemy.title = "追踪测试敌人"
	var obstacle = D.obstacle()
	var wave = D.wave(enemy.id); wave.count = 3; wave.interval = 0.3
	var rock = D.wave(obstacle.id, true)
	var level = D.level(wave.id); level.title = "整关时间轴验收"
	level.segments[0].duration = 4; level.segments[0].events[0].at = 0.5
	var middle = D.level_segment(rock.id); middle.duration = 6; middle.events[0].at = 0.2
	var last = D.level_segment(wave.id); last.duration = 3; last.events[0].at = 1
	level.segments.append(middle); level.segments.append(last)
	studio.session.edit(func(project):
		project.bosses.append(enemy); project.obstacles.append(obstacle)
		project.waves.append(wave); project.waves.append(rock); project.levels.append(level))
	studio.switch_collection("levels", level.id); await settle()
	var timeline = studio.level_timeline
	check(timeline.geometry.segments.size() == 3 and timeline.geometry.events.size() == 3, "完整时间轴同时展示三个阶段的事件")
	check(studio.inspector_tab == 1 and studio.event_id.is_empty(), "进入关卡先编辑阶段，右侧不自动选中别的事件")
	check(timeline.event_rect(1, middle.events[0].id).position.x > timeline.event_rect(0, level.segments[0].events[0].id).position.x, "阶段内时间映射到整关计划坐标")
	check(studio.palette_panel.visible and studio.level_palette.item_count >= 3, "关卡左侧提供敌人、编队、障碍拖放资源")
	studio.timeline_zoom.value = 4; await settle()
	check(timeline.zoom_factor == 4 and timeline.size.x > studio.timeline_scroll.size.x * 3, "缩放增加真实时间轴宽度并支持横向滚动")
	studio.timeline_scroll.scroll_horizontal = 200
	check(studio.timeline_scroll.scroll_horizontal > 0, "横向滚动不改变事件数据")
	timeline.fit_all(); await settle()
	check(studio.timeline_zoom.value == 1 and studio.timeline_scroll.scroll_horizontal == 0, "显示整关复位缩放和横向滚动")
	var event_id: String = studio.current().segments[0].events[0].id
	var origin: Rect2 = timeline.event_rect(0, event_id)
	var grab: float = origin.get_center().x - timeline.time_x(0.5)
	var history: int = studio.session.undo_stack.size()
	drag(timeline, origin.get_center(), Vector2(timeline.time_x(8) + grab, origin.get_center().y)); await settle()
	check(studio.segment_index == 1 and studio.level_event().id == event_id and is_equal_approx(studio.level_event().at, 4), "拖动出场条跨阶段后保存新归属和阶段内时间")
	check(studio.session.undo_stack.size() == history + 1, "跨阶段拖动只提交一次撤销事务")
	studio.undo_edit(); await settle()
	check(studio.current().segments[0].events[0].id == event_id and is_equal_approx(studio.current().segments[0].events[0].at, 0.5), "撤销跨阶段拖动恢复原阶段和时间")
	var first_id: String = studio.current().segments[0].id
	var stage: Rect2 = timeline.geometry.segments[0]
	drag(timeline, stage.position + Vector2(12, 10), timeline.geometry.segments[2].get_center()); await settle()
	check(studio.current().segments[2].id == first_id and studio.current().segments[2].events[0].id == event_id, "拖动阶段重排时事件跟随阶段整体移动")
	studio.undo_edit(); await settle()
	stage = timeline.geometry.segments[0]
	drag(timeline, Vector2(stage.end.x - 3, stage.get_center().y), Vector2(timeline.time_x(2), stage.get_center().y)); await settle()
	check(is_equal_approx(studio.current().segments[0].duration, 2) and is_equal_approx(studio.current().segments[0].events[0].at, 0.5), "拖动阶段右边缘修改计划长度，后续阶段整体前移")
	studio.undo_edit(); await settle()
	var full_height: float = timeline.custom_minimum_size.y
	timeline.environment_visible = false; timeline.queue_redraw(); await settle()
	check(not timeline.geometry.has("music") and timeline.custom_minimum_size.y < full_height, "背景和音乐轨可以整体折叠")
	timeline.environment_visible = true; timeline.queue_redraw(); await settle()
	var data = {"kind": "obstacles", "id": obstacle.id}
	check(timeline._can_drop_data(Vector2.ZERO, data) and not timeline._can_drop_data(Vector2.ZERO, {"kind": "obstacles", "id": "missing"}), "拖放只接受本项目中可用的出场资源")
	var before_events: int = studio.current().segments[1].events.size()
	timeline._drop_data(Vector2(timeline.time_x(5), 90), data); await settle()
	check(studio.segment_index == 1 and is_equal_approx(studio.level_event().at, 1) and studio.current().segments[1].events.size() == before_events + 1, "障碍拖入时间轴创建单体编队与出场事件")
	check(studio.session.project.find("waves", studio.level_event().wave_id).obstacle_id == obstacle.id, "新事件引用可复用障碍定义")
	studio.undo_edit(); await settle()
	studio.select_level_segment(0)
	var point = studio.canvas.screen(Vector2(220, -70))
	studio.canvas._drop_data(point, {"kind": "bosses", "id": enemy.id}); await settle()
	check(studio.canvas.edit_mode == "level_spawn" and studio.level_event().spawn_position.distance_to(Vector2(220, -70)) < 0.01, "敌人拖入预览画面直接设置本阶段出生点")
	studio.undo_edit(); await settle()
	studio.select_level_segment(2); await settle()
	var modes = option(studio.inspector, STGLevelExitRule.MODE_LABELS[1])
	check(modes != null, "阶段属性提供三种时间与目标关系")
	if modes != null: modes.item_selected.emit(1)
	await settle()
	var conditions = option(studio.inspector, STGLevelExitRule.CONDITION_LABELS[2])
	if conditions != null: conditions.item_selected.emit(2)
	await settle()
	check(studio.level_segment().exit_rule.mode == "condition" and studio.level_segment().exit_rule.condition == "defeat_target" and not studio.level_segment().exit_rule.target_event_id.is_empty(), "表单选择指定击败目标时自动关联有效出场")
	var target_id: String = studio.level_segment().exit_rule.target_event_id
	studio.Commands.edit_list(studio, ["segments"], "copy", func(): return D.level_segment(), 2); await settle()
	check(studio.current().segments.size() == 4 and studio.level_segment().exit_rule.target_event_id != target_id and studio.level_segment().exit_rule.target_event_id == studio.level_segment().events[0].id and studio.session.project.validate().is_empty(), "复制目标阶段为事件和击败目标重建关联，项目仍合法")
	studio.undo_edit(); await settle()
	check(studio.current().segments.size() == 3 and studio.level_segment().exit_rule.target_event_id == target_id and studio.session.project.validate().is_empty(), "撤销目标阶段复制恢复原事件与目标")
	history = studio.session.undo_stack.size()
	studio.Commands.edit_list(studio, ["segments", 2, "events"], "remove", func(): return null, 0)
	check(studio.session.undo_stack.size() == history and studio.level_segment().events[0].id == target_id, "删除阶段击败目标时先提示更换目标，不创建坏配置")
	studio.message_dialog.hide()
	history = studio.session.undo_stack.size()
	studio.LevelCommands.move_event(studio, 2, studio.level_segment().exit_rule.target_event_id, 0, 1)
	check(studio.session.undo_stack.size() == history, "指定目标事件跨阶段移动先提示改目标，避免悬空条件")
	studio.message_dialog.hide()
	studio.test_level(true)
	for i in ceili((studio.level_segment().duration + 1) / STGSimulation.STEP): studio.canvas.step_preview()
	studio.update_preview_ui()
	check(studio.timeline_status.text.contains("实际战斗") and studio.timeline_status.text.contains("已等待"), "预览清楚显示计划进度、实际战斗时间与等待秒数")
	studio.playing = false
	var authoring_waves: int = studio.session.project.waves.size()
	studio.switch_collection("obstacles", obstacle.id); await settle()
	check(studio.canvas.world is STGLevelSimulation and studio.canvas.world.issue.is_empty() and studio.session.project.waves.size() == authoring_waves, "独立障碍预览使用正式运行器且不污染制作编队库")
	studio.edit_path(["entity_settings"], "lifetime", 9, true); await settle()
	check(studio.current().entity_settings.lifetime == 9, "障碍自身生命周期通过定义编辑")
	studio.undo_edit(); await settle()
	check(studio.current().entity_settings.lifetime == 0, "实体规则支持撤销")
	check(studio.session.project.validate().is_empty(), "全部时间轴操作后项目配置保持合法")
	studio.queue_free(); await settle()
	print("LEVEL TIMELINE RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

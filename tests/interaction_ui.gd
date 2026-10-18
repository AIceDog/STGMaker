extends SceneTree
## 用户交互验收：不可用操作先禁用，选择、引用导航和悬停不污染制作历史。
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 10:
		await process_frame

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found = find_button(child, title)
		if found != null:
			return found
	return null

func hover(timeline: Control, at: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = at
	timeline._gui_input(motion)

func run() -> void:
	root.size = Vector2i(1440, 1000)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://interaction_ui_checks.cfg"
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	check(not studio.context_row.visible, "普通资源编辑不显示无效返回行")
	check(studio.workspace_caption.text.contains(studio.current().title), "预览标题明确对应当前资源")
	check(studio.inspector_context.text.contains(studio.current().title), "属性上下文包含当前资源名称")
	check(studio.mode_status.text.contains("已暂停"), "测试时钟状态作为信息显示")
	check(studio.mode_status.mouse_filter in [Control.MOUSE_FILTER_IGNORE, Control.MOUSE_FILTER_PASS] and studio.mode_status.focus_mode == Control.FOCUS_NONE, "状态文字只显示信息与悬停说明，不获取操作焦点")
	check(studio.library_panel.size.x < studio.canvas.size.x, "资源栏保留合理宽度，不挤占主要编辑区域")
	check(studio.toolbar.size.y < studio.library_search.size.y * 2, "常用窗口的项目操作保持紧凑工具行")
	check(studio.delete_button.disabled and studio.delete_button.tooltip_text.contains("Boss"), "被引用的招式先禁用删除并解释引用关系")
	var history = studio.session.undo_stack.size()
	find_button(studio.inspector, "编辑子弹素材 →").pressed.emit()
	await settle()
	check(studio.collection == "bullets" and studio.context_row.visible and studio.back_button.visible, "进入共享子弹显示返回上下文")
	check(studio.back_button.size.x > 100, "引用返回入口保留可读的按钮宽度")
	check(studio.inspector_context.text.contains("›") and studio.inspector_context.tooltip_text.contains("所有使用处"), "共享定义显示调用链与修改影响")
	check(studio.session.undo_stack.size() == history, "引用导航不产生配置历史")
	studio.navigation.go_back(studio)
	await settle()
	check(studio.collection == "barrages" and not studio.context_row.visible, "返回后恢复原资源和导航层级")
	studio.Commands.add(studio, "fan")
	await settle()
	check(not studio.delete_button.disabled, "未被引用的新资源可以直接删除")
	studio.switch_collection("bosses")
	studio.Commands.add(studio, "conditional_boss")
	await settle()
	check(studio.boss_node().kind == "condition" and not studio.flow_editor.copy_button.disabled, "条件节点可按自身类型复制")
	check(studio.flow_editor.copy_button.tooltip_text.contains("节点"), "复制提示明确当前节点")
	var action = studio.boss_flow().nodes.filter(func(node): return node.kind == "action")[0]
	studio.select_flow_node(action.id)
	await settle()
	check(not studio.flow_editor.copy_button.disabled and studio.inspector_caption.text.contains(action.title), "选择动作节点启用复制并同步属性对象")
	studio.switch_collection("barrages", studio.session.project.barrages[0].id)
	studio.set_tool("flight_path")
	await settle()
	check(studio.mode_status.text.contains("编辑") and studio.edit_bar.visible and not studio.playing, "控制点编辑显示独立状态与完成入口")
	find_button(studio.edit_bar, "完成编辑").pressed.emit()
	await settle()
	check(studio.mode_status.text.contains("已暂停") and not studio.edit_bar.visible, "完成编辑恢复预览状态")
	studio.edit_path(["projectile", "motion_stages", 0], "duration", -1)
	await settle()
	check(studio.play_button.disabled and studio.preview_actions.all(func(button): return button.disabled), "配置无效时开始、重测、单步均不可用")
	check(studio.mode_status.text.contains("待调整") and studio.validation_button.visible, "配置错误提供可用的修复原因入口")
	studio.undo_edit()
	await settle()
	check(not studio.play_button.disabled and studio.preview_actions.all(func(button): return not button.disabled), "修复配置后恢复测试操作")
	studio.switch_collection("barrages", studio.session.project.barrages[0].id)
	studio.edit_path(["projectile"], "bullet_id", "missing", true)
	await settle()
	var reference_button = find_button(studio.inspector, "编辑子弹素材 →")
	check(reference_button.disabled and reference_button.tooltip_text.contains("有效"), "失效引用先修复下拉框，不能跳入不存在的页面")
	studio.undo_edit()
	await settle()
	studio.open_project("res://presets/timeline_demo.tres")
	studio.switch_collection("levels")
	await settle()
	var timeline = studio.level_timeline
	check(studio.file_status.get_global_rect().end.y <= root.size.y - 4, "常用关卡窗口同时显示时间轴与保存状态")
	var segment: Rect2 = timeline.geometry.segments[0]
	history = studio.session.undo_stack.size()
	hover(timeline, segment.get_center())
	check(timeline.mouse_default_cursor_shape == Control.CURSOR_DRAG, "阶段中部提示可拖动")
	hover(timeline, Vector2(segment.end.x - 3, segment.get_center().y))
	check(timeline.mouse_default_cursor_shape == Control.CURSOR_HSIZE, "阶段右缘明确提示长度调整")
	var event = studio.level_segment().events[0]
	var event_rect: Rect2 = timeline.event_rect(0, event.id)
	hover(timeline, event_rect.get_center())
	check(timeline.hover_rect == event_rect and timeline.mouse_default_cursor_shape == Control.CURSOR_DRAG, "出场条悬停使用实际可拖动矩形")
	check(studio.session.undo_stack.size() == history, "悬停提示不改配置，不产生历史")
	studio.select_level_event(event.id)
	await settle()
	check(studio.inspector_caption.text.contains(event.title) and studio.inspector_context.text.contains(studio.level_segment().title), "点选出场后右侧显示阶段与事件关系")
	check(studio.mode_status.text.contains("编辑") and studio.edit_bar.visible, "点选出场立即同步出生点编辑状态和完成入口")
	studio.select_inspector_tab(2)
	await settle()
	check(studio.inspector_caption.text == "整关背景 / 音乐", "环境页明确作用于整个关卡")
	studio.select_level_segment(2)
	studio.LevelCommands.set_exit_mode(studio, "condition")
	studio.LevelCommands.set_condition(studio, "defeat_target")
	await settle()
	studio.select_level_event(studio.level_segment().exit_rule.target_event_id)
	await settle()
	# 折叠项内的按钮即使尚未显示，也应明确保护指定击败目标。
	var remove = find_button(studio.inspector, "删除")
	check(remove != null and remove.disabled and remove.tooltip_text.contains("击败目标"), "作为推进目标的出场不能直接删除，并说明修改位置")
	studio.queue_free()
	await settle()
	print("INTERACTION UI RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

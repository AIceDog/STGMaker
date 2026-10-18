extends SceneTree
## 编辑集成：真实 GraphEdit 信号、插入/重连/汇合、历史、路径、目标与导出。
const Commands = preload("res://addons/stg_maker/ui/flow_commands.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func settle() -> void:
	for i in 8: await process_frame
func drag(control, from: Vector2, to: Vector2) -> void:
	var press = InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = from
	control._gui_input(press)
	var motion = InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_LEFT; motion.position = to
	control._gui_input(motion)
	press = InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = false; press.position = to
	control._gui_input(press)
func run() -> void:
	root.size = Vector2i(1440, 900)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false; studio.settings_path = "user://flow_editor_test.cfg"
	root.add_child(studio); studio.set_font_size(0, false); studio.set_ui_scale(0, false); await settle()
	studio.switch_collection("bosses"); await settle()
	check(studio.flow_editor.visible and not studio.canvas.visible and studio.flow_view_button.text == "行为流程", "Boss 默认进入顺序流程画布")
	var flow = studio.boss_flow()
	var first_id: String = flow.entry_id
	var move_id: String = flow.nodes[1].id
	var graph: GraphEdit = studio.flow_editor.graph
	check(graph.is_node_connected("entry", 0, first_id, 0) and graph.is_node_connected(first_id, 0, move_id, 0), "开始仅接第一个动作，动作间顺序连接")
	check(not graph.is_node_connected("entry", 0, move_id, 0), "不再由一个根节点连接全部动作")
	graph.node_selected.emit(graph.get_node(move_id)); await settle()
	check(studio.flow_node_id == move_id and studio.boss_action().movement.mode == "curve", "画布选择显示移动模块")
	studio.set_tool("path"); await settle()
	check(studio.canvas.visible and not studio.flow_editor.visible, "路径编辑自动切换战斗画面")
	var before: Vector2 = studio.boss_action().movement.path.get_point_position(1)
	var point: Vector2 = studio.canvas.screen(studio.canvas.path_origin + before)
	var history: int = studio.session.undo_stack.size()
	drag(studio.canvas, point, point + Vector2(45, -20)); await settle()
	check(studio.boss_action().movement.path.get_point_position(1) != before, "Boss 运动曲线可拖动编辑")
	check(studio.session.undo_stack.size() == history + 1, "完整路径拖动只产生一次历史")
	studio.inspector_dirty = true; studio.session.undo(); await settle()
	check(studio.boss_action().movement.path.get_point_position(1) == before, "撤销恢复运动路径")
	var scope = studio.boss_action_scope() + ["movement"]
	studio.edit_path(scope, "mode", "line", true); await settle(); studio.set_tool("target"); await settle()
	before = studio.boss_action().movement.target
	point = studio.canvas.screen(studio.canvas.handles[0].point)
	drag(studio.canvas, point, point + Vector2(50, 30)); await settle()
	check(studio.boss_action().movement.target != before, "直线终点可视化编辑")
	studio.edit_path(scope, "mode", "teleport", true); studio.edit_path(scope, "target_mode", "world", true); await settle()
	studio.set_tool("target"); await settle(); point = studio.canvas.screen(studio.canvas.handles[0].point)
	drag(studio.canvas, point, studio.canvas.screen(Vector2(130, -80))); await settle()
	check(studio.boss_action().movement.target.is_equal_approx(Vector2(130, -80)), "瞬移共用移动模块目标编辑与坐标换算")
	studio.set_boss_view("flow"); studio.select_flow_node(first_id)
	Commands.add(studio, "condition"); await settle()
	var condition_id: String = studio.flow_node_id
	var alternate_id: String = studio.boss_node().failure_id
	check(studio.boss_flow().find(first_id).next_id == condition_id and studio.boss_node().next_id == move_id, "插入条件保留原有顺序")
	check(studio.boss_flow().find(alternate_id).next_id == move_id and studio.session.project.validate().is_empty(), "条件自动创建另一分支并汇合")
	graph.connection_request.emit(StringName(condition_id), 1, StringName(move_id), 0); await settle()
	check(studio.boss_flow().find(condition_id).failure_id == move_id, "否出口可以连接现有节点")
	check(not studio.session.project.validate().is_empty(), "被断开的分支明确提示孤立，不静默删除用户节点")
	studio.inspector_dirty = true; studio.session.undo(); await settle()
	check(studio.boss_flow().find(condition_id).failure_id == alternate_id and studio.session.project.validate().is_empty(), "撤销恢复分支与合法流程")
	studio.select_flow_node(move_id)
	var graph_node: GraphNode = graph.get_node(move_id)
	before = studio.boss_node().editor_position
	graph_node.position_offset += Vector2(40, 30); graph.end_node_move.emit(); await settle()
	check(studio.boss_node().editor_position != before, "节点画布位置写入配置")
	studio.inspector_dirty = true; studio.session.undo(); await settle()
	check(studio.boss_node().editor_position == before, "节点移动可以撤销")
	var original_path = studio.boss_action().movement.path
	Commands.duplicate_node(studio); await settle()
	var copy_id: String = studio.flow_node_id
	check(copy_id != move_id and studio.boss_flow().find(move_id).next_id == copy_id, "副本插入原动作之后")
	check(studio.boss_action().movement.path != original_path, "副本不共享可编辑运动曲线")
	Commands.remove(studio); await settle()
	check(studio.boss_flow().find(copy_id) == null and studio.session.project.validate().is_empty(), "删除动作自动连接后续步骤")
	Commands.arrange(studio); await settle()
	check(studio.session.project.validate().is_empty(), "自动排列不改变流程规则")
	graph.disconnection_request.emit(StringName("entry"), 0, StringName(first_id), 0); await settle()
	check(not studio.session.project.validate().is_empty(), "断开开始节点阻止无效预览")
	graph.connection_request.emit(StringName("entry"), 0, StringName(first_id), 0); await settle()
	check(studio.session.project.validate().is_empty(), "重连开始节点恢复有效流程")
	studio.phase_index = 1; studio.flow_node_id = ""; studio.refresh(true); await settle()
	check(studio.canvas.world.boss_player.phase_index == 1 and studio.hp_slider.value == 50, "选择血量阶段直接预览对应流程")
	studio.phase_index = 0; studio.flow_node_id = ""; studio.refresh(true); await settle()
	studio.edit_path(["phases", 0], "loop", false); await settle()
	check(studio.Commands.export_prefab(studio, "user://flow_boss.tscn").is_empty(), "组合动作 Boss 可导出真正场景")
	var packed = ResourceLoader.load("user://flow_boss.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var prefab = packed.instantiate(); prefab.autoplay = false; root.add_child(prefab)
	var events: Array = []; prefab.boss_action_event.connect(func(id, event): events.append([id, event]))
	prefab.play(); prefab.set_player(Vector2(5000, 5000))
	for i in 2000: prefab._physics_process(STGSimulation.STEP)
	check(not prefab.running and prefab.simulation.completed, "导出场景独立使用同一流程和动作段运行器")
	check(not events.is_empty(), "外部游戏可以订阅动作生命周期事件")
	prefab.free()
	studio.queue_free(); await settle()
	print("FLOW EDITOR RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

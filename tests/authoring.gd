extends SceneTree
## 编辑集成测试：真实控件输入、历史、共享资源边界与导出场景。
const FlowCommands = preload("res://addons/stg_maker/ui/flow_commands.gd")
const FormSection = preload("res://addons/stg_maker/ui/form_section.gd")
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
var checks = 0
var failures = 0
var finished_count = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func settle() -> void:
	for i in 3: await process_frame
func find_section(node: Node, key: String):
	if node is FormSection and (node.state_key.ends_with("/" + key) or node.title == key): return node
	for child in node.get_children():
		var found = find_section(child, key)
		if found != null: return found
	return null
func mouse(control, position: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.pressed = pressed; control._gui_input(event)
func drag(control, from: Vector2, to: Vector2) -> void:
	mouse(control, from, true)
	var event = InputEventMouseMotion.new(); event.position = to; event.button_mask = MOUSE_BUTTON_MASK_LEFT; control._gui_input(event)
	mouse(control, to, false)
func run() -> void:
	root.size = Vector2i(1440, 900)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://authoring_ui_checks.cfg"
	root.add_child(studio); await settle()
	studio.set_ui_scale(0, false); await settle()
	check(studio.collection == "barrages" and studio.current() is STGBarrageSkill, "启动直接进入攻击库")
	check(not studio.curve_panel.visible and not studio.hp_row.visible, "默认隐藏曲线与 Boss 调试输入")
	studio.switch_collection("bullets"); await settle()
	studio.select_inspector_tab(0); await settle()
	var visuals = find_section(studio.inspector, "外观")
	var history_size: int = studio.session.undo_stack.size()
	check(visuals.indent.visible and studio.session.undo_stack.size() == history_size, "切换属性页不产生项目编辑历史")
	studio.refresh(true); await settle()
	visuals = find_section(studio.inspector, "外观")
	check(visuals.indent.visible and studio.inspector_tab == 0, "刷新当前资源保持属性页")
	studio.select_inspector_tab(1); await settle()
	check(find_section(studio.inspector, "外观") == null, "动画粒子页不重复构建基础几何控件")
	studio.switch_collection("barrages"); await settle()
	studio.set_tool("flight_path")
	var before: Vector2 = studio.motion_stage().path.get_point_position(1)
	var start: Vector2 = studio.canvas.screen(studio.canvas.path_origin + before.rotated(studio.canvas.path_angle))
	drag(studio.canvas, start, start + Vector2(40, -20)); await settle()
	check(studio.motion_stage().path.get_point_position(1) != before, "画布实际拖动写入空间路径")
	check(studio.session.undo_stack.size() == 1, "整次拖动只占一个撤销步骤")
	studio.inspector_dirty = true; studio.session.undo(); await settle()
	check(studio.motion_stage().path.get_point_position(1) == before, "撤销恢复路径")
	studio.session.redo(); await settle()
	check(studio.motion_stage().path.get_point_position(1) != before, "重做恢复编辑")
	studio.open_curve(["projectile", "motion_stages", 0], "visual_scale_curve"); await settle()
	var curve = studio.curve_editor
	start = curve.screen(curve.curve.get_point_position(1))
	drag(curve, start, curve.screen(Vector2(1, 2))); await settle()
	check(is_equal_approx(studio.motion_stage().visual_scale_curve.get_point_position(1).y, 2), "真实鼠标编辑尺寸时间曲线")
	check(studio.session.project.validate().is_empty(), "编辑后的配置合法")
	var original_id = studio.selected_id
	studio.Commands.duplicate(studio); await settle()
	check(studio.selected_id != original_id and studio.current().title.ends_with("副本"), "复制子弹为独立资源")
	studio.edit_path(["projectile", "motion_stages", 0], "speed", 30); await settle()
	check(studio.session.project.find("barrages", original_id).projectile.motion_stages[0].speed != 30, "修改副本不影响原子弹")
	studio.Commands.edit_list(studio, ["projectile", "motion_stages"], "add", func(): return Defaults.stage("aim"), 0); await settle()
	check(studio.current().projectile.motion_stages.size() == 2 and studio.stage_index == 1, "添加阶段后选中新阶段")
	studio.Commands.edit_list(studio, ["projectile", "motion_stages"], "move", func(): return Defaults.stage(), 1, 0); await settle()
	check(studio.current().projectile.motion_stages[0].mode == "aim" and studio.stage_index == 0, "排序后跟随选中阶段")
	studio.switch_collection("barrages"); await settle()
	studio.edit_path(["fire_pattern"], "arrangement", "circle", true); await settle()
	studio.set_tool("spawn")
	start = studio.canvas.screen(studio.canvas.path_origin + Vector2(studio.fire_pattern().radius, 0))
	drag(studio.canvas, start, start + Vector2(30, 0)); await settle()
	check(studio.fire_pattern().radius > 80, "画布拖动出生排列半径")
	studio.edit_path(["fire_pattern"], "count", 12.0); await settle()
	check(studio.fire_pattern().count == 12, "数值控件可修改整数参数")
	studio.switch_collection("bosses"); await settle()
	check(not studio.hp_row.visible and studio.current() is STGBossDefinition, "Boss 页面默认专注独立行为资源，调试血量按需显示")
	studio.set_meta("preview_tools_expanded", true); studio.update_preview_ui()
	check(studio.hp_row.visible, "展开测试工具后可调整 Boss 测试血量")
	FlowCommands.add(studio, "action"); await settle()
	studio.edit_path(studio.boss_action_scope() + ["movement"], "mode", "dash", true); await settle()
	check(studio.boss_action().movement.mode == "dash", "新增树动作可编辑为冲刺")
	studio.edit_path(studio.boss_action_scope() + ["movement"], "mode", "teleport", true); await settle()
	check(studio.boss_action().movement.mode == "teleport", "树特殊动作可编辑")
	check(studio.session.save("user://simple_ui_project.tres").is_empty(), "编辑项目保存")
	check(not studio.session.dirty(), "保存后清除未保存标记")
	check(studio.session.open("user://simple_ui_project.tres").is_empty(), "编辑项目重新打开")
	studio.inspector_dirty = true; await settle()
	check(studio.session.project.validate().is_empty(), "重开后引用与阶段完整")
	studio.switch_collection("barrages"); await settle()
	check(studio.Commands.export_prefab(studio, "user://simple_attack.tscn").is_empty(), "导出真正的 Godot 预制体场景")
	var packed = ResourceLoader.load("user://simple_attack.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "导出文件可加载为 PackedScene")
	var prefab = packed.instantiate(); prefab.autoplay = false; prefab.position = Vector2(100, 200); root.add_child(prefab)
	prefab.finished.connect(func(): finished_count += 1)
	prefab.play(); prefab.set_player(Vector2(5000, 5000))
	check(prefab.simulation.player == Vector2(4900, 4800), "外部玩家世界坐标转换为预制体局部坐标")
	check(not prefab.simulation.editor_markers, "导出场景不显示编辑器玩家与 Boss 标记")
	for i in 800: prefab._physics_process(STGSimulation.STEP)
	check(finished_count == 1 and not prefab.running, "导出场景可独立播放并报告完成")
	prefab.free()
	studio.set_font_size(20, false)
	check(studio.theme.default_font_size == 20, "字号可直接调整")
	studio.queue_free()
	# 完整 UI 含独立弹窗、主题和图节点；让释放与布局通知结束后再关闭测试进程。
	for i in 12: await process_frame
	print("AUTHORING RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

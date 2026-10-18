extends SceneTree
## 关卡制作流程：菜单入口、拖动时间 / 出生点、引用返回、片段复制、撤销和导出。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func settle() -> void:
	for i in 8: await process_frame
func mouse(control, point: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	control._gui_input(event)
func drag(control, from: Vector2, to: Vector2) -> void:
	mouse(control, from, true)
	var event = InputEventMouseMotion.new(); event.position = to; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	control._gui_input(event)
	mouse(control, to, false)
func key(code: int, pressed: bool) -> InputEventKey:
	var event = InputEventKey.new(); event.physical_keycode = code; event.pressed = pressed; return event

func run() -> void:
	root.size = Vector2i(1440, 900)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false; studio.settings_path = "user://level_editor_checks.cfg"
	root.add_child(studio); await settle(); studio.set_process(false)
	# 项目菜单的专用关卡示例入口已按用户要求移除；通过通用打开项目并切到关卡页。
	studio.open_project("res://presets/level_demo.tres")
	studio.switch_collection("levels")
	await settle()
	studio.message_dialog.hide() # 清理提示后继续操作其他对话框。
	check(studio.collection == "levels" and studio.current() is STGLevelDefinition and studio.level_panel.visible, "通用项目打开后切到关卡时间轴")
	check(studio.canvas.world is STGLevelSimulation and studio.inspector_tabs.tab_count == 3, "关卡页使用正式运行器和三个分工清楚的属性页")
	var level_id = studio.selected_id
	studio.select_level_event(studio.level_segment().events[0].id); await settle()
	check(studio.canvas.edit_mode == "level_spawn" and studio.canvas.handles.size() == 1, "选中事件后显示可拖动的编队出生点")
	var origin: Vector2 = studio.level_event().spawn_position
	var start: Vector2 = studio.canvas.screen(origin)
	var history = studio.session.undo_stack.size()
	drag(studio.canvas, start, start + Vector2(-40, 15)); await settle()
	check(studio.level_event().spawn_position != origin and studio.session.undo_stack.size() == history + 1, "一次出生点拖动只提交一个撤销事务")
	studio.undo_edit(); await settle()
	check(studio.level_event().spawn_position == origin, "撤销恢复出生点")
	var event_id = studio.event_id
	var before = studio.level_event().at
	var timeline = studio.level_timeline
	await settle()
	start = timeline.rectangles[event_id].get_center()
	var grab_offset = start.x - timeline.time_x(before)
	drag(timeline, start, Vector2(timeline.time_x(2.0) + grab_offset, start.y)); await settle()
	check(is_equal_approx(studio.level_event().at, 2.0), "时间轴实际鼠标拖动修改事件时间")
	studio.undo_edit(); await settle()
	check(is_equal_approx(studio.level_event().at, before), "撤销恢复出场时间")
	studio.select_inspector_tab(2)
	studio.request_asset("texture", ["background_layers", 1])
	studio.asset_dialog.hide()
	studio.assign_asset("res://assets/enemies/01_swift.svg"); await settle()
	check(studio.current().background_layers[0].texture == null and studio.current().background_layers[1].texture is Texture2D, "背景贴图选择只修改对应层，不误写关卡根资源")
	check(studio.canvas.world.background.definition.background_layers[1].texture is Texture2D, "预览直接使用刚绑定的背景贴图")
	studio.undo_edit(); await settle()
	check(studio.current().background_layers[1].texture == null, "撤销恢复背景层贴图")
	studio.select_inspector_tab(0)
	studio.select_level_segment(1)
	studio.select_level_event(studio.level_segment().events[0].id); await settle()
	event_id = studio.event_id
	studio.edit_reference("waves", studio.level_event().wave_id); await settle()
	check(studio.current() is STGWaveDefinition and not studio.level_panel.visible, "从事件打开编队，不显示关卡时间轴")
	studio.edit_path([], "count", 5, true); await settle()
	studio.navigation.go_back(studio); await settle()
	check(studio.collection == "levels" and studio.selected_id == level_id and studio.segment_index == 1 and studio.event_id == event_id, "返回关卡恢复片段与原事件")
	check(studio.session.project.find("waves", studio.level_event().wave_id).count == 5, "引用编辑结果保留在关卡中")
	studio.Commands.edit_list(studio, ["segments"], "copy", func(): return D.level_segment(), 1); await settle()
	check(studio.current().segments.size() == 4 and studio.session.project.validate().is_empty(), "复制片段创建新 ID，事件和编队引用合法")
	studio.undo_edit(); await settle()
	studio.LevelCommands.add_event(studio); await settle()
	check(studio.level_segment().events.size() == 2 and studio.session.project.validate().is_empty(), "可以给片段添加出场事件")
	studio.LevelCommands.resize_segment(studio, 0.5); await settle()
	check(studio.level_segment().events.all(func(event): return event.at <= 0.5), "缩短片段时调整超出的事件，一次操作保持合法")
	studio.select_level_segment(2); await settle()
	studio.test_level(true)
	check(studio.canvas.world.segment_index == 2 and studio.playing, "从本段测试跳过前面的片段")
	studio.playing = false
	studio.finish_canvas_edit(); studio.canvas.grab_focus(); await settle()
	studio.canvas._gui_input(key(KEY_SPACE, true))
	studio.canvas.step_preview()
	check(not studio.canvas.world.player_shots.shots.is_empty(), "关卡预览接收空格并发射测试子弹")
	studio.asset_list.grab_focus(); await settle(); studio.canvas.control_player(0.1)
	check(not studio.canvas.level_shoot_held, "离开画布释放测试射击，不污染参数输入")
	studio.canvas._gui_input(key(KEY_SPACE, false))
	studio.test_level(false)
	check(studio.canvas.world.segment_index == 0, "从关卡开头测试恢复第一片段")
	studio.playing = false
	check(studio.session.save("user://edited_level.tres").is_empty(), "编辑后的完整关卡项目可以保存")
	check(studio.Commands.export_prefab(studio, "user://edited_level.tscn").is_empty(), "关卡可以导出可实例化场景")
	var prefab = ResourceLoader.load("user://edited_level.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	prefab.autoplay = false; root.add_child(prefab); prefab.set_physics_process(false); prefab.play()
	check(prefab.kind == "levels" and prefab.simulation is STGLevelSimulation and prefab.simulation.issue.is_empty(), "导出的关卡场景正确绑定关卡资源和运行器")
	prefab.stop(); prefab.free()
	studio.session.create(); studio.switch_collection("levels"); await settle()
	studio.Commands.add(studio, "level"); await settle()
	check(studio.current() is STGLevelDefinition and studio.session.project.waves.size() == 1 and studio.session.project.validate().is_empty(), "旧攻击项目可以一键创建关卡并补齐编队依赖")
	studio.undo_edit(); await settle()
	check(studio.session.project.levels.is_empty() and studio.session.project.waves.is_empty(), "一次撤销移除新关卡及自动生成的依赖")
	studio.Commands.add(studio, "three_section"); await settle()
	check(studio.current().segments.size() == 3 and studio.session.project.validate().is_empty(), "普通项目也能创建三段关卡模板")
	studio.queue_free(); await settle()
	print("LEVEL EDITOR RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

extends SceneTree
## 真实工作区导航：一级入口、二级素材、按需测试工具、引用返回和专注模式。
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
var checks = 0
var failures = 0
var studio

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for _frame in 6:
		await process_frame

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://workspace_navigation_checks.cfg"
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	var ui: Dictionary = studio.get_meta(Workspaces.UI_KEY)
	var names: Array[String] = []
	for child in ui.primary.get_children():
		names.append(child.text)
	check(names == ["招式", "敌人", "关卡", "游戏"], "一级导航按制作任务组织")
	check(studio.library_button.button_pressed and ui.attacks.visible, "默认招式工作区显示自己的资源入口")
	check(studio.bullet_button.get_parent() != ui.primary and studio.bullet_button.text == "子弹素材", "子弹素材作为招式内二级入口")
	check(not studio.library_help.visible and not studio.inspector_context.visible and not studio.context_row.visible, "默认不堆叠操作说明和重复上下文")
	check(not ui.advanced_panel.visible and not studio.preview_status.is_visible_in_tree(), "统计和测试工具默认收起")
	check(studio.get_meta("preview_transport").row.visible, "招式工作区直接提供预览时间条")
	check(studio.layout_outer.get_child(0).size.y < 75, "项目操作和主导航保持一条紧凑顶栏")
	var history = studio.session.undo_stack.size()
	studio.bullet_button.pressed.emit()
	await settle()
	check(studio.collection == "bullets" and studio.library_button.button_pressed and studio.bullet_button.button_pressed, "进入素材仍归属招式工作区")
	studio.boss_button.pressed.emit()
	await settle()
	check(studio.collection == "bosses" and not ui.attacks.visible and not ui.levels.visible, "角色工作区隐藏无关的次级入口")
	check(not studio.get_meta("preview_transport").row.visible and not ui.trajectory_button.visible, "角色工作区不显示招式专用的时间条和轨迹开关")
	check(not studio.hp_row.is_visible_in_tree(), "角色测试血量不常驻")
	ui.tools_button.pressed.emit()
	await settle()
	check(ui.advanced_panel.visible and studio.hp_row.is_visible_in_tree(), "展开工具后可调整角色测试血量")
	ui.tools_button.pressed.emit()
	await settle()
	check(not ui.advanced_panel.visible, "测试工具可以一键收起")
	studio.level_button.pressed.emit()
	await settle()
	check(studio.collection == "levels" and ui.levels.visible, "关卡工作区提供关卡、编队与障碍入口")
	ui.level_buttons.waves.pressed.emit()
	await settle()
	check(studio.collection == "waves" and studio.level_button.button_pressed, "二级编队仍归属关卡工作区")
	ui.level_buttons.obstacles.pressed.emit()
	await settle()
	check(studio.collection == "obstacles" and ui.level_buttons.obstacles.button_pressed, "障碍库可从二级入口访问")
	studio.library_button.pressed.emit()
	await settle()
	var id = studio.current().projectile.bullet_id
	studio.edit_reference("bullets", id)
	await settle()
	check(studio.context_row.visible and studio.context_row.get_parent() == studio.library_panel, "引用返回放在资源栏，不挤占整行画布")
	check(studio.inspector_context.visible and not studio.subtitle.visible, "进入引用时才显示完整编辑关系")
	studio.navigation.go_back(studio)
	await settle()
	check(studio.collection == "barrages" and not studio.context_row.visible, "返回原招式恢复上下文")
	check(studio.session.undo_stack.size() == history, "导航与展开工具不写入制作历史")
	var width = studio.canvas.size.x
	studio.display_menu.get_popup().id_pressed.emit(200)
	await settle()
	check(not studio.library_panel.is_visible_in_tree() and not studio.inspector_scroll.is_visible_in_tree() and studio.canvas.size.x > width, "专注工作区隐藏侧栏并放大画布")
	studio.display_menu.get_popup().id_pressed.emit(200)
	await settle()
	check(studio.library_panel.is_visible_in_tree() and studio.inspector_scroll.is_visible_in_tree(), "再次切换恢复资源和属性")
	root.size = Vector2i(1100, 760)
	await settle()
	check(studio.layout_margin.size.x <= studio.size.x + 1 and studio.canvas.size.x >= 320, "较小窗口保持可用画布且布局不溢出")
	ui.game.pressed.emit()
	await settle()
	check(is_instance_valid(studio.game_project_panel) and studio.game_project_panel.visible, "游戏入口打开主角与世界地图设置")
	studio.game_project_panel.dispose()
	await settle()
	studio.queue_free()
	await settle()
	if FileAccess.file_exists("user://workspace_navigation_checks.cfg"):
		DirAccess.remove_absolute("user://workspace_navigation_checks.cfg")
	print("WORKSPACE NAVIGATION RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

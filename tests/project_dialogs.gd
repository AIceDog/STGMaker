@tool
extends EditorPlugin
## 在真实编辑器和原生子窗口中验证恢复提示、模态窗口释放与项目菜单输入。
const Studio = preload("res://addons/stg_maker/ui/studio_workspace.gd")
const Session = preload("res://addons/stg_maker/ui/session.gd")
const FOLDER = "user://project_dialog_checks"
var checks: int = 0
var failures: int = 0

func _enter_tree() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func settle() -> void:
	for frame in 12: await get_tree().process_frame
	# 原生窗口的显示/隐藏还要经过 Windows 消息队列，不能只等待高速空闲帧。
	await get_tree().create_timer(0.2).timeout

func cleanup() -> void:
	var folder = DirAccess.open(FOLDER)
	if folder != null:
		for file in folder.get_files(): DirAccess.remove_absolute(FOLDER.path_join(file))

func recovery_dialog(host: Node) -> AcceptDialog:
	for child in host.get_children():
		if child is AcceptDialog and child.title == "恢复本机草稿" and not child.is_queued_for_deletion(): return child
	return null

func restore_button(node: Node) -> Button:
	if node is Button and node.text == "恢复": return node
	for child in node.get_children():
		var found = restore_button(child)
		if found != null: return found
	return null

func click(window: Window, at: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = at
	window.push_input(motion, true)
	var event = InputEventMouseButton.new()
	event.window_id = window.get_window_id()
	event.position = at
	event.global_position = Vector2(window.position) + at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	window.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	window.push_input(event, true)

func choose(menu: PopupMenu, id: int) -> void:
	menu.set_focused_item(menu.get_item_index(id))
	press_key(menu, KEY_ENTER)

func press_key(window: Window, code: Key) -> void:
	var event = InputEventKey.new()
	event.window_id = window.get_window_id()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func run() -> void:
	await settle()
	cleanup()
	var seed = Session.new()
	seed.recovery_folder = FOLDER
	seed.create()
	seed.edit(func(next): next.barrages[0].title = "未保存的测试招式")
	for index in 12:
		seed.recovery_slot = "dialog_test_%d" % index
		seed.recovery_source = "res://" + "很长的目录名称/".repeat(18) + "%d.tres" % index
		seed.last_recovery_project = null
		check(seed.save_recovery().is_empty(), "准备独立草稿 %d" % index)
	var entries = seed.available_drafts()
	var before = FileAccess.get_sha256(entries[0].path)
	var studio = Studio.new()
	studio.session.recovery_folder = FOLDER
	studio.settings_path = "user://project_dialog_checks_missing.cfg"
	studio.visible = false
	studio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(studio)
	await settle()
	check(recovery_dialog(studio) == null, "隐藏工作区启动时不打开模态恢复窗口")
	check(get_tree().root.get_last_exclusive_window() == get_tree().root, "启动草稿提示不锁住 Godot 主窗口")
	# 旧实现的自动弹窗先显式关闭，以便继续检查手动入口。
	var dialog = recovery_dialog(studio)
	if dialog != null: dialog.hide(); dialog.queue_free()
	studio.show()
	for screen in EditorInterface.get_editor_main_screen().get_children():
		if screen != studio and screen is Control: screen.hide()
	studio.set_font_size(24, false)
	studio.set_ui_scale(200, false)
	await settle()
	studio.show_recovery_drafts()
	await settle()
	dialog = recovery_dialog(studio)
	check(dialog != null and dialog.visible, "手动入口仍能查看草稿")
	if dialog != null:
		var usable = DisplayServer.screen_get_usable_rect(dialog.current_screen)
		check(dialog.size.x <= usable.size.x and dialog.size.y <= usable.size.y, "长路径、多草稿和大字号不会把窗口撑出屏幕")
		check(Rect2(Vector2.ZERO, Vector2(dialog.size)).encloses(dialog.get_ok_button().get_global_rect()), "关闭按钮位于窗口可见范围")
		studio.show_recovery_drafts()
		await settle()
		var count = 0
		for child in studio.get_children():
			if child is AcceptDialog and child.title == "恢复本机草稿" and not child.is_queued_for_deletion(): count += 1
		check(count == 1, "恢复窗口重复请求不会叠加模态窗口")
		# 清理旧实现叠加出的窗口，使关闭与项目输入检查可以独立报告。
		for child in studio.get_children():
			if child is AcceptDialog and child.title == "恢复本机草稿" and child != dialog: child.hide(); child.queue_free()
		RenderingServer.force_draw()
		if "--capture" in OS.get_cmdline_user_args() or OS.has_environment("STG_TEST_CAPTURE"): dialog.get_texture().get_image().save_png("res://tests/project_dialogs_actual.png")
		press_key(dialog, KEY_ENTER)
		await settle()
		check(recovery_dialog(studio) == null and get_tree().root.get_last_exclusive_window() == get_tree().root, "关闭按钮响应回车并释放原生窗口的模态锁")
	studio.set_font_size(0, false)
	studio.set_ui_scale(0, false)
	await settle()
	var menu_button = studio.get_meta(studio.WorkspaceNavigation.UI_KEY).project_menu
	var menu = menu_button.get_popup()
	for pair in [[6, "res://presets/flytiger_enemies.tres"], [3, "res://presets/enemy_library.tres"], [7, "res://presets/flytiger_bosses.tres"]]:
		click(get_tree().root, menu_button.get_global_rect().get_center())
		await settle()
		check(menu.visible, "项目菜单响应鼠标输入：%d" % pair[0])
		choose(menu, pair[0])
		await settle()
		check(studio.session.file_path == pair[1] and not menu.visible, "菜单键盘输入加载项目并正常收起：%d" % pair[0])
		check(get_tree().root.get_last_exclusive_window() == get_tree().root, "切换项目后不遗留模态锁：%d" % pair[0])
	studio.show_recovery_drafts()
	await settle()
	dialog = recovery_dialog(studio)
	restore_button(dialog).grab_focus()
	press_key(dialog, KEY_SPACE)
	await settle()
	check(studio.session.file_path.is_empty() and studio.session.project.barrages[0].title == "未保存的测试招式", "恢复按钮的键盘输入加载草稿并要求另存")
	check(recovery_dialog(studio) == null and get_tree().root.get_last_exclusive_window() == studio.message_dialog, "恢复完成先释放旧模态锁，再显示确认提示")
	press_key(studio.message_dialog, KEY_ENTER)
	await settle()
	check(get_tree().root.get_last_exclusive_window() == get_tree().root, "恢复提示关闭后主窗口继续接收输入")
	check(FileAccess.get_sha256(entries[0].path) == before and seed.available_drafts().size() == 12, "查看、关闭和切换项目不删除或修改恢复草稿")
	studio.queue_free()
	await settle()
	cleanup()
	print("PROJECT DIALOGS RESULT: %d checks, %d failures" % [checks, failures])
	preload("res://tests/editor_shutdown.gd").request(self)

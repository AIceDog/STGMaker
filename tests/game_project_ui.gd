extends SceneTree
## 游戏配置面板的真实控件集成测试；保存仅写专用 user:// 文件，原游戏资源保持只读。
const Fixture = preload("res://tests/game_fixture.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const GameDocument = preload("res://addons/stg_maker/authoring/game_document.gd")
const SAVE = "user://game_project_ui_test.tres"
const SETTINGS = "user://game_project_ui_test.cfg"
const DEFAULT_GAME = "res://game/content/first_game.tres"
var checks = 0
var failures = 0
var studio
var panel

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for _frame in count:
		await process_frame

func controls(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		result.append(child)
		result.append_array(controls(child))
	return result

func field(caption: String, class_type: String) -> Node:
	for node in controls(panel.body):
		if node is Label and node.text == caption:
			var siblings = node.get_parent().get_children()
			var index = siblings.find(node)
			if index + 1 < siblings.size() and siblings[index + 1].is_class(class_type):
				return siblings[index + 1]
	return null

func button(caption: String) -> Button:
	for node in controls(panel):
		if node is Button and node.text == caption:
			return node
	return null

func select_option(caption: String, index: int) -> void:
	var option = field(caption, "OptionButton")
	option.select(index)
	option.item_selected.emit(index)

func set_text(caption: String, value: String) -> void:
	var edit = field(caption, "LineEdit")
	edit.text = value
	edit.text_submitted.emit(value)

func cleanup() -> void:
	for path in [SAVE, SAVE.get_basename() + "_library.tres", SETTINGS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func run() -> void:
	cleanup()
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	var source = ResourceLoader.load(DEFAULT_GAME, "", ResourceLoader.CACHE_MODE_REUSE) as STGGameDefinition
	var source_hash = FileAccess.get_sha256(DEFAULT_GAME)
	var library_path = source.library.resource_path
	var library_hash = FileAccess.get_sha256(library_path) if not library_path.is_empty() and not "::" in library_path else ""
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = SETTINGS
	root.add_child(studio)
	await frames(5)
	studio.set_process(false)
	studio.open_game_configuration()
	await frames(5)
	panel = studio.game_project_panel
	check(panel != null and panel.visible and panel.size.x >= 780 and panel.size.y >= 600, "工作台可以打开游戏配置窗口：%s" % panel.size)
	check(panel.game != source and panel.game.library != source.library, "面板使用深拷贝，不直接编辑成品共享资源")
	check(panel.library_source_path == library_path and not library_path.is_empty(), "打开面板保留外部资源库身份，以便同步编辑器最新修改：%s" % panel.library_source_path)
	check(field("游戏名称", "LineEdit") != null and field("生命格数", "SpinBox") != null and field("进入关卡", "OptionButton") != null, "真实表单提供主角和地图字段")
	check(is_equal_approx(field("移动速度", "SpinBox").value, panel.game.player.move_speed) and is_equal_approx(field("受击判定半径", "SpinBox").value, panel.game.player.hit_radius) and is_equal_approx(field("每发伤害（敌人最大生命百分比）", "SpinBox").value, panel.game.player.shot_damage), "数值显示与配置一致，不被步长起点悄悄偏移")
	for caption in ["使用当前资源库", "保存游戏配置", "完整试玩", "导出独立工程…", "导出 Windows 游戏…"]:
		check(button(caption) != null, "操作入口存在：" + caption)
	# 两个关卡使资源选择切换有实际结果；新建 fixture 不影响成品库。
	var fixture = Fixture.create()
	var next_level: STGLevelDefinition = Copy.copy(fixture.library.levels[0])
	next_level.id = "ui_second_level"
	next_level.title = "UI 第二关"
	fixture.library.levels.append(next_level)
	studio.session.project = fixture.library
	button("使用当前资源库").pressed.emit()
	await frames()
	check(panel.game.library != fixture.library and panel.game.library.levels.size() == 2, "接入当前资源库时使用配置快照")
	check(panel.game.library.find("levels", next_level.id) != null, "当前工作台的新关卡出现在游戏资源库")
	panel.game.world = Copy.copy(fixture.world)
	panel.game.start_location_id = fixture.start_location_id
	panel.selected_location = 0
	panel.refresh()
	await frames()
	set_text("游戏名称", "UI 测试首航")
	field("生命格数", "SpinBox").value = 5
	field("移动速度", "SpinBox").value = 310
	field("射击间隔（秒）", "SpinBox").value = 0.2
	check(panel.game.title == "UI 测试首航" and panel.game.player.max_health == 5 and is_equal_approx(panel.game.player.move_speed, 310), "文本和数值控件提交主角配置：%s / %s / %s" % [panel.game.title, panel.game.player.max_health, panel.game.player.move_speed])
	check(is_equal_approx(panel.game.player.fire_interval, 0.2), "射击间隔控件提交参数")
	set_text("地点名称", "测试海岸")
	set_text("地点说明", "用于验证保存与关卡绑定")
	field("首次通关奖励", "SpinBox").value = 250
	select_option("进入关卡", 1)
	check(panel.game.world.locations[0].title == "测试海岸" and panel.game.world.locations[0].level_id == next_level.id and panel.game.world.locations[0].reward == 250, "地点名称、奖励和关卡选择提交配置")
	select_option("编辑地点", 1)
	await frames()
	check(panel.selected_location == 1 and field("地点名称", "LineEdit").text == "山谷遭遇战", "选择地点后切换对应字段")
	var prerequisite: CheckButton
	for node in controls(panel.body):
		if node is CheckButton and node.text == "测试海岸":
			prerequisite = node
	check(prerequisite != null and prerequisite.button_pressed, "前置条件控件显示已有通关依赖")
	prerequisite.button_pressed = false
	check(panel.game.world.locations[1].requires_completion.is_empty(), "取消前置条件立即更新依赖")
	prerequisite.button_pressed = true
	check(panel.game.world.locations[1].requires_completion == ["coast"], "勾选前置条件保存稳定地点 ID")
	button("添加地点").pressed.emit()
	await frames()
	var added = panel.game.world.locations.back()
	check(panel.game.world.locations.size() == 3 and panel.selected_location == 2 and not added.id.is_empty(), "添加地点创建唯一 ID 并选中")
	check(added.level_id == fixture.library.levels[0].id, "新地点默认引用有效关卡")
	panel.game.world.locations[1].requires_completion.append(added.id)
	button("删除地点").pressed.emit()
	await frames()
	check(panel.game.world.locations.size() == 2 and not panel.game.world.locations[1].requires_completion.has(added.id), "删除地点同时清理引用它的前置条件")
	panel.selected_location = 0
	panel.refresh()
	await frames()
	check(panel.game.validate().is_empty(), "编辑后的完整游戏资源有效")
	var save_issue = panel.save_game(SAVE)
	check(save_issue.is_empty(), "面板保存至专用临时文件：" + save_issue)
	var reloaded = GameDocument.load_definition(SAVE)
	check(reloaded != null and reloaded.validate().is_empty(), "保存后游戏定义和外部资源库可以重新加载")
	check(reloaded.library.resource_path == SAVE.get_basename() + "_library.tres", "另存自动连接对应独立战斗库：%s" % reloaded.library.resource_path)
	check(reloaded.title == "UI 测试首航" and reloaded.player.max_health == 5 and reloaded.world.locations[0].level_id == next_level.id, "保存保留主角和地图编辑结果")
	check(reloaded.get_script() == source.get_script() and reloaded.library.get_script() == fixture.library.get_script(), "刷新配置时复用定义脚本，避免重复加载执行依赖图")
	check(FileAccess.get_sha256(DEFAULT_GAME) == source_hash, "成品 first_game 文件保持不变")
	check(library_hash.is_empty() or FileAccess.get_sha256(library_path) == library_hash, "成品外部资源库保持不变")
	check(fixture.library.levels[0].title == "巡航试炼", "测试工作台配置未被面板反向修改")
	studio.session.file_path = panel.library_source_path
	studio.session.edit(func(next): next.levels[0].title = "工作台最新关卡名称")
	check(panel.game.library.levels[0].title != studio.session.project.levels[0].title, "打开的配置副本确实落后于工作台修改")
	check(panel.save_game(SAVE).is_empty(), "同一资源库的保存自动同步工作台最新快照")
	check(GameDocument.load_definition(SAVE).library.levels[0].title == "工作台最新关卡名称", "自动同步避免旧面板覆盖新编辑内容")
	panel.game.player.fire_interval = 0
	check(panel.save_game(SAVE).is_empty(), "无效的半成品游戏配置仍可保存草稿")
	check(is_zero_approx(GameDocument.load_definition(SAVE).player.fire_interval), "重新加载保留尚未完成的配置，留待继续修复")
	check(not panel.Compiler.compile(panel.game).issue.is_empty(), "试玩编译仍拒绝无效配置")
	var cached = GameDocument.load_definition(SAVE)
	cached.library.levels[0].title = "缓存中未保存的名称"
	check(GameDocument.load_definition(SAVE).library.levels[0].title == "工作台最新关卡名称", "浅层加载也刷新外部库磁盘数据，不误用旧缓存")
	# 子窗口先解除嵌入与弹出状态，再销毁工作台；避免视口仍持有已释放窗口的登记。
	panel.dispose()
	await frames(2)
	panel.queue_free()
	studio.game_project_panel = null
	await frames(2)
	panel = null
	studio.queue_free()
	await frames(8)
	studio = null
	cleanup()
	print("GAME PROJECT UI RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

@tool
extends Window
## 游戏配置窗口：把战斗资源库连接到主角和地图；游戏执行与构建各有独立模块。
const Assets = preload("res://addons/stg_maker/authoring/asset_store.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Builder = preload("res://addons/stg_maker/build/project_builder.gd")
const GameShell = preload("res://game/game_shell.gd")
const GameDocument = preload("res://addons/stg_maker/authoring/game_document.gd")
const Drafts = preload("res://addons/stg_maker/authoring/draft_store.gd")
var disk_revision: Dictionary = {}
var host: Control
var game: STGGameDefinition
var game_path: String = ""
var library_source_path: String = ""
var selected_location: int = 0
var body: VBoxContainer
var status: Label
var save_dialog: FileDialog
var build_dialog: FileDialog
var release_dialog: FileDialog
var disposing: bool = false
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var revision: int = 0
var saved_revision: int = 0
var revision_counter: int = 0
var undo_button: Button
var redo_button: Button
var close_dialog: ConfirmationDialog
var recovery_dialog: ConfirmationDialog
var recovery_timer: Timer
var recovery_folder: String = Drafts.ROOT
var recovery_source: String = ""
var recovery_slot: String = ""
var last_recovery_revision: int = -1
var recovery_offer: Dictionary = {}
var synced_editor_project: STGProject
var close_after_save: bool = false

func open_for(workspace: Control) -> void:
	host = workspace
	if game_path.is_empty():
		game = STGGameDefinition.new()
		game.library = host.session.project.snapshot()
		game.player = STGPlayerDefinition.new()
		game.world = STGWorldDefinition.new()
		library_source_path = host.session.file_path
		synced_editor_project = host.session.project
		saved_revision = -1
	else:
		var loaded = GameDocument.load_definition(game_path)
		if not loaded is STGGameDefinition:
			host.message("游戏配置不存在：" + game_path)
			queue_free()
			return
		disk_revision = Assets.capture(game_path)
		library_source_path = loaded.library.resource_path if loaded.library != null else ""
		game = Copy.copy(loaded)
	title = "游戏配置 · 主角与世界地图"
	min_size = Vector2i(780, 600)
	close_requested.connect(request_close)
	set_meta("section_states", {})
	set_meta("section_context", "game")
	if host.session != null: recovery_folder = host.session.recovery_folder
	recovery_source = game_path
	recovery_slot = Drafts.new_slot(game_path)
	var background = ColorRect.new()
	background.color = Color("14202e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var outer = VBoxContainer.new()
	margin.add_child(outer)
	F.note(outer, "资源库定义战斗内容；地图选择关卡，主角配置控制玩家。保存后可完整试玩或导出游戏。")
	var actions = HFlowContainer.new()
	outer.add_child(actions)
	undo_button = F.button(actions, "撤销", undo)
	F.help(undo_button, "撤销本窗口上一次主角、地图或资源库接入修改。\n与工作台资源库的撤销分别记录。")
	redo_button = F.button(actions, "重做", redo)
	F.help(redo_button, "恢复本窗口刚才撤销的修改。")
	F.help(F.button(actions, "使用当前资源库", use_current_library), "把工作台当前的制作库接入这个游戏配置，\n不替换工作台中的项目。\n请重新检查各地图地点引用的关卡；\n保存游戏配置后才写入文件。")
	F.help(F.button(actions, "保存游戏配置", func(): save_dialog.popup_centered_ratio(0.65), "primary"), "保存本窗口的主角、地图和配套战斗资源库。\n与工作台的“保存项目”分别保存；\n试玩和导出会读取本窗口当前配置。")
	F.help(F.button(actions, "完整试玩", preview, "primary"), "运行当前配置的菜单、地图、关卡与结算完整流程，\n不自动保存配置文件。\n试玩使用独立进度存档，不混入正式游戏进度。")
	F.help(F.button(actions, "导出独立工程…", func(): build_dialog.popup_centered_ratio(0.65)), "生成可独立用 Godot 打开的游戏工程，\n包含当前地图引用的关卡与运行依赖，\n不包含 STGMaker 编辑器代码。\n选择输出目录后开始构建。")
	F.help(F.button(actions, "导出 Windows 游戏…", func(): release_dialog.popup_centered_ratio(0.65)), "导出可以直接运行的 Windows 游戏，\n不包含 STGMaker 工作台。\n需要当前 Godot 版本的 Windows 导出模板；\n选择 .exe 保存位置后构建。")
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	status = F.note(outer, "")
	F.help(status, "显示游戏配置的保存位置或最近一次操作结果。\n主角与地图配置保存在游戏资源中，玩家通关进度另存。")
	_dialogs()
	refresh()
	popup_centered(Vector2i(1050, 780))
	_offer_recovery.call_deferred()

func _dialogs() -> void:
	save_dialog = FileDialog.new()
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.tres ; 游戏配置"])
	save_dialog.current_path = ProjectSettings.globalize_path(game_path if not game_path.is_empty() else "res://game/content/my_game.tres")
	add_child(save_dialog)
	save_dialog.file_selected.connect(func(path):
		var issue = save_game(ProjectSettings.localize_path(path))
		report(issue, "游戏配置草稿已保存；试玩与导出时检查完整配置。")
		if issue.is_empty() and close_after_save: hide()
		close_after_save = false)
	save_dialog.canceled.connect(func(): close_after_save = false)
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "游戏配置尚未保存"
	close_dialog.dialog_text = "保存主角与地图修改后关闭，或保留本机恢复草稿后关闭。"
	close_dialog.ok_button_text = "保存后关闭"
	close_dialog.cancel_button_text = "继续编辑"
	close_dialog.add_button("保留草稿并关闭", false, "keep_draft")
	add_child(close_dialog)
	close_dialog.confirmed.connect(func():
		close_after_save = true
		save_dialog.popup_centered_ratio(0.65))
	close_dialog.custom_action.connect(func(action):
		if action == "keep_draft":
			var issue = save_recovery()
			if issue.is_empty():
				close_dialog.hide()
				hide()
			else: report(issue, ""))
	recovery_timer = Timer.new()
	recovery_timer.one_shot = true
	recovery_timer.wait_time = 2.0
	add_child(recovery_timer)
	recovery_timer.timeout.connect(func():
		var issue = save_recovery()
		if not issue.is_empty(): status.text = issue)
	recovery_dialog = ConfirmationDialog.new()
	recovery_dialog.title = "发现游戏配置恢复草稿"
	recovery_dialog.ok_button_text = "恢复草稿"
	recovery_dialog.cancel_button_text = "稍后处理"
	add_child(recovery_dialog)
	recovery_dialog.confirmed.connect(func():
		var issue = recover_draft(recovery_offer.path)
		if not issue.is_empty(): report(issue, ""))
	build_dialog = FileDialog.new()
	build_dialog.access = FileDialog.ACCESS_FILESYSTEM
	build_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	add_child(build_dialog)
	build_dialog.dir_selected.connect(func(path):
		_sync_editor_library()
		var result = Builder.build(game, path)
		report(result.issue, "独立游戏工程已导出：\n" + path))
	release_dialog = FileDialog.new()
	release_dialog.access = FileDialog.ACCESS_FILESYSTEM
	release_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	release_dialog.filters = PackedStringArray(["*.exe ; Windows 游戏"])
	release_dialog.current_file = "STGMakerGame.exe"
	add_child(release_dialog)
	release_dialog.file_selected.connect(export_windows)

func refresh() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	F.text(body, "游戏名称", game.title, func(value): edit(func(): game.title = value))
	F.help(F.note(body, "战斗资源库：%d 个关卡 · %d 个敌人 / Boss。使用当前资源库会替换本游戏引用的内容。" % [game.library.levels.size(), game.library.bosses.size()]), "这是本游戏当前引用的战斗库统计；地图只能选择该库中的关卡。工作台编辑了另一份库时，需要先“使用当前资源库”接入。")
	var player = F.group(body, "主角")
	F.number(player, "生命格数", game.player.max_health, func(value): edit(func(): game.player.max_health = int(value)), 1, 99, 1)
	F.number(player, "移动速度", game.player.move_speed, func(value): edit(func(): game.player.move_speed = value), 1, 2000, 1)
	F.number(player, "受击判定半径", game.player.hit_radius, func(value): edit(func(): game.player.hit_radius = value), 0.1, 50, 0.1)
	F.number(player, "射击间隔（秒）", game.player.fire_interval, func(value): edit(func(): game.player.fire_interval = value), 0.02, 5, 0.01)
	F.number(player, "子弹速度", game.player.shot_speed, func(value): edit(func(): game.player.shot_speed = value), 1, 3000, 1)
	F.number(player, "每发伤害（敌人最大生命百分比）", game.player.shot_damage, func(value): edit(func(): game.player.shot_damage = value), 0.1, 100, 0.1)
	F.number(player, "子弹存活时间（秒）", game.player.shot_lifetime, func(value): edit(func(): game.player.shot_lifetime = value), 0.1, 10, 0.1)
	var modules = F.fold(player, "自定义主角能力", game.player.controller != null or game.player.weapon != null or game.player.ability != null, "player.extensions")
	for pair in [["controller", "移动控制"], ["weapon", "射击武器"], ["ability", "主动技能"]]:
		var slot: String = pair[0]
		preload("res://addons/stg_maker/ui/extension_fields.gd").build(F.group(modules, pair[1]), "player", pair[1], game.library, func(): return game.player.get(slot), func(value, rebuild): edit(func(): game.player.set(slot, value), rebuild))
	F.note(modules, "技能输入：X / K；模块与主角参数一起保存，可随时撤销。")
	var world = F.group(body, "世界地图 · 地点连接独立战斗关卡")
	F.help(world, "地图地点是进入战斗关卡的入口。\n地点位置、关卡引用和通关前置都属于游戏配置，\n不改变关卡内的出场事件。")
	var location_ids: Array = []
	var location_names: Array = []
	for location in game.world.locations:
		location_ids.append(location.id)
		location_names.append(location.title)
	F.help(F.select(world, "起始地点", game.start_location_id, location_ids, location_names, func(value): edit(func(): game.start_location_id = value)), "设置新游戏起始使用的地图地点；与下面“编辑地点”的属性选择互相独立。")
	selected_location = clampi(selected_location, 0, game.world.locations.size() - 1)
	if not game.world.locations.is_empty():
		F.help(F.select(world, "编辑地点", game.world.locations[selected_location].id, location_ids, location_names, func(value):
			selected_location = location_ids.find(value)
			refresh()), "选择下面要修改的地图地点；只切换编辑对象，不改变游戏起始地点。")
	var operations = HBoxContainer.new()
	world.add_child(operations)
	F.help(F.button(operations, "添加地点", add_location), "在当前世界地图新增一个独立地点，然后在下方选择进入的关卡与解锁前置；需保存游戏配置。")
	var remove = F.button(operations, "删除地点", remove_location, "danger")
	remove.disabled = game.world.locations.size() <= 1
	F.help(remove, "地图至少保留一个地点。" if remove.disabled else "删除当前编辑地点，并移除其他地点对它的解锁依赖；不删除它引用的战斗关卡。需保存游戏配置。")
	if not game.world.locations.is_empty():
		_location_fields(world, game.world.locations[selected_location])
	status.text = "保存位置：" + game_path + "\n地图地点通过稳定 ID 连接；通关记录保存在独立玩家存档中。"
	_update_state()

func _location_fields(parent: Node, location: STGWorldLocation) -> void:
	var identifier = location.id
	F.help(F.note(parent, "地点 ID：" + location.id), "地点的稳定标识，用于解锁条件和玩家通关记录。\n修改地点名称会保留这个 ID；\n删除后重建会成为新地点。")
	F.text(parent, "地点名称", location.title, func(value): edit(func(): game.world.find(identifier).title = value))
	F.text(parent, "地点说明", location.description, func(value): edit(func(): game.world.find(identifier).description = value))
	var level_ids: Array = []
	var level_names: Array = []
	if game.library.find("levels", location.level_id) == null:
		level_ids.append(location.level_id)
		level_names.append("请选择有效关卡")
	for level in game.library.levels:
		level_ids.append(level.id)
		level_names.append(level.title)
	F.help(F.select(parent, "进入关卡", location.level_id, level_ids, level_names, func(value): edit(func(): game.world.find(identifier).level_id = value)), "玩家从这个地点进入的独立战斗关卡，来自本游戏的战斗资源库；选择引用，不复制或修改关卡内容。")
	F.help(F.number(parent, "地图横坐标", location.map_position.x, func(value): edit(func(): game.world.find(identifier).map_position.x = value), -10000, 10000, 0.01), "改变这个地点在世界地图中的水平布局位置；不是战斗画面坐标，不影响关卡出生点。")
	F.help(F.number(parent, "地图纵坐标", location.map_position.y, func(value): edit(func(): game.world.find(identifier).map_position.y = value), -10000, 10000, 0.01), "改变这个地点在世界地图中的垂直布局位置；不是战斗画面坐标，不影响关卡出生点。")
	F.help(F.number(parent, "首次通关奖励", location.reward, func(value): edit(func(): game.world.find(identifier).reward = int(value)), 0, 999999, 1), "玩家首次通关这个地图地点时发放的奖励数量；重复挑战不重复领取，领取记录保存在玩家存档中。")
	F.note(parent, "解锁前置：勾选需要先通关的地点；不勾选则初始开放。")
	for other in game.world.locations:
		if other.id == location.id:
			continue
		F.help(F.toggle(parent, other.title, other.id in location.requires_completion, func(enabled):
			edit(func():
				var current = game.world.find(identifier)
				if enabled and other.id not in current.requires_completion:
					current.requires_completion.append(other.id)
				elif not enabled:
					current.requires_completion.erase(other.id))), "把“%s”设为当前地点“%s”的通关前置。\n勾选的地点需要全部通关；\n清空所有勾选则初始开放。" % [other.title, location.title])

func use_current_library() -> void:
	edit(func():
		game.library = host.session.project.snapshot()
		library_source_path = host.session.file_path
		synced_editor_project = host.session.project, true)
	status.text = "已接入当前编辑中的资源库。请确认每个地图地点的关卡引用，再保存游戏配置。"

func add_location() -> void:
	edit(func():
		var location = STGWorldLocation.new()
		location.id = "location_%s" % Time.get_ticks_usec()
		location.map_position = Vector2(game.world.locations.size(), 0)
		if game.world.locations.is_empty(): game.start_location_id = location.id
		if not game.library.levels.is_empty(): location.level_id = game.library.levels[0].id
		game.world.locations.append(location)
		selected_location = game.world.locations.size() - 1, true)

func remove_location() -> void:
	if game.world.locations.size() <= 1: return
	edit(func():
		var identifier = game.world.locations[selected_location].id
		game.world.locations.remove_at(selected_location)
		for location in game.world.locations: location.requires_completion.erase(identifier)
		if game.start_location_id == identifier: game.start_location_id = game.world.locations[0].id, true)

func save_game(path: String) -> String:
	_sync_editor_library()
	var library_path = path.get_basename() + "_library.tres"
	var issue = Assets.save_game(game, path, library_path, disk_revision if path == game_path else {})
	if not issue.is_empty(): return issue
	disk_revision = Assets.capture(path)
	game.library.take_over_path(library_path)
	game.take_over_path(path)
	Drafts.discard(recovery_folder, "game", recovery_slot)
	game_path = path
	recovery_source = path
	recovery_slot = Drafts.new_slot(path)
	library_source_path = library_path
	saved_revision = revision
	last_recovery_revision = revision
	status.text = "已保存草稿：" + path
	_update_state()
	return ""

func preview() -> void:
	_sync_editor_library()
	var compiled = Compiler.compile(game)
	if not compiled.issue.is_empty():
		report(compiled.issue, "")
		return
	if Engine.is_editor_hint():
		# 游戏另开运行进程，确保使用游戏时钟和输入，而非编辑器的工具脚本生命周期。
		var error = ResourceSaver.save(compiled.game, "user://stg_game_preview.tres")
		var scene = FileAccess.open("user://stg_game_preview.tscn", FileAccess.WRITE)
		if error != OK or scene == null:
			report("无法准备完整试玩资源。", "")
			return
		scene.store_string('[gd_scene load_steps=3 format=3]\n[ext_resource type="Script" path="res://game/game_shell.gd" id="1"]\n[ext_resource type="Resource" path="user://stg_game_preview.tres" id="2"]\n[node name="Game" type="Control"]\nscript = ExtResource("1")\ndefinition = ExtResource("2")\nsave_path = "user://stg_preview_progress_v1.json"\n')
		scene.close()
		var process_id = OS.create_process(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "user://stg_game_preview.tscn"]))
		status.text = "完整试玩已启动。" if process_id > 0 else "无法启动游戏进程。"
		return
	var window = Window.new()
	window.title = "完整游戏试玩"
	window.size = Vector2i(1280, 800)
	window.min_size = Vector2i(960, 640)
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var shell = GameShell.new()
	shell.definition = compiled.game
	shell.save_path = "user://stg_preview_progress_v1.json"
	window.add_child(shell)
	window.popup_centered()

func export_windows(path: String) -> void:
	# 只构建生成目录；输出安全与插件排除由 Builder 负责。
	_sync_editor_library()
	var build = Builder.build(game, "res://exports/PlayableGame")
	if not build.issue.is_empty():
		report(build.issue, "")
		return
	var result = Builder.export_windows(build.path, path)
	report(result.issue, "Windows 游戏已导出：\n" + path)

func report(issue: String, success: String) -> void:
	status.text = success if issue.is_empty() else issue
	host.message(status.text)

func dispose() -> void:
	if disposing:
		return
	disposing = true
	_commit_focus()
	save_recovery()
	_hide_windows(self)
	hide()

func _hide_windows(parent: Node) -> void:
	for child in parent.get_children():
		_hide_windows(child)
		if child is Window:
			child.hide()

func _exit_tree() -> void:
	dispose()
	# 子控件离开场景树后再清理数据，保留失焦提交期间需要的配置。
	host = null
	game = null

func _sync_editor_library() -> void:
	# 配置窗口可能一直打开；对同一命名资源库，试玩 / 保存总是读取编辑器最新快照。
	if not library_source_path.is_empty() and host.session.file_path == library_source_path and synced_editor_project != host.session.project:
		edit(func():
			game.library = host.session.project.snapshot()
			synced_editor_project = host.session.project)

func dirty() -> bool:
	return revision != saved_revision

func _history_entry() -> Dictionary:
	return {"game": GameDocument.snapshot(game), "source": library_source_path, "editor_project": synced_editor_project, "selection": selected_location, "revision": revision}

func edit(change: Callable, rebuild: bool = false) -> void:
	# 控件只提交一次事务。原 game 保持同一对象，已有输入回调不会抓到旧快照。
	undo_stack.append(_history_entry())
	if undo_stack.size() > 40: undo_stack.pop_front()
	redo_stack.clear()
	change.call()
	revision_counter += 1
	revision = revision_counter
	_update_state()
	if rebuild: refresh()
	if recovery_timer != null: recovery_timer.start()

func undo() -> void:
	_commit_focus()
	if undo_stack.is_empty(): return
	redo_stack.append(_history_entry())
	_restore_history(undo_stack.pop_back())

func redo() -> void:
	_commit_focus()
	if redo_stack.is_empty(): return
	undo_stack.append(_history_entry())
	_restore_history(redo_stack.pop_back())

func _restore_history(entry: Dictionary) -> void:
	game = entry.game
	library_source_path = entry.source
	synced_editor_project = entry.editor_project
	selected_location = entry.selection
	revision = entry.revision
	refresh()
	recovery_timer.start()

func _update_state() -> void:
	title = ("● 未保存 · " if dirty() else "") + "游戏配置 · 主角与世界地图"
	if undo_button != null: undo_button.disabled = undo_stack.is_empty()
	if redo_button != null: redo_button.disabled = redo_stack.is_empty()

func _commit_focus() -> void:
	var focused = gui_get_focus_owner()
	if focused != null: focused.release_focus()

func request_close() -> void:
	_commit_focus()
	if dirty(): close_dialog.popup_centered(Vector2i(600, 180))
	else: hide()

func save_recovery() -> String:
	if game == null: return ""
	if not dirty():
		Drafts.discard(recovery_folder, "game", recovery_slot)
		last_recovery_revision = -1
		return ""
	if last_recovery_revision == revision: return ""
	# 恢复副本内嵌资源库，不能只保存指向旧磁盘文件的引用。
	var issue = Drafts.write(Copy.copy(game), recovery_folder, "game", recovery_source, game.title, recovery_slot)
	if issue.is_empty(): last_recovery_revision = revision
	return issue

func _offer_recovery() -> void:
	var candidates = Drafts.list_drafts(recovery_folder, "game")
	if candidates.is_empty(): return
	recovery_offer = candidates[0]
	recovery_dialog.dialog_text = "发现本机未保存的游戏配置：%s\n来源：%s\n恢复后需另存确认，不会自动覆盖原文件。" % [recovery_offer.title, recovery_offer.source]
	recovery_dialog.popup_centered(Vector2i(650, 220))

func recover_draft(path: String) -> String:
	var found: Dictionary = {}
	for entry in Drafts.list_drafts(recovery_folder, "game"):
		if entry.path == path: found = entry
	if found.is_empty(): return "游戏恢复草稿不存在。"
	var loaded = Drafts.load_draft(path)
	if not loaded is STGGameDefinition or loaded.library == null or loaded.player == null or loaded.world == null:
		return "游戏恢复草稿缺少基本配置，无法在当前窗口中编辑。"
	if dirty() and (last_recovery_revision != revision or found.slot != recovery_slot):
		var backup_slot = "before_restore_" + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_usec())
		var issue = Drafts.write(Copy.copy(game), recovery_folder, "game", recovery_source, "恢复前：" + game.title, backup_slot)
		if not issue.is_empty(): return issue
	game = Copy.copy(loaded)
	library_source_path = "" # 恢复的库独立于打开的工作台，不能被自动同步覆盖。
	synced_editor_project = null
	game_path = "" # 恢复确认后另存，绝不静默覆盖旧游戏配置。
	recovery_source = found.source
	recovery_slot = found.slot
	selected_location = 0
	undo_stack.clear()
	redo_stack.clear()
	revision_counter += 1
	revision = revision_counter
	saved_revision = -1
	last_recovery_revision = revision
	refresh()
	save_dialog.current_file = "restored_game.tres"
	status.text = "已恢复本机草稿，请另存游戏配置确认。来源：" + found.source
	return ""

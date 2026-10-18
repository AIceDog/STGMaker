extends SceneTree
## 草稿与编辑历史：只写隔离 user:// 文件，源预设只读；实际控件与关闭提示一起验证。
const Session = preload("res://addons/stg_maker/ui/session.gd")
const GamePanel = preload("res://addons/stg_maker/ui/game_project_panel.gd")
const Drafts = preload("res://addons/stg_maker/authoring/draft_store.gd")
const Document = preload("res://addons/stg_maker/authoring/game_document.gd")
const Fixture = preload("res://tests/game_fixture.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const FOLDER = "user://draft_safety_test"
const SOURCE = "user://draft_safety_library.tres"
const INVALID = "user://draft_safety_invalid.tres"
const RESTORED = "user://draft_safety_restored.tres"
const GAME = "user://draft_safety_game.tres"

class TestHost extends Control:
	var session
	var messages: PackedStringArray = []
	func message(value: String) -> void: messages.append(value)

var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for _index in count: await process_frame

func controls(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		result.append(child)
		result.append_array(controls(child))
	return result

func field(panel, caption: String, type: String) -> Node:
	for node in controls(panel.body):
		if node is Label and node.text == caption:
			var siblings = node.get_parent().get_children()
			var index = siblings.find(node)
			if index + 1 < siblings.size() and siblings[index + 1].is_class(type): return siblings[index + 1]
	return null

func cleanup() -> void:
	var directory = DirAccess.open(FOLDER)
	if directory != null:
		for file in directory.get_files(): DirAccess.remove_absolute(FOLDER.path_join(file))
	for path in [SOURCE, INVALID, RESTORED, GAME, GAME.get_basename() + "_library.tres"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func run() -> void:
	cleanup()
	root.size = Vector2i(1440, 1000)
	root.gui_embed_subwindows = true
	var session = Session.new()
	session.recovery_folder = FOLDER
	session.create()
	check(session.save_recovery().is_empty() and session.available_drafts().is_empty(), "未编辑的默认项目不制造恢复草稿")
	check(session.save(SOURCE).is_empty() and not session.dirty(), "正常保存记录已保存快照")
	var source_hash = FileAccess.get_sha256(SOURCE)
	session.edit(func(next):
		next.barrages[0].projectile.bullet_id = "unfinished_bullet"
		next.bosses[0].phases.clear())
	check(not session.project.validate().is_empty(), "测试半成品具有无效引用与空阶段")
	check(session.save(INVALID).is_empty(), "尚未完成的文档允许显式保存")
	var opened = Session.new()
	opened.recovery_folder = FOLDER
	check(opened.open(INVALID).is_empty(), "无效半成品能够重新打开修复")
	check(opened.project.barrages[0].projectile.bullet_id == "unfinished_bullet" and opened.project.bosses[0].phases.is_empty(), "打开不自动补写或丢弃未完成数据")
	check(not opened.dirty(), "已从磁盘打开的半成品保留已保存状态")
	session.edit(func(next): next.barrages[0].title = "本机尚未保存招式")
	check(session.save_recovery().is_empty(), "未保存修改可以写入本机恢复副本")
	var candidates = session.available_drafts()
	check(candidates.size() == 1 and candidates[0].source == INVALID, "恢复草稿记录来源，与原项目分开保存")
	var draft_hash = FileAccess.get_sha256(candidates[0].path)
	check(session.save_recovery().is_empty() and FileAccess.get_sha256(candidates[0].path) == draft_hash, "重复UI刷新不会重复改写同一快照")
	check(FileAccess.get_sha256(SOURCE) == source_hash, "本机备份未改写原项目")
	check(opened.recover_draft(candidates[0].path).is_empty(), "恢复不要求半成品通过运行校验")
	check(opened.file_path.is_empty() and opened.dirty() and opened.undo_stack.is_empty(), "恢复后需显式另存，不能静默覆盖来源")
	check(opened.project.barrages[0].title == "本机尚未保存招式" and opened.project.bosses[0].phases.is_empty(), "恢复包含未完成属性和空结构")
	opened.edit(func(next): next.barrages[0].title = "同来源恢复前的未保存修改")
	check(opened.recover_draft(candidates[0].path).is_empty() and opened.project.barrages[0].title == "本机尚未保存招式", "同来源恢复先读取目标，不会用当前修改覆盖目标草稿")
	var backups = opened.available_drafts()
	check(backups.size() == 2, "恢复前的未保存内容放入独立恢复位置")
	for backup in backups:
		if backup.path == candidates[0].path: continue
		check(Drafts.load_draft(backup.path).barrages[0].title == "同来源恢复前的未保存修改", "恢复前备份保留当前内容，来源相同也不丢失")
		opened.discard_draft(backup.path)
	check(not opened.recover_draft(SOURCE).is_empty(), "恢复入口只接受已登记的本机草稿")
	check(opened.save(RESTORED).is_empty() and opened.available_drafts().is_empty(), "显式另存成功后清理对应恢复副本")
	check(FileAccess.get_sha256(SOURCE) == source_hash, "另存恢复结果保留旧文件")
	# 退出 / 切换时即时保留最后一次修改，不依赖延时计时器先触发。
	opened.edit(func(next): next.barrages[0].title = "切换前最后输入")
	check(opened.open(SOURCE).is_empty() and opened.available_drafts().size() == 1, "切换文档前保留未保存的最后修改")
	for entry in opened.available_drafts(): opened.discard_draft(entry.path)
	opened.edit(func(next): next.barrages[0].title = "撤销后可重做的草稿")
	opened.save_recovery()
	opened.undo()
	opened.save_recovery()
	check(opened.available_drafts().is_empty(), "撤销回到磁盘保存点清理恢复副本")
	opened.redo()
	opened.save_recovery()
	check(opened.available_drafts().size() == 1, "重做离开保存点重新写入恢复副本")
	for entry in opened.available_drafts(): opened.discard_draft(entry.path)
	var fixture = Fixture.create()
	check(ResourceSaver.save(fixture, GAME) == OK, "准备独立游戏配置测试文件")
	var game_hash = FileAccess.get_sha256(GAME)
	var host = TestHost.new()
	host.session = Session.new()
	host.session.recovery_folder = FOLDER
	host.session.project = fixture.library
	host.session.file_path = SOURCE
	root.add_child(host)
	var panel = GamePanel.new()
	panel.game_path = GAME
	host.add_child(panel)
	panel.open_for(host)
	await frames(5)
	check(not panel.dirty() and panel.undo_button.disabled and panel.redo_button.disabled, "游戏窗口初始状态已保存且无历史")
	var title_input = field(panel, "游戏名称", "LineEdit")
	title_input.text = "草稿测试首航"
	title_input.text_submitted.emit(title_input.text)
	check(panel.game.title == "草稿测试首航" and panel.dirty() and panel.title.begins_with("● 未保存"), "真实文本输入进入历史并更新未保存标题")
	var library = panel.game.library
	check(panel.undo_stack.back().game.library == library, "游戏标量编辑不复制整个战斗资源库")
	panel.undo()
	check(not panel.dirty() and panel.game.title == fixture.title and not panel.redo_button.disabled, "撤销回到打开时清除未保存标记")
	panel.redo()
	check(panel.dirty() and panel.game.title == "草稿测试首航", "重做恢复字段和未保存标记")
	field(panel, "移动速度", "SpinBox").value = 333
	check(is_equal_approx(panel.game.player.move_speed, 333), "主角数值输入进入游戏配置")
	panel.undo()
	check(not is_equal_approx(panel.game.player.move_speed, 333) and panel.game.title == "草稿测试首航", "数值撤销不丢失之前的文本修改")
	panel.redo()
	panel.use_current_library()
	check(panel.game.library != host.session.project and panel.game.library.levels.size() == fixture.library.levels.size(), "接入资源库单独保存快照")
	panel.undo()
	check(panel.game.library == library, "撤销资源库接入恢复原库")
	panel.redo()
	var count = panel.game.world.locations.size()
	panel.add_location()
	var location_id = panel.game.world.locations.back().id
	check(panel.game.world.locations.size() == count + 1 and panel.selected_location == count, "添加地点进入历史并选中新地点")
	panel.undo()
	check(panel.game.world.locations.size() == count, "撤销添加地点")
	panel.redo()
	check(panel.game.world.locations.back().id == location_id, "重做保留地点稳定ID")
	field(panel, "地点名称", "LineEdit").text = "未完成地点"
	field(panel, "地点名称", "LineEdit").text_submitted.emit("未完成地点")
	check(panel.game.world.find(location_id).title == "未完成地点", "撤销重建控件后修改仍指向当前地点")
	panel.remove_location()
	panel.undo()
	check(panel.game.world.find(location_id) != null and panel.game.world.find(location_id).title == "未完成地点", "撤销删除恢复地点属性")
	check(FileAccess.get_sha256(GAME) == game_hash, "普通字段编辑、历史和窗口操作不写入原游戏文件")
	check(panel.save_game(GAME).is_empty() and not panel.dirty(), "保存游戏草稿建立历史保存点")
	panel.edit(func(): panel.game.player.fire_interval = 0)
	check(panel.dirty() and not Compiler.compile(panel.game).issue.is_empty(), "无效草稿可编辑，试玩编译保持严格校验")
	panel.undo()
	check(not panel.dirty(), "撤销到最近保存点清除dirty状态")
	panel.redo()
	check(panel.dirty(), "离开保存点重新标记dirty")
	panel.request_close()
	await frames()
	check(panel.close_dialog.visible and panel.visible, "未保存时关闭先弹出确认并保留窗口")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/draft_safety_actual.png")
	panel.close_dialog.hide()
	check(panel.save_recovery().is_empty(), "游戏草稿包含未保存的主角与地图")
	var game_candidates = Drafts.list_drafts(FOLDER, "game")
	check(game_candidates.size() == 1, "游戏恢复副本与资源库草稿分开登记")
	panel.edit(func(): panel.game.player.max_health = 8)
	check(panel.recover_draft(game_candidates[0].path).is_empty(), "游戏恢复草稿可重新打开")
	var game_backups = Drafts.list_drafts(FOLDER, "game")
	check(game_backups.size() == 2, "游戏恢复也先单独保存当前未保存内容")
	for backup in game_backups:
		if backup.path == game_candidates[0].path: continue
		check(Drafts.load_draft(backup.path).player.max_health == 8, "恢复游戏草稿前的主角改动仍能找回")
		Drafts.discard(FOLDER, "game", backup.slot)
	check(panel.dirty() and panel.game_path.is_empty() and panel.library_source_path.is_empty(), "恢复游戏后强制另存，避免工作台同步覆盖恢复内容")
	check(is_zero_approx(panel.game.player.fire_interval) and panel.game.world.find(location_id).title == "未完成地点", "游戏恢复保留无效参数与新增地点")
	check(not Compiler.compile(panel.game).issue.is_empty(), "恢复草稿不会绕过试玩校验")
	check(panel.save_game(GAME).is_empty() and is_zero_approx(Document.load_definition(GAME).player.fire_interval), "无效游戏配置显式保存后可以重新载入")
	check(Drafts.list_drafts(FOLDER, "game").is_empty(), "游戏保存成功后清理恢复副本")
	check(game_hash != FileAccess.get_sha256(GAME), "只有显式保存改写测试游戏文件")
	panel.dispose()
	await frames(2)
	panel.queue_free()
	await frames(3)
	host.queue_free()
	await frames(4)
	cleanup()
	print("DRAFT SAFETY RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


extends SceneTree
## 嵌入子窗口后捕获窗口自身纹理，避免另开可见系统窗口。
const SETTINGS = "user://game_project_capture.cfg"
var studio
var panel
var images = 0

func _initialize() -> void:
	run.call_deferred()

func shot(name: String) -> void:
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png("res://tests/game_project_" + name + "_actual.png")
	images += 1

func run() -> void:
	root.size = Vector2i(1440, 1000)
	root.gui_embed_subwindows = true
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = SETTINGS
	root.add_child(studio)
	for _frame in 5:
		await process_frame
	studio.set_process(false)
	studio.open_game_configuration()
	panel = studio.game_project_panel
	panel.size = Vector2i(1050, 780)
	await shot("large")
	var scroll: ScrollContainer = panel.body.get_parent()
	scroll.scroll_vertical = 10000
	await shot("world")
	panel.size = Vector2i(780, 600)
	panel.position = Vector2i(300, 100)
	scroll.scroll_vertical = 0
	await shot("small")
	scroll.scroll_vertical = 10000
	await shot("small_world")
	studio.queue_free()
	for _frame in 8:
		await process_frame
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)
	print("GAME PROJECT CAPTURE RESULT: %d images saved" % images)
	quit(0)

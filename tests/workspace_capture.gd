extends SceneTree
## 实际渲染紧凑工作区及二级素材导航；不打开用户自己的编辑器。
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
var studio
var images = 0

func _initialize() -> void:
	run.call_deferred()

func shot(name: String) -> void:
	for _frame in 48:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/workspace_" + name + "_actual.png")
	images += 1

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://workspace_capture.cfg"
	root.add_child(studio)
	await shot("barrage")
	studio.bullet_button.pressed.emit()
	await shot("materials")
	studio.boss_button.pressed.emit()
	await shot("character")
	studio.level_button.pressed.emit()
	studio.Commands.add(studio, "empty_level")
	await shot("level")
	studio.library_button.pressed.emit()
	root.size = Vector2i(1100, 760)
	await shot("small")
	Workspaces.toggle_focus(studio)
	await shot("focused")
	studio.queue_free()
	for _frame in 10:
		await process_frame
	if FileAccess.file_exists("user://workspace_capture.cfg"):
		DirAccess.remove_absolute("user://workspace_capture.cfg")
	print("WORKSPACE CAPTURE RESULT: %d images saved" % images)
	quit(0)

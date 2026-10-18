extends SceneTree
## 实际渲染检查：暂停下的完整轨迹、追踪运动、窄窗口布局。
var studio
var images = 0

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	for i in 12: await process_frame
	var frames = 0
	while studio.canvas.trajectory.running and frames < 240:
		await process_frame
		frames += 1
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + ".png")
	images += 1

func _run() -> void:
	root.size = Vector2i(1440, 900)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://attack_workbench_capture.cfg"
	root.add_child(studio)
	for i in 12: await process_frame
	studio.set_font_size(0, false)
	studio.set_ui_scale(0, false)
	studio.playing = false
	await capture("attack_workbench_actual")
	studio.edit_path(studio.motion_scope(), "mode", "track", true)
	studio.edit_path(studio.motion_scope(), "preserve_heading", true, true)
	studio.edit_path(studio.motion_scope(), "duration", 4.0, true)
	await capture("attack_tracking_actual")
	root.size = Vector2i(1100, 760)
	await capture("attack_compact_actual")
	studio.free()
	for i in 8: await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://attack_workbench_capture.cfg"))
	print("ATTACK WORKBENCH CAPTURE RESULT: %d images" % images)
	quit(0)

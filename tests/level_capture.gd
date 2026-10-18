extends SceneTree
## 原生渲染检查：关卡布局、实际滚动战斗、出生点、编队、背景页和窗口尺寸。
var studio
var images = 0
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i in 8: await process_frame
func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + "_actual.png")
	images += 1
func run() -> void:
	root.size = Vector2i(1440, 900)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false; studio.settings_path = "user://level_capture.cfg"
	root.add_child(studio); await settle(); studio.set_process(false)
	studio.open_project("res://presets/level_demo.tres"); studio.switch_collection("levels"); await settle()
	studio.message_dialog.hide()
	studio.select_level_event(studio.level_segment().events[0].id)
	await shot("level_spawn")
	studio.finish_canvas_edit()
	for i in 420: studio.canvas.world.step()
	studio.update_preview_ui()
	await shot("level_battle")
	studio.select_level_segment(1); studio.select_inspector_tab(1); await settle()
	studio.test_level(true); studio.playing = false
	for i in 180: studio.canvas.world.step()
	studio.update_preview_ui()
	await shot("level_obstacles")
	studio.select_inspector_tab(2)
	await shot("level_background")
	studio.select_inspector_tab(0)
	studio.select_level_event(studio.level_segment().events[0].id)
	studio.edit_reference("waves", studio.level_event().wave_id)
	await shot("level_wave")
	studio.navigation.go_back(studio)
	root.size = Vector2i(1100, 760)
	await shot("level_small")
	root.size = Vector2i(2560, 1440)
	await shot("level_large")
	studio.queue_free(); await settle()
	print("LEVEL CAPTURE RESULT: %d images" % images)
	quit(0)

extends SceneTree
## 真正渲染完整时间轴和实体设置。截图用于检查裁切、文字、轨道与窗口适配。
var studio
var images: int = 0

func _initialize() -> void: # Godot 回调
	run.call_deferred()

func settle() -> void:
	for i in 10: await process_frame

func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + "_actual.png")
	images += 1

func run() -> void:
	root.size = Vector2i(1440, 1000)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://timeline_capture.cfg"
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	studio.open_project("res://presets/timeline_demo.tres")
	studio.switch_collection("levels")
	await settle()
	studio.select_level_segment(0)
	studio.select_inspector_tab(1)
	await shot("timeline_overview")
	studio.select_level_segment(2)
	studio.select_inspector_tab(1)
	await shot("timeline_boss_condition")
	studio.select_level_segment(1)
	studio.test_level(true)
	studio.playing = false
	for i in 1500: studio.canvas.world.step()
	studio.update_preview_ui()
	await shot("timeline_waiting")
	studio.select_level_segment(0)
	studio.select_level_event(studio.level_segment().events[0].id)
	studio.edit_reference("waves", studio.level_event().wave_id)
	await shot("timeline_wave")
	var wave = studio.current()
	studio.edit_reference("bosses", wave.enemy_id)
	studio.select_inspector_tab(2)
	await shot("timeline_entity_settings")
	studio.navigation.go_back(studio)
	studio.navigation.go_back(studio)
	studio.select_level_segment(0)
	studio.select_inspector_tab(1)
	root.size = Vector2i(1100, 760)
	await shot("timeline_small")
	root.size = Vector2i(2560, 1440)
	await shot("timeline_large")
	studio.queue_free()
	await settle()
	print("TIMELINE CAPTURE RESULT: %d images" % images)
	quit(0)

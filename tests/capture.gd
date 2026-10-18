extends SceneTree
## 实际渲染回归：基础外形、路径、时间曲线、分支流程与字体缩放。
var studio
var images = 0
func _initialize() -> void: run.call_deferred()
func shot(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + "_actual.png"); images += 1
func run() -> void:
	root.size = Vector2i(1440, 900)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate(); studio.restore_last_project = false
	studio.settings_path = "user://capture_ui_size.cfg"; root.add_child(studio)
	studio.set_font_size(0, false); studio.set_ui_scale(0, false)
	await shot("simple_barrage")
	studio.switch_collection("bullets", studio.session.project.bullets[0].id)
	studio.select_inspector_tab(0)
	await shot("simple_bullet")
	studio.switch_collection("barrages", studio.session.project.barrages[0].id)
	studio.open_curve(["projectile", "motion_stages", 0], "visual_scale_curve")
	await shot("simple_curve")
	studio.switch_collection("bullets", studio.session.project.bullets[1].id)
	await shot("simple_laser")
	studio.switch_collection("bosses"); studio.Commands.add(studio, "conditional_boss")
	for i in 8: await process_frame
	studio.set_boss_view("flow"); studio.flow_editor.fit_graph()
	await shot("boss_conditional_flow")
	studio.set_font_size(20, false)
	await shot("simple_font20")
	root.size = Vector2i(2560, 1440); studio.set_font_size(0, false); studio.set_ui_scale(0, false)
	await shot("ui_large")
	root.size = Vector2i(1100, 760); studio.set_ui_scale(150, false)
	await shot("ui_small_150")
	studio.queue_free(); for i in 12: await process_frame
	print("CAPTURE RESULT: %d images saved" % images); quit(0)

extends SceneTree
## 实际绘制引用导航、编辑状态、不可用测试按钮与时间轴悬停反馈。
var studio
var images: int = 0

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in 10:
		await process_frame

func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + "_actual.png")
	images += 1

func run() -> void:
	root.size = Vector2i(1440, 1000)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://interaction_capture.cfg"
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	studio.edit_reference("bullets", studio.emission().bullet_id)
	await settle()
	studio.select_inspector_tab(1)
	await shot("interaction_reference")
	studio.set_tool("path")
	await shot("interaction_edit")
	studio.finish_canvas_edit()
	studio.edit_path([], "radius", -1)
	await shot("interaction_invalid")
	studio.undo_edit()
	await settle()
	studio.open_project("res://presets/timeline_demo.tres")
	studio.switch_collection("levels")
	await settle()
	var event = studio.level_segment().events[0]
	studio.select_level_event(event.id)
	await settle()
	var motion = InputEventMouseMotion.new()
	motion.position = studio.level_timeline.event_rect(0, event.id).get_center()
	studio.level_timeline._gui_input(motion)
	await shot("interaction_timeline_hover")
	studio.queue_free()
	await settle()
	print("INTERACTION CAPTURE RESULT: %d images" % images)
	quit(0)

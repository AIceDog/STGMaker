extends SceneTree
## 实际渲染：十敌人图鉴、工作台入口和两个分支流程。无头模式不运行此脚本。
const LIBRARY_PATH = "res://presets/enemy_library.tres"
var images = 0

func _initialize() -> void: # Godot 回调
	run.call_deferred()

func capture(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + "_actual.png")
	images += 1

func run() -> void:
	root.size = Vector2i(2000, 1180)
	var project: STGProject = load(LIBRARY_PATH)
	var page = ColorRect.new()
	page.color = Color("101621")
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var notes = ["上下巡航 · 向左扇射", "固定圆心盘旋 · 环形扩散", "曲线换位 · 三连狙击", "预告瞬移 · 近身散射", "遁地追击 · 地面脉冲", "距离判断 · 冲刺 / 点射", "慢速换位 · 预警激光", "靠近后缩圈 · 星弹蓄势突击", "折线巡航 · 变形雷种和尾迹", "随机压制 · 低血量复合封锁"]
	var times = [1.6, 2.6, 3.7, 1.6, 2.6, 1.7, 3.4, 2.7, 2.5, 2.8]
	for index in project.bosses.size():
		var enemy = project.bosses[index]
		var panel = Panel.new()
		panel.position = Vector2(12 + (index % 5) * 398, 12 + (index / 5) * 578)
		panel.size = Vector2(386, 566)
		page.add_child(panel)
		var title = Label.new()
		title.text = enemy.title
		title.position = Vector2(16, 12)
		title.add_theme_font_size_override("font_size", 24)
		panel.add_child(title)
		var description = Label.new()
		description.text = notes[index]
		description.position = Vector2(16, 52)
		description.add_theme_font_size_override("font_size", 18)
		panel.add_child(description)
		var preview = SubViewportContainer.new()
		preview.position = Vector2(8, 210)
		preview.size = Vector2(370, 208)
		panel.add_child(preview)
		var viewport = SubViewport.new()
		viewport.size = Vector2i(370, 208)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		preview.add_child(viewport)
		var world = STGSimulation.new()
		viewport.add_child(world)
		world.reset(project, "bosses", enemy.id)
		world.position = Vector2(185, 104)
		world.scale = Vector2.ONE * (370.0 / 960)
		if enemy.id == "06_charger": world.player = Vector2(240, 0)
		if enemy.id == "10_commander": world.damage_boss(60)
		for i in ceili(times[index] / STGSimulation.STEP): world.step()
	await capture("ten_enemies")
	page.queue_free()
	for i in 8: await process_frame
	root.size = Vector2i(1440, 900)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://enemy_capture.cfg"
	root.add_child(studio)
	for i in 8: await process_frame
	studio.set_process(false)
	studio.open_project(LIBRARY_PATH)
	studio.switch_collection("bosses", "01_swift")
	studio.set_boss_view("battle")
	for i in 8: await process_frame
	for i in 200: studio.canvas.world.step()
	studio.update_preview_ui()
	await capture("enemy_library_ui")
	studio.select_resource("06_charger")
	studio.set_boss_view("flow")
	await capture("enemy_distance_flow")
	studio.select_resource("10_commander")
	studio.phase_index = 1
	studio.refresh(true)
	await capture("enemy_phase_flow")
	studio.queue_free()
	for i in 12: await process_frame
	print("CAPTURE RESULT: %d enemy images saved" % images)
	quit(0)

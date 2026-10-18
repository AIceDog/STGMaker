extends SceneTree
## 原生渲染验证新入口、Boss 阶段表单、旋转激光与带缺口刀阵。
var studio
var images: int = 0
func _initialize() -> void: run.call_deferred()
func shot(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/flytiger_boss_" + name + "_actual.png")
	images += 1
func choose(collection: String, id: String) -> void:
	studio.switch_collection(collection, id)
	for i in 8: await process_frame
	studio.set_process(false)
func simulate(seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): studio.canvas.world.step()
	studio.update_preview_ui()
func run() -> void:
	root.size = Vector2i(1440, 900)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://flytiger_boss_capture.cfg"
	root.add_child(studio)
	for i in 8: await process_frame
	studio.set_process(false)
	studio.open_project("res://presets/flytiger_bosses.tres")
	await choose("bosses", "ft_boss_Sphinx")
	studio.set_boss_view("flow"); studio.flow_editor.fit_graph()
	studio.select_inspector_tab(2)
	await shot("phases")
	await choose("barrages", "ft_boss_skill_183")
	simulate(1.4)
	await shot("rotating_lasers")
	await choose("behaviors", "ft_boss_skill_132")
	simulate(1)
	await shot("blade_gap")
	await choose("bosses", "ft_boss_BossMan")
	studio.create_button.get_popup().popup()
	await shot("menu")
	studio.create_button.get_popup().hide()
	root.size = Vector2i(1100, 760)
	await choose("barrages", "ft_boss_skill_027")
	simulate(4.7)
	await shot("summons_small")
	studio.queue_free()
	for i in 12: await process_frame
	print("CAPTURE RESULT: %d Boss UI images saved" % images)
	quit(0)

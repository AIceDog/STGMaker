extends SceneTree
## 使用真实渲染器检查模板入口、参数表单、行为流程和攻击预览。
var studio
var images: int = 0

func _initialize() -> void: run.call_deferred()
func shot(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/flytiger_" + name + "_actual.png")
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
	studio.settings_path = "user://flytiger_capture.cfg"
	root.add_child(studio)
	for i in 8: await process_frame
	studio.set_process(false)
	studio.open_project("res://presets/flytiger_enemies.tres")
	await choose("bosses", "ft_enemy_pig")
	studio.set_boss_view("flow")
	studio.flow_editor.fit_graph()
	await shot("enemy_flow")
	await choose("behaviors", "ft_skill_35")
	simulate(0.5)
	await shot("paired_salvo")
	await choose("barrages", "ft_skill_21")
	simulate(0.4)
	await shot("laser_warning")
	await choose("bullets", "ft_bullet_archer_arrow")
	studio.select_inspector_tab(1)
	simulate(0.6)
	await shot("ballistic_fields")
	await choose("bullets", "ft_bullet_stormfish_orb_0")
	studio.select_inspector_tab(1)
	simulate(0.6)
	await shot("sine_fields")
	await choose("bosses", "ft_enemy_axeMinion")
	studio.create_button.get_popup().popup()
	await shot("template_menu")
	studio.create_button.get_popup().hide()
	root.size = Vector2i(1100, 760)
	await choose("barrages", "ft_skill_13")
	simulate(0.85)
	await shot("body_small_window")
	studio.queue_free()
	for i in 12: await process_frame
	print("CAPTURE RESULT: %d FlyTiger UI images saved" % images)
	quit(0)

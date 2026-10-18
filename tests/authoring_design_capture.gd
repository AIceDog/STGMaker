extends SceneTree
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Section = preload("res://addons/stg_maker/ui/form_section.gd")
var studio
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i in 12: await process_frame
func capture(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/authoring_design_" + name + ".png")
func fold(node: Node, title: String) -> void:
	if node.get_script() == Section and node.title == title and node.collapsible: node.heading.button_pressed = false
	for child in node.get_children(): fold(child, title)
func run() -> void:
	root.size = Vector2i(1440, 900)
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://authoring_design_capture.cfg"
	studio.show_trajectories = false
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	var project = STGProject.create()
	var bullet = Factory.bullet()
	bullet.title = "四阶段贴图子弹"
	bullet.visual.mode = "texture"
	bullet.visual.run_clip = load("res://addons/stg_maker/authoring/gif_import.gd").new().load_clip("res://tests/fixtures/phase_gif/disposal.gif").clip
	bullet.visual.geometry.size = Vector2(64, 40)
	project.bullets.append(bullet)
	project.bullets.append(Factory.bullet("laser"))
	project.bullets.append(Factory.bullet("trail"))
	project.bosses.append(Factory.boss())
	var attack = Factory.barrage(bullet.id)
	attack.title = "12 颗 · 每批 3 颗"
	attack.fire_pattern.count = 12
	attack.fire_pattern.group_size = 3
	attack.fire_pattern.group_interval = 0.1
	project.barrages.append(attack)
	studio.session.project = project
	studio.switch_collection("bullets", bullet.id)
	await capture("texture")
	studio.edit_configuration(["visual"], func(visual, _project): visual.mode = "geometry"; visual.run_clip = null)
	root.size = Vector2i(1100, 760)
	studio.set_font_size(24, false)
	await capture("large_font")
	root.size = Vector2i(1440, 900)
	studio.set_font_size(18, false)
	studio.switch_collection("barrages", attack.id)
	fold(studio.inspector, "招式类型与引用")
	fold(studio.inspector, "子弹节奏")
	await capture("grouped")
	studio.edit_configuration(["fire_pattern"], func(pattern, library): pattern.enemy_id = library.bosses[0].id; pattern.summon_mode = "launch")
	await capture("summon")
	studio.free()
	await settle()
	print("AUTHORING DESIGN CAPTURE RESULT: 4 images")
	quit()

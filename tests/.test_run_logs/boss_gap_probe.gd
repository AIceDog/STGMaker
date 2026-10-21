extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var project = load("res://addons/stg_maker/authoring/templates/flytiger_boss_library.gd").new().build()
	var world = STGSimulation.new(); root.add_child(world)
	world.reset(project, "barrages" if project.find("barrages", "ft_boss_skill_164") != null else "behaviors", "ft_boss_skill_164"); world.player = Vector2(-300, 0); world.step()
	print("GAP PROBE count=", world.actors.size())
	for actor in world.actors: print("GAP PROBE birth=", actor.stage_origin, " current=", actor.position)
	world.free(); quit()

@tool
extends EditorPlugin
## 由临时测试插件加载到真实编辑器，不替换编辑器主循环。
const Copy = preload("res://stg/definitions/config_copy.gd")
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Document = preload("res://addons/stg_maker/authoring/game_document.gd")
var checks: int = 0
var failures: int = 0

func _enter_tree() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func run() -> void:
	for frame in 30: await get_tree().process_frame
	var filesystem = EditorInterface.get_resource_filesystem()
	var started = Time.get_ticks_msec()
	while filesystem != null and filesystem.is_scanning() and Time.get_ticks_msec() - started < 20000: await get_tree().process_frame
	check(Engine.is_editor_hint(), "test runs inside actual editor context")
	for path in ["accelerated_straight", "emissions/spiral", "actions/dive", "conditions/health_gate", "effects/hit_burst", "players/dash"]:
		var definition: STGExtensionDefinition = load("res://game/extensions/" + path + ".tres")
		check(definition != null and definition.validate({}).is_empty(), "editor instantiates capability: " + path)
	_test_preview()
	for frame in 8: await get_tree().process_frame
	print("EDITOR EXTENSIONS RESULT: %d checks, %d failures" % [checks, failures])
	# 走编辑器原生关闭流程，先分离调试插件；直接终止主循环会打断编辑器收尾。
	preload("res://tests/editor_shutdown.gd").request(self)

func _test_preview() -> void:
	var game: STGGameDefinition = Copy.copy(Document.load_definition("res://game/content/modular_example/game.tres"))
	var session = STGGameSession.new()
	get_tree().root.add_child(session)
	session.configure(game, "user://editor_extension_test_progress.json")
	check(session.enter_location(game.start_location_id), "editor can start shared game framework")
	if session.simulation != null:
		var origin: Vector2 = session.simulation.player
		for tick in 60: session.advance(STGSimulation.STEP, Vector2.RIGHT, false, tick == 0)
		check(session.state == "battle" and session.issue.is_empty() and session.simulation.player.x > origin.x + 70, "editor executes default controller and custom player ability")
		session.advance(STGSimulation.STEP, Vector2.ZERO, true)
		check(session.simulation.player_shots.shots.size() >= 3, "editor executes custom weapon")
		var enemy = session.simulation.entities[0].simulation if not session.simulation.entities.is_empty() else null
		check(enemy != null and enemy.actors.size() > 0 and enemy.issue.is_empty(), "editor executes custom condition, action and asynchronous emission")
		if enemy != null:
			var bullet = enemy.emit_projectile("modular_spiral", enemy.player, 0, enemy.allocate_owner())
			bullet.tick(enemy, STGSimulation.STEP)
			check(enemy.barrages.any(func(value): return value.prefab.id == "modular_followup"), "editor executes custom hit effect")
		session.return_to_map()
		check(session.player_modules.is_empty(), "editor preview closes player module contexts")
	session.free()
	var library = STGProject.create()
	library.schema_version = STGProject.VERSION
	var motion_bullet = Factory.bullet()
	var motion_attack = Factory.barrage(motion_bullet.id)
	motion_attack.fire_pattern.count = 1
	motion_attack.fire_pattern.rounds = 1
	motion_attack.projectile.motion_stages[0].mode = "extension"
	motion_attack.projectile.motion_stages[0].extension = STGExtensionBinding.create(load("res://game/extensions/accelerated_straight.tres"))
	library.barrages.append(motion_attack)
	library.bullets.append(motion_bullet)
	var world = STGSimulation.new()
	get_tree().root.add_child(world)
	world.reset(library, "barrages", motion_attack.id)
	world.step()
	world.player = Vector2(-10000, -10000)
	var initial: Vector2 = world.actors[0].position
	for tick in 30: world.step()
	check(world.issue.is_empty() and world.actors[0].position.distance_to(initial) > 1, "editor executes custom motion with shared lifecycle")
	world.free()

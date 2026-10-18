extends SceneTree
## 从独立资产编译，再在无编辑器/测试源码的全新工程中执行自定义角色与主角能力。
const Builder = preload("res://addons/stg_maker/build/project_builder.gd")
const Document = preload("res://addons/stg_maker/authoring/game_document.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func run() -> void:
	var game = Document.load_definition("res://game/content/modular_example/game.tres")
	check(game != null and game.validate().is_empty(), "independent example assets are valid")
	var output = "user://modular_export_%s" % Time.get_ticks_usec()
	var built = Builder.build(game, output)
	check(built.issue.is_empty(), "modular game builds: " + built.issue)
	if built.issue.is_empty():
		for script in ["emissions/spiral", "actions/dive", "conditions/health_gate", "effects/hit_burst", "players/spread_weapon", "players/dash"]:
			check(FileAccess.file_exists(output.path_join("game/extensions/" + script + ".gd")), "selected runtime extension enters export: " + script)
		check(not DirAccess.dir_exists_absolute(output.path_join("addons")) and not DirAccess.dir_exists_absolute(output.path_join("tools")) and not DirAccess.dir_exists_absolute(output.path_join("tests")), "export excludes editor, migrations and test source")
		check(not FileAccess.file_exists(output.path_join("game/extensions/accelerated_straight.gd")), "unused SDK example is omitted")
		check(FileAccess.file_exists(output.path_join("game/extensions/emissions/ring_math.gd")), "relative preload helper enters recursive file dependencies")
		var verifier = FileAccess.open(output.path_join("verify_export.gd"), FileAccess.WRITE)
		verifier.store_string('''extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://game/content/first_game.tres")
	if game == null or not game.validate().is_empty(): quit(1); return
	var session = STGGameSession.new()
	root.add_child(session)
	session.configure(game, "user://modular_export_verify.json")
	if not session.enter_location(game.start_location_id): quit(2); return
	var start = session.simulation.player
	for tick in 120: session.advance(STGSimulation.STEP, Vector2(0, -0.1), false, tick == 0)
	var valid = session.state == "battle" and session.issue.is_empty() and session.simulation.player.y < start.y - 50
	valid = valid and not session.simulation.entities.is_empty()
	if valid:
		var enemy = session.simulation.entities[0].simulation
		valid = enemy != null and enemy.issue.is_empty() and enemy.actors.size() > 0
	session.return_to_map()
	valid = valid and session.player_modules.is_empty()
	session.free()
	print("MODULAR EXPORTED GAME RESULT: 1 checks, %d failures" % (0 if valid else 1))
	quit(0 if valid else 3)
''')
		verifier.close()
		var log: Array = []
		var code = preload("res://tests/export_runtime.gd").import_project(built.path, log)
		check(code == 0 and not Builder._has_errors(log), "fresh exported project imports without source cache: " + "\n".join(log))
		log.clear()
		code = preload("res://tests/export_runtime.gd").run(built.path, log, "verify_export.gd", 2000)
		check(code == 0 and not Builder._has_errors(log) and "MODULAR EXPORTED GAME RESULT: 1 checks, 0 failures" in "\n".join(log), "exported game executes custom enemy/emission/player modules: " + "\n".join(log))
	var rejected = Builder._resolve_dependencies({"game/test.gd": {"text": 'extends RefCounted\nconst Bad = preload("res://game/../addons/editor.gd")\n'}})
	check(not rejected.issue.is_empty(), "traversal cannot bring editor code into export")
	print("MODULAR BUILD RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

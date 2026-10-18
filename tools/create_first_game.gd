extends SceneTree
## 首版内容组装工具：只创建新游戏内容，不修改已有预设或策划 working.tres。
const D = preload("res://stg/definitions/definition_factory.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const References = preload("res://stg/definitions/resource_references.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game_path = "res://game/content/first_game.tres"
	if FileAccess.file_exists(game_path):
		push_error("首版游戏已经存在；创建工具不会覆盖已编辑内容。")
		quit(1)
		return
	var library = STGProject.create()
	library.schema_version = STGProject.VERSION
	for path in ["res://presets/flytiger_enemies.tres", "res://presets/flytiger_bosses.tres"]:
		var source = load(path).snapshot()
		for collection in References.COLLECTIONS:
			for item in source.get(collection):
				if library.find(collection, item.id) == null:
					library.get(collection).append(Copy.copy(item))
	var demon_wave = _wave(library, "patrol_demons", "恶魔巡逻队", "ft_enemy_demon", 3)
	var bat_wave = _wave(library, "patrol_bats", "蝙蝠突击队", "ft_enemy_bat", 2)
	var patrol = D.level()
	patrol.id = "border_patrol"
	patrol.title = "边境巡航"
	patrol.segments.clear()
	var cruise = D.level_segment()
	cruise.id = "patrol_cruise"
	cruise.title = "起飞"
	cruise.duration = 2
	cruise.scroll_speed = 35
	cruise.exit_rule = D.level_exit_rule("time")
	patrol.segments.append(cruise)
	patrol.segments.append(_encounter("patrol_skirmish", "恶魔巡逻队", demon_wave.id, Vector2(260, -90), 8))
	patrol.segments.append(_encounter("patrol_ambush", "蝙蝠突击队", bat_wave.id, Vector2(300, -45), 6))
	library.levels.append(patrol)
	var boss_wave = _wave(library, "mountain_boss", "山门守卫", "ft_boss_PigKing", 1)
	var boss_level = D.level()
	boss_level.id = "mountain_gate"
	boss_level.title = "山门试炼"
	boss_level.segments.clear()
	boss_level.segments.append(_encounter("mountain_duel", "击败猪妖王", boss_wave.id, Vector2(250, 0), 20, "defeat_all"))
	library.levels.append(boss_level)
	var game = STGGameDefinition.new()
	game.title = "STGMaker · 首版试飞"
	game.library = library
	game.player = STGPlayerDefinition.new()
	game.player.max_health = 5
	game.player.shot_damage = 12.5
	game.world = STGWorldDefinition.new()
	game.start_location_id = "border"
	game.world.locations.append(_location("border", "边境巡航", patrol.id, Vector2(0.28, 0.52), 100))
	var gate = _location("gate", "山门试炼", boss_level.id, Vector2(0.72, 0.37), 300)
	gate.requires_completion.append("border")
	game.world.locations.append(gate)
	var errors = game.validate()
	if not errors.is_empty():
		push_error("\n".join(errors))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://game/content")
	var error = ResourceSaver.save(library, "res://game/content/first_library.tres", ResourceSaver.FLAG_CHANGE_PATH)
	if error == OK:
		library.take_over_path("res://game/content/first_library.tres")
		error = ResourceSaver.save(game, game_path)
	if error != OK:
		push_error(error_string(error))
		quit(1)
		return
	print("FIRST GAME CREATED: %d enemies/Bosses, %d levels" % [library.bosses.size(), library.levels.size()])
	quit(0)

func _wave(library: STGProject, id: String, title: String, enemy: String, count: int) -> STGWaveDefinition:
	var wave = D.wave(enemy)
	wave.id = id
	wave.title = title
	wave.count = count
	wave.interval = 0.7
	wave.spacing = Vector2(0, 90)
	library.waves.append(wave)
	return wave

func _encounter(id: String, title: String, wave_id: String, at: Vector2, planned_duration: float, condition: String = "clear") -> STGLevelSegment:
	var segment = D.level_segment(wave_id)
	segment.id = id
	segment.title = title
	segment.duration = planned_duration
	segment.scroll_speed = 0
	segment.exit_rule = D.level_exit_rule("condition")
	segment.exit_rule.condition = condition
	segment.exit_rule.wait_attacks = false
	segment.events[0].spawn_position = at
	return segment

func _location(id: String, title: String, level_id: String, at: Vector2, reward: int) -> STGWorldLocation:
	var location = STGWorldLocation.new()
	location.id = id
	location.title = title
	location.level_id = level_id
	location.map_position = at
	location.reward = reward
	location.description = "完成战斗可获得首通奖励，返回地图后进度自动保存。"
	return location

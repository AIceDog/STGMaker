extends SceneTree
## 关卡运行集成：出场节奏、卷轴与 AI 组合、旧攻击收尾、死亡 / 离场、射击和资源保存。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred() # Godot 回调
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func advance(world, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): world.step()

func basic() -> STGProject:
	var project = STGProject.create()
	D.populate(project)
	project.bosses[0].phases.resize(1)
	var idle = D.action(); idle.windup = 0; idle.recovery = 0; idle.duration = 20
	project.bosses[0].phases[0].behavior_flow = D.flow([idle])
	project.bosses[0].entity_settings.movement_policy = "independent"
	project.bosses[0].entity_settings.lifetime = 0
	var wave = D.wave(project.bosses[0].id)
	wave.count = 1
	project.waves.append(wave)
	var level = D.level(wave.id)
	level.segments[0].duration = 0.1
	level.segments[0].events[0].spawn_position = Vector2(320, 0)
	project.levels.append(level)
	return project

func world_for(project: STGProject) -> STGLevelSimulation:
	var world = STGLevelSimulation.new()
	root.add_child(world)
	world.reset(project, "levels", project.levels[0].id)
	return world

func run() -> void:
	var demo = load("res://presets/level_demo.tres")
	check(demo != null and demo.validate().is_empty(), "三段示例关卡和全部敌人依赖合法")
	check(demo.levels.size() == 1 and demo.waves.size() == 4 and demo.bosses.size() == 10, "关卡复用十敌人库，具有四种编队")
	var project = basic()
	var wave = project.waves[0]
	wave.count = 2; wave.interval = 0.5
	project.bosses[0].entity_settings.lifetime = 1.5
	var world = world_for(project)
	advance(world, 0.1)
	check(world.entities.size() == 1 and world.waiting_clear, "按间隔出场，片段到时等待清场")
	world.damage_entity(world.entities[0].instance_id, 100)
	advance(world, 0.2)
	check(not world.completed and world.wave_jobs.size() == 1, "首个敌人死亡也等待尚未出场的编队成员")
	advance(world, 2)
	check(world.completed and world.entities.is_empty() and world.resolved_entities.values().has("died") and world.resolved_entities.values().has("timeout"), "死亡和时间离场分别上报，编队完整收尾")
	world.free()

	# 从头走完整示例：前三段不能各自测试通过却在实际连接时卡住。
	world = STGLevelSimulation.new()
	root.add_child(world)
	world.reset(demo, "levels", demo.levels[0].id)
	var visited = {}
	for i in 4800:
		visited[world.segment_index] = true
		if world.segment_index == 2 and world.waiting_clear:
			for enemy in world.entities: world.damage_entity(enemy.instance_id, 100)
		world.step()
		if world.completed or not world.issue.is_empty(): break
	check(visited.size() == 3 and world.completed and world.issue.is_empty(), "完整示例依次推进三段，最终结束：%s / %s" % [world.status(), world.issue])
	check(world.scroll.distance > 1600 and world.resolved_entities.values().has("died") and (world.resolved_entities.values().has("escaped") or world.resolved_entities.values().has("timeout")), "完整关卡保留推进距离及每个实体的真实离场结果")
	world.free()

	project = basic()
	project.levels[0].segments[0].duration = 5
	project.levels[0].segments[0].events.clear()
	wave = project.waves[0]; project.bosses[0].entity_settings.movement_policy = "scroll"
	var independent_enemy = project.bosses[0].duplicate(true)
	independent_enemy.id = "independent_enemy"
	independent_enemy.entity_settings.movement_policy = "independent"
	project.bosses.append(independent_enemy)
	world = world_for(project)
	var moving = world.spawn_entity(wave, Vector2(320, 0), world.segment().id)
	var independent = wave.duplicate(true); independent.enemy_id = independent_enemy.id
	var stationary = world.spawn_entity(independent, Vector2(320, 100), world.segment().id)
	var projectile = project.barrages[0].projectile
	projectile.motion_stages.assign([D.stage("wait")]); projectile.motion_stages[0].duration = 4
	var actor = moving.simulation.emit_projectile(project.barrages[0].id, Vector2(100, 0), PI, moving.simulation.allocate_owner())
	advance(world, 1)
	check(moving.location.is_equal_approx(Vector2(240, 0)) and stationary.location.is_equal_approx(Vector2(320, 100)), "跟随卷轴的敌人左移，独立战斗敌人不受卷轴影响")
	check(moving.position == Vector2.ZERO and moving.simulation.position == Vector2.ZERO and actor.position == Vector2(100, 0), "敌人根节点保持稳定，已发出子弹不跟着敌人移动")
	check(is_equal_approx(world.scroll.distance, 80), "背景与实体使用同一个推进距离")
	world.player = Vector2(-200, 40); world.reset_player_sample()
	check(not moving.simulation.player_sample_valid and moving.simulation.previous_player == world.player, "暂停移动后每个敌人重新采样玩家速度")
	world.free()

	project = basic()
	project.barrages[0].projectile.motion_stages.assign([D.stage("wait")]); project.barrages[0].projectile.motion_stages[0].duration = 0.8
	var skill = project.barrages[0]; skill.fire_pattern.count = 1; skill.fire_pattern.rounds = 3; skill.fire_pattern.interval = 0.5
	var fire = D.action("fire", skill.id); fire.windup = 0; fire.recovery = 0
	project.bosses[0].phases[0].behavior_flow = D.flow([fire])
	project.bosses[0].entity_settings.lifetime = 0.3
	world = world_for(project)
	advance(world, 0.4)
	check(not world.completed and world.entities[0].is_resolved() and not world.actors.is_empty(), "敌人离场后停止行为，但等待旧子弹自然结束")
	advance(world, 0.2)
	check(world.actors.size() == 1, "敌人离场会取消未来轮次，不在离场后继续发射")
	advance(world, 1)
	check(world.completed and world.actors.is_empty(), "旧攻击结束后片段完成")
	world.free()

	project = basic()
	project.levels[0].segments[0].events[0].spawn_position = Vector2(80, 0)
	world = world_for(project)
	for i in 180:
		world.shoot_player(); world.step()
	check(world.completed and world.resolved_entities.values().has("died"), "测试射击从左向右命中敌人并真正完成清场")
	world.free()

	project = basic()
	var obstacle_definition = D.obstacle()
	obstacle_definition.entity_settings.body_radius = 24
	obstacle_definition.entity_settings.lifetime = 0
	project.obstacles.append(obstacle_definition)
	var obstacle = D.wave(obstacle_definition.id, true); obstacle.count = 1
	project.waves.append(obstacle)
	project.levels[0].segments[0].events.clear(); project.levels[0].segments[0].duration = 5
	world = world_for(project)
	world.spawn_entity(obstacle, world.player + Vector2(10, 0), world.segment().id)
	advance(world, 0.1)
	check(world.hits == 1, "障碍物不开 AI，仍能接触命中玩家")
	var rock = world.spawn_entity(obstacle, Vector2(-460, 100), world.segment().id)
	var rock_id = rock.instance_id
	advance(world, 1.6)
	check(world.resolved_entities.get(rock_id) == "escaped", "越过左边界的障碍上报逃离并回收")
	world.free()

	world = STGLevelSimulation.new(); root.add_child(world)
	world.reset(demo, "levels", demo.levels[0].id, 2)
	advance(world, 12)
	check(world.segment_index == 2 and world.waiting_clear and world.scroll.distance == 0, "可以从 Boss 片段测试，卷轴停止但战斗继续")
	world.damage_entity(world.entities[0].instance_id, 100)
	world.step()
	check(world.completed, "击败 Boss 才能结束关卡")
	world.free()

	project = basic()
	check(ResourceSaver.save(project, "user://level_roundtrip.tres") == OK, "关卡资源可以保存")
	var loaded: STGProject = ResourceLoader.load("user://level_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded.validate().is_empty() and loaded.levels[0].segments[0].events[0].wave_id == loaded.waves[0].id, "重开保留事件、编队与敌人引用")
	var snapshot = project.snapshot()
	snapshot.levels[0].segments[0].events[0].spawn_position.x += 20
	check(snapshot.levels[0].segments[0].events[0].spawn_position != project.levels[0].segments[0].events[0].spawn_position, "关卡快照不共享可编辑事件")
	project.levels[0].segments[0].events[0].wave_id = "missing"
	check(not project.validate().is_empty(), "拒绝丢失的编队引用")
	project = basic(); project.levels[0].segments[0].events[0].at = 99
	check(not project.validate().is_empty(), "拒绝超出片段时长的事件")
	project = basic()
	obstacle_definition = D.obstacle()
	obstacle_definition.entity_settings.destructible = false
	obstacle_definition.entity_settings.lifetime = 0
	project.obstacles.append(obstacle_definition)
	obstacle = D.wave(obstacle_definition.id, true)
	obstacle.counts_for_clear = true
	project.waves.append(obstacle)
	project.levels[0].segments[0].scroll_speed = 0
	project.levels[0].segments[0].events[0].wave_id = obstacle.id
	check(not project.validate().is_empty(), "卷轴停止时不允许永不离场的无敌障碍阻塞清场")
	var prefab = load("res://examples/levels/level_demo.tscn").instantiate()
	prefab.autoplay = false; root.add_child(prefab); prefab.set_physics_process(false); prefab.play()
	prefab.set_player(Vector2(-200, 50)); advance(prefab.simulation, 1)
	check(prefab.simulation is STGLevelSimulation and prefab.simulation.issue.is_empty() and not prefab.simulation.entities.is_empty(), "独立关卡场景使用正式关卡运行器")
	prefab.stop(); prefab.free()
	print("LEVEL RUNTIME RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


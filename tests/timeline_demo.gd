extends SceneTree
## 新示例的完整战斗与导出接口：实际等待不会改写后续事件，Boss 目标必须真实击败。
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func advance(world, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): world.step()

func run() -> void:
	var project: STGProject = load("res://presets/timeline_demo.tres")
	check(project != null and project.schema_version == STGProject.VERSION and project.validate().is_empty(), "新版时间轴示例配置合法")
	if project == null or not project.validate().is_empty(): quit(1); return
	var level = project.levels[0]
	var world = STGLevelSimulation.new()
	root.add_child(world)
	world.reset(project, "levels", level.id)
	world.player = Vector2(5000, 5000)
	advance(world, 7.1)
	check(world.segment_index == 1 and world.issue.is_empty(), "巡航按计划结束并进入遭遇阶段")
	advance(world, 8)
	check(world.segment_index == 1 and world.waiting_clear and world.entities.any(func(entity): return entity.simulation != null and not entity.is_resolved()), "计划时长后仍等待活着的遭遇敌人")
	check(is_equal_approx(world.planned_time(), 13) and world.time > 15 and world.status().contains("已等待"), "计划游标停在遭遇末尾，实际时钟与等待提示继续增长")
	for entity in world.entities.duplicate():
		if entity.simulation != null and not entity.is_resolved(): world.damage_entity(entity.instance_id, 100)
	advance(world, 0.1)
	check(world.segment_index == 2 and not world.completed and is_equal_approx(level.segments[2].events[0].at, 0), "清场后Boss事件从新阶段局部零秒触发，配置不改写")
	advance(world, 13)
	check(world.segment_index == 2 and world.waiting_clear and not world.completed and world.scroll.displacement.is_zero_approx(), "Boss战卷轴停止，超过计划长度仍等待真实击败")
	for entity in world.entities.duplicate():
		if entity.simulation != null and not entity.is_resolved(): world.damage_entity(entity.instance_id, 100)
	advance(world, 0.1)
	check(world.completed and world.issue.is_empty() and world.entities.is_empty(), "Boss击败后完整示例结束并清理实例")
	world.free()
	var prefab = load("res://examples/levels/timeline_demo.tscn").instantiate()
	prefab.autoplay = false
	prefab.position = Vector2(100, 50)
	prefab.scale = Vector2(2, 2)
	root.add_child(prefab)
	prefab.set_physics_process(false)
	prefab.play()
	prefab.set_player(Vector2(120, 70), 8)
	check(prefab.simulation is STGLevelSimulation and prefab.simulation.issue.is_empty() and prefab.simulation.player.is_equal_approx(Vector2(10, 10)) and is_equal_approx(prefab.simulation.player_radius, 4), "导出场景复用关卡运行器，玩家世界坐标与半径正确换算")
	prefab.stop()
	prefab.free()
	print("TIMELINE DEMO RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

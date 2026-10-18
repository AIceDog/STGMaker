extends SceneTree
## 阶段条件与实体生命周期回归：计划时间、真实战斗时间、未生成成员与真实死亡分开。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred() # Godot 回调。

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func advance(world, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): world.step()

func basic(mode: String = "time_and_condition", condition: String = "clear") -> STGProject:
	var project = STGProject.create()
	D.populate(project)
	project.bosses[0].phases.resize(1)
	var idle = D.action(); idle.windup = 0; idle.recovery = 0; idle.duration = 20
	project.bosses[0].phases[0].behavior_flow = D.flow([idle])
	project.bosses[0].entity_settings = D.entity_settings()
	var wave = D.wave(project.bosses[0].id); wave.count = 1
	project.waves.append(wave)
	var level = D.level(wave.id)
	level.segments[0].duration = 0.1
	level.segments[0].events[0].spawn_position = Vector2(250, 0)
	level.segments[0].exit_rule = D.level_exit_rule(mode)
	level.segments[0].exit_rule.condition = condition
	project.levels.append(level)
	return project

func world_for(project: STGProject) -> STGLevelSimulation:
	var world = STGLevelSimulation.new(); root.add_child(world)
	world.reset(project, "levels", project.levels[0].id)
	check(world.issue.is_empty(), "测试项目可运行：" + world.issue)
	return world

func run() -> void:
	var project = basic("condition")
	var event = project.levels[0].segments[0].events[0]
	event.at = 0.08
	var world = world_for(project)
	advance(world, 0.04)
	check(not world.completed and world.entities.is_empty(), "目标条件包含尚未触发的出场事件，空屏不能提前推进")
	advance(world, 0.04)
	world.damage_entity(world.entities[0].instance_id, 100); world.step()
	check(world.completed and world.time < 0.1, "只按目标结束的阶段允许早于计划时长推进")
	check(is_equal_approx(world.planned_time(), 0.1), "最后阶段提前结束时，计划完成游标仍落在整关末尾")
	world.free()

	project = basic("time_and_condition")
	world = world_for(project); world.step()
	world.damage_entity(world.entities[0].instance_id, 100)
	advance(world, 0.04)
	check(not world.completed and not world.waiting_clear, "到时且目标满足：提前击败敌人仍等待计划时长")
	advance(world, 0.06)
	check(world.completed, "计划时长与目标都满足才继续")
	world.free()

	project = basic("condition", "defeat_target")
	project.waves[0].count = 2; project.waves[0].interval = 0.25
	project.waves[0].counts_for_clear = false
	project.levels[0].segments[0].exit_rule.target_event_id = project.levels[0].segments[0].events[0].id
	world = world_for(project); world.step()
	world.damage_entity(world.entities[0].instance_id, 100); advance(world, 0.1)
	check(not world.completed and world.waiting_clear and world.wave_jobs.size() == 1, "指定批次包含所有未生成成员，且不依赖清场计数开关")
	advance(world, 0.15)
	check(world.entities.size() == 1 and not world.completed, "编队生成条结束只表示生成结束，剩余敌人继续存在")
	world.damage_entity(world.entities[0].instance_id, 100); world.step()
	check(world.completed and world.resolved_entities.size() == 2, "指定批次所有成员真正死亡后阶段结束")
	world.free()

	for condition in ["clear", "defeat_all"]:
		project = basic("time_and_condition", condition)
		project.bosses[0].entity_settings.lifetime = 0.15
		project.barrages[0].projectile.motion_stages.assign([D.stage("wait")]); project.barrages[0].projectile.motion_stages[0].duration = 1
		project.barrages[0].projectile.lifecycle.warning = 0; project.barrages[0].projectile.lifecycle.fade = 0
		world = world_for(project); world.step()
		if condition == "defeat_all":
			var enemy = world.entities[0]
			enemy.simulation.emit_projectile(project.barrages[0].id, Vector2(100, 100), 0, enemy.simulation.allocate_owner())
		advance(world, 0.2)
		if condition == "clear":
			check(world.completed and world.resolved_entities.values().has("timeout"), "清场接受超时离场结果")
		else:
			check(not world.completed and world.issue.is_empty() and world.condition_failure.contains("已离场") and world.resolved_entities.values().has("timeout"), "全部击败拒绝把超时离场当成死亡，并报告不能达成的目标")
			var actual = world.time; var simulation_time = world.entities[0].simulation.time
			advance(world, 0.1)
			check(world.time > actual and world.entities[0].simulation.time > simulation_time and not world.actors.is_empty(), "击败目标离场后阻止阶段推进，实际计时、卷轴与旧攻击继续运行")
		world.free()

	# 条件集合由敌人决定；障碍可计入清场，但“全部击败”只计算敌人。
	project = basic("condition", "defeat_all")
	project.waves[0].counts_for_clear = false
	var obstacle = D.obstacle(); project.obstacles.append(obstacle)
	var rocks = D.wave(obstacle.id, true); rocks.count = 1; rocks.counts_for_clear = true
	project.waves.append(rocks)
	project.levels[0].segments[0].events.append(D.level_event(rocks.id))
	world = world_for(project); world.step()
	world.damage_entity(world.entities[0].instance_id, 100); world.step()
	check(world.completed and world.resolved_entities.values().has("phase_end"), "全部击败包含未勾清场的敌人，且不要求击败障碍")
	world.free()

	project = basic("condition", "defeat_target")
	project.levels[0].segments[0].exit_rule.target_event_id = project.levels[0].segments[0].events[0].id
	world = world_for(project)
	world.segment().exit_rule.target_event_id = "missing_after_reset"; world.step()
	check(not world.completed and world.issue.contains("击败目标"), "运行期间目标引用丢失也不能把空目标当作达成")
	world.free()

	# 第一阶段延长，第二阶段事件保持自己的阶段内时间。
	project = basic()
	project.bosses[0].entity_settings.lifetime = 0.3
	var next = D.level_segment(project.waves[0].id); next.duration = 0.2
	next.exit_rule = D.level_exit_rule("time"); next.events[0].at = 0.1
	project.levels[0].segments.append(next)
	world = world_for(project); advance(world, 0.2)
	check(world.segment_index == 0 and world.waiting_clear and world.time > world.planned_time() and world.status().contains("已等待"), "计划指针到阶段末尾后保持，实际战斗计时与等待提示继续增加")
	var enemy_age = world.entities[0].age
	advance(world, 0.05)
	check(world.entities[0].age > enemy_age and world.scroll.distance > 16, "等待目标时敌人行为与卷轴继续运行")
	advance(world, 0.1)
	check(world.segment_index == 1 and world.entities.is_empty() and is_equal_approx(next.events[0].at, 0.1), "后续阶段整体延后，不改写后续事件的阶段内时间")
	advance(world, 0.06)
	check(world.entities.size() == 1 and world.time > 0.4, "后续出场从真实阶段开始计时")
	world.free()

	for persists in [false, true]:
		project = basic("time")
		project.waves[0].count = 3; project.waves[0].interval = 0.1
		project.bosses[0].entity_settings.persist_across_segments = persists
		next = D.level_segment(); next.duration = 0.5; next.exit_rule = D.level_exit_rule("time")
		project.levels[0].segments.append(next)
		world = world_for(project); advance(world, 0.25)
		if persists:
			check(world.segment_index == 1 and world.entities.size() == 3 and world.entities[0].age > 0.2, "持续敌人和未生成编队成员跨阶段继续存在，AI正常推进")
		else:
			check(world.segment_index == 1 and world.entities.is_empty() and world.wave_jobs.is_empty() and world.resolved_entities.size() == 2, "不跨阶段的敌人结束，尚未生成成员取消出场")
		world.free()

	for wait_attacks in [false, true]:
		project = basic()
		project.levels[0].segments[0].exit_rule.wait_attacks = wait_attacks
		project.bosses[0].entity_settings.lifetime = 0.1
		project.barrages[0].projectile.motion_stages.assign([D.stage("wait")]); project.barrages[0].projectile.motion_stages[0].duration = 0.5
		project.barrages[0].projectile.lifecycle.warning = 0; project.barrages[0].projectile.lifecycle.fade = 0
		world = world_for(project); world.step()
		var enemy = world.entities[0]
		enemy.simulation.emit_projectile(project.barrages[0].id, Vector2(100, 100), 0, enemy.simulation.allocate_owner())
		advance(world, 0.15)
		check(world.completed != wait_attacks, "阶段是否等待离场敌人的旧攻击，由 wait_attacks 控制")
		if wait_attacks:
			check(not world.actors.is_empty(), "敌人回收后已发攻击继续独立运行")
			advance(world, 0.5); check(world.completed, "旧攻击自然结束后清场阶段完成")
		world.free()

	# 屏幕外出生：未实际入场前不误回收；越过屏幕的粗步长也能判断真正入场。
	project = basic("time"); project.levels[0].segments[0].duration = 5
	project.levels[0].segments[0].events.clear()
	obstacle = D.obstacle(); obstacle.entity_settings.exit_boundary = "screen"
	project.obstacles.append(obstacle); rocks = D.wave(obstacle.id, true); rocks.count = 1; project.waves.append(rocks)
	world = world_for(project)
	var rock = world.spawn_entity(rocks, Vector2(700, 0), world.segment().id)
	advance(world, 0.1)
	check(not rock.is_resolved() and not rock.entered_screen, "屏幕外出生的障碍不会立即按屏幕边界回收")
	world.scroll.displacement = Vector2(-1500, 0); rock.tick(world, 0.1)
	check(rock.entered_screen and rock.resolved_reason == "escaped", "一次位移扫过屏幕后越界，正确上报离场")
	world.free()

	project = basic(); obstacle = D.obstacle(); obstacle.entity_settings.destructible = false
	project.obstacles.append(obstacle)
	world = STGLevelSimulation.new(); root.add_child(world); world.reset(project, "obstacles", obstacle.id)
	check(world.issue.is_empty() and project.waves.size() == 1 and world.project != project, "独立障碍预览复用正式出场接口，并且不向项目加入临时编队")
	advance(world, 12)
	check(world.completed, "不可破坏障碍的独立预览可以按时间结束")
	world.free()
	print("LEVEL CONDITIONS RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


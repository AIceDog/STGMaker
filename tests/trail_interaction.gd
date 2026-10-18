extends SceneTree
## 尾迹由独立招式生成，移动由敌人动作负责；覆盖采样、判定、收尾和成品坐标。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const Movement = preload("res://stg/runtime/boss/movement_player.gd")
const Prefab = preload("res://stg/runtime/prefab_root.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
var checks = 0
var failures = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func advance(world, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): world.step()
func run() -> void:
	var project = STGProject.create(); Defaults.populate(project)
	var skill: STGBarrageSkill = project.barrages[-1]
	var material: STGBulletDefinition = project.find("bullets", skill.projectile.bullet_id)
	var enemy = Defaults.trail_boss(skill.id); enemy.phases[0].loop = false; project.bosses.append(enemy)
	check(project.validate().is_empty() and skill.fire_pattern.count == 1, "尾迹使用单套发射配置与独立弹体")
	check(enemy.phases[0].behavior_flow.nodes[0].action.movement.mode == "orbit", "缩圈移动显式配置在敌人行为动作")
	var sim = STGSimulation.new(); root.add_child(sim); sim.reset(project, "bosses", enemy.id)
	check(sim.player == CombatSpace.PLAYER_SPAWN and sim.boss == CombatSpace.ENEMY_SPAWN, "默认战斗坐标保持横向射击距离")
	advance(sim, 0.4); check(sim.boss == CombatSpace.ENEMY_SPAWN and sim.actors.is_empty(), "动作前摇期间不提前移动或生成尾迹")
	advance(sim, 1.1); check(sim.boss.distance_to(sim.player) < 640 and not sim.actors.is_empty(), "敌人边缩圈移动边释放独立尾迹招式")
	var trail: STGBulletTrailActor = sim.actors[0]
	check(trail.segments.size() > 3, "连续移动采样生成沿真实路径的多段攻击带")
	var old_point: Vector2 = trail.segments[-1].a; var born: float = trail.segments[-1].born
	sim.player += Vector2(60, 30); sim.step()
	check(trail.segments.any(func(part): return part.born == born and part.a == old_point), "圆心移动不改变已有尾迹的战斗坐标")
	check(sim.boss.distance_to(sim.player) < 640, "环绕移动可持续跟随玩家圆心")
	advance(sim, 10); check(sim.completed and sim.actors.is_empty() and sim.barrages.is_empty(), "停止采样后等待每段淡出再完成")
	sim.free()

	sim = STGSimulation.new(); root.add_child(sim)
	var orbit = Defaults.movement("orbit"); orbit.duration = 2; orbit.target_mode = "player"; orbit.target = Vector2.ZERO
	orbit.orbit_end_radius = 20; orbit.orbit_turns = 1; orbit.orbit_follow_center = false
	sim.boss = Vector2(100, 0); sim.player = Vector2.ZERO
	var mover = Movement.new(); mover.prepare(sim, orbit); mover.start(sim)
	check(sim.boss == Vector2(100, 0), "开始环绕时没有半径跳变")
	mover.tick(sim, 1); check(sim.boss.is_equal_approx(Vector2(-60, 0)), "按曲线缩到中间半径")
	sim.player = Vector2(300, 0); mover.tick(sim, 1); check(sim.boss.is_equal_approx(Vector2(20, 0)) and mover.completed, "锁定圆心且移动到结束半径")
	orbit.orbit_follow_center = true; sim.boss = Vector2(100, 0); sim.player = Vector2.ZERO
	mover = Movement.new(); mover.prepare(sim, orbit); mover.start(sim); sim.player = Vector2(10, 20); mover.tick(sim, 0.5)
	check(sim.boss.is_equal_approx(Vector2(10, 100)), "持续跟随模式读取玩家当前坐标")
	orbit.orbit_progress_curve = Defaults.curve([Vector2.ZERO, Vector2(0.5, 0), Vector2.ONE]); sim.boss = Vector2(100, 0); sim.player = Vector2.ZERO
	mover = Movement.new(); mover.prepare(sim, orbit); mover.start(sim); mover.tick(sim, 1)
	check(is_equal_approx(sim.boss.length(), 100), "可编辑曲线让前半段保持半径")
	sim.free()

	sim = STGSimulation.new(); root.add_child(sim); sim.reset(project, "barrages", skill.id); sim.clear_attacks()
	trail = sim.emit_projectile(skill.id, Vector2.ZERO, 0, sim.allocate_owner())
	trail.segments = [{"a": Vector2.ZERO, "b": Vector2(50, 0), "born": 0.0, "distance": 0.0}]
	sim.player = Vector2(25, 0); trail.tick(sim, 0.05); check(sim.hits == 0 and not trail.is_active(trail.age), "每段预警期间无碰撞伤害")
	trail.tick(sim, 0.1); check(sim.hits == 1 and sim.player_last_hit_at == sim.time, "每段生效时命中并记录受击时间")
	trail.tick(sim, 0.01); check(sim.hits == 1, "持续命中模式每条尾迹只命中一次")
	trail.hit_once = false; trail.age = trail.lifecycle.warning + trail.motion_stages[0].duration + 0.2; trail.tick(sim, 0.01)
	check(sim.hits == 1 and trail.segment_opacity(trail.age) < 1, "淡出阶段逐渐透明且不再伤害")
	trail.age = 0; trail.segments.clear(); trail.last_emitter = Vector2.ZERO; trail.has_sample = false
	trail.definition = material.duplicate(true); trail.definition.trail_offset = 0
	trail._sample(Vector2(10, 0)); trail._sample(Vector2(20, 0)); check(trail.segments.size() == 1, "正常位移连接尾迹")
	trail._sample(Vector2(500, 0)); trail._sample(Vector2(510, 0)); trail._sample(Vector2(520, 0))
	check(trail.segments.size() == 2 and trail.segments[-1].a.x > 450, "瞬移后重新采样，不生成跨屏攻击段")
	trail.segments.clear(); trail.emitter_path.clear(); trail.path_distance = 0; trail.has_sample = false; trail.last_emitter = Vector2.ZERO; trail.definition.trail_offset = 10
	for point in [Vector2(10, 0), Vector2(20, 0), Vector2(20, 10), Vector2(20, 20)]: trail._sample(point)
	check(trail.segments[-1].a == Vector2(20, 0) and trail.segments[-1].b == Vector2(20, 10), "尾部偏移沿真实拐弯路径取点")
	trail.segments = [{"a": Vector2.ZERO, "b": Vector2(50, 0), "born": 0.0, "distance": 0.0}, {"a": Vector2(50, 0), "b": Vector2(80, 0), "born": 1.0, "distance": 50.0}]
	trail.age = 2.1; sim.player = Vector2(5000, 5000)
	check(trail.segment_opacity(trail.age) < trail.segment_opacity(trail.age - 1), "旧段比新段更早淡出")
	trail.tick(sim, 0.3); check(trail.segments.size() == 1 and trail.alive, "旧段寿命结束只删除旧段")
	trail.tick(sim, 1); check(not trail.alive and trail.segments.is_empty(), "全部段过期后释放尾迹实例")
	sim.clear_attacks(); var instance = sim.play_barrage(skill.id, sim.boss); sim.step(); trail = sim.actors[0]
	for i in 5: sim.boss += Vector2(10, 0); sim.step()
	var segments_before = trail.segments.size(); instance.cancel(); sim.boss += Vector2(20, 0); sim.step()
	check(not trail.recording and trail.segments.size() == segments_before, "取消发射停止后续采样并保留已有段")
	check(not instance.is_finished(sim), "已有尾迹未结束时招式仍在收尾")
	advance(sim, 3); check(instance.is_finished(sim) and sim.actors.is_empty(), "取消后的旧段按寿命清理")
	sim.free()
	check(ResourceSaver.save(project, "user://trail_roundtrip.tres") == OK, "显式尾迹与敌人行为可序列化")
	var loaded = ResourceLoader.load("user://trail_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded.validate().is_empty() and loaded.bosses[-1].phases[0].behavior_flow.nodes[0].action.movement.mode == "orbit", "重开后移动配置仍属于敌人动作")

	var prefab = Prefab.new(); prefab.autoplay = false; prefab.library = project; prefab.kind = "barrages"; prefab.resource_id = skill.id
	prefab.position = Vector2(100, 200); root.add_child(prefab); prefab.set_physics_process(false); prefab.play(); prefab.set_player(Vector2(100, 430))
	check(prefab.simulation.boss == Vector2.ZERO and prefab.simulation.player == Vector2(0, 230), "成品招式以局部原点开始并转换玩家世界坐标")
	for i in 60: prefab.simulation.boss += Vector2(5, 0); prefab.simulation.step()
	check(prefab.simulation.actors[0] is STGBulletTrailActor and not prefab.simulation.actors[0].segments.is_empty(), "成品同样沿外部实际移动生成尾迹")
	advance(prefab.simulation, 9); check(prefab.simulation.completed, "成品尾迹在全部段消失后结束")
	prefab.free()
	print("TRAIL INTERACTION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

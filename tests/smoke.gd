extends SceneTree
## 正式运行集成：类型资源、实例隔离、发射时序、变形、碰撞、阶段和固定随机数。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
var checks = 0
var failures = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func advance(sim, frames: int) -> void:
	for i in frames: sim.step()
func fresh() -> STGProject:
	var project = STGProject.create(); Defaults.populate(project); return project
func world(project, collection: String, id: String) -> STGSimulation:
	var instance = STGSimulation.new(); root.add_child(instance); instance.reset(project, collection, id); instance.player = Vector2(5000, 5000); return instance
func single(attack: STGBarrageSkill, angle: float = 180) -> void:
	attack.fire_pattern.count = 1; attack.fire_pattern.rounds = 1; attack.fire_pattern.angle = angle; attack.fire_pattern.anchor = "origin"
func run() -> void:
	var project = fresh()
	check(project.validate().is_empty(), "默认类型化资源合法")
	check(project.bullets.size() == 4 and project.barrages.size() == 6, "四种子弹素材与六种独立招式示例")
	var copy = project.snapshot()
	copy.barrages[0].projectile.motion_stages[0].path.set_point_position(1, Vector2(999, 999))
	check(project.barrages[0].projectile.motion_stages[0].path.get_point_position(1) != Vector2(999, 999), "快照不共享可编辑运动曲线")
	check(copy.bullets[0].scene == project.bullets[0].scene, "快照共享只读场景")
	check(ResourceSaver.save(project, "user://simple_roundtrip.tres") == OK, "当前格式项目保存")
	var loaded = ResourceLoader.load("user://simple_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded is STGProject and loaded.validate().is_empty(), "类型资源保存重开")
	check(loaded.barrages[0].projectile.motion_stages[0].path.point_count == 3 and loaded.barrages[0].projectile.bullet_id == project.bullets[0].id, "路径和素材引用保留")
	var sim = world(project, "barrages", project.barrages[0].id)
	advance(sim, 1)
	check(sim.actors.size() == 9 and sim.actors[0] is STGBulletActor, "扇形实例化真实子弹场景")
	check(sim.actors[0].definition == sim.actors[1].definition and sim.actors[0] != sim.actors[1], "素材共享、运行实例独立")
	advance(sim, 60)
	check(sim.actors.size() >= 18, "轮次发射")
	advance(sim, 700)
	check(sim.completed and sim.actors.is_empty(), "等待子弹和淡出自然完成")
	sim.free()
	project = fresh()
	var child = project.barrages[4]
	single(child); child.projectile.lifecycle.warning = 0.1; child.projectile.lifecycle.fade = 0.2; child.projectile.motion_stages[0].duration = 0.2
	var parent = project.barrages[0]
	single(parent); parent.projectile.motion_stages[0].duration = 0.1
	var transform = Defaults.stage("transform"); transform.transform_attack_id = child.id
	parent.projectile.motion_stages.append(transform)
	sim = world(project, "barrages", parent.id)
	var job = sim.barrages[0]
	advance(sim, 15)
	check(sim.actors.size() == 1 and sim.actors[0].definition.id == child.projectile.bullet_id, "阶段终点变成目标招式的区域弹体")
	check(sim.actors[0].owner_id == job.owner_id and not job.is_finished(sim), "变形继承归属并继续等待")
	advance(sim, 70); check(job.is_finished(sim), "子区域淡出后完成")
	sim.free()
	project = fresh()
	var laser = project.barrages[3]; single(laser)
	laser.projectile.lifecycle.warning = 0.1; laser.projectile.motion_stages[0].duration = 0.2; laser.projectile.lifecycle.fade = 0.1
	project.bullets[1].collision.offset = Vector2.ZERO
	sim = world(project, "barrages", laser.id); sim.player = sim.boss + Vector2(-100, 0)
	advance(sim, 6); check(sim.hits == 0, "激光预警无伤害")
	advance(sim, 15); check(sim.hits == 1, "激光生效使用几何判定")
	advance(sim, 50); check(sim.actors.is_empty(), "激光淡出结束")
	sim.free()
	project = fresh(); single(project.barrages[0])
	project.barrages[0].projectile.motion_stages[0].duration = 0.3
	var boss = project.bosses[0]; boss.phases[0].loop = false
	var fire = Defaults.action("fire", project.barrages[0].id); fire.windup = 0; fire.recovery = 0
	boss.phases[0].behavior_flow = Defaults.flow([fire, Defaults.action("teleport")])
	sim = world(project, "bosses", boss.id); advance(sim, 20)
	check(sim.boss_player.context.active_node_id == boss.phases[0].behavior_flow.nodes[0].id and not sim.actors.is_empty(), "敌人动作等待真实攻击结束")
	sim.hp = 40; advance(sim, 5); check(sim.boss_player.phase_index == 0, "低血量等待当前动作结束")
	advance(sim, 100); check(sim.boss_player.phase_index == 1, "动作完成后进入低血量阶段")
	sim.hp = 0; advance(sim, 1); check(sim.boss_player.finished and sim.actors.is_empty(), "死亡清理攻击并终止行为")
	sim.free()
	project = fresh()
	var transform_a = Defaults.stage("transform"); transform_a.transform_attack_id = project.barrages[1].id
	var transform_b = Defaults.stage("transform"); transform_b.transform_attack_id = project.barrages[0].id
	project.barrages[0].projectile.motion_stages.assign([transform_a]); project.barrages[1].projectile.motion_stages.assign([transform_b])
	check(not project.validate().is_empty(), "拒绝无限变形循环")
	project = fresh(); project.barrages[0].projectile.bullet_id = "missing"
	check(not project.validate().is_empty(), "拒绝丢失素材引用")
	project = fresh(); single(project.barrages[0])
	project.barrages[0].projectile.motion_stages.assign([Defaults.stage("aim")]); project.barrages[0].projectile.motion_stages[0].speed = 24000
	sim = world(project, "barrages", project.barrages[0].id); sim.player = sim.boss + Vector2(0, 100)
	advance(sim, 1); check(sim.hits == 1, "高速子弹连续扫掠不会穿过玩家")
	sim.free()
	project = fresh(); laser = project.barrages[3]; single(laser)
	project.bullets[1].beam_path = Defaults.path([Vector2.ZERO, Vector2(100, 80), Vector2(200, 0)])
	project.bullets[1].beam_path_size = project.bullets[1].collision.size; project.bullets[1].collision.offset = Vector2.ZERO
	laser.projectile.lifecycle.warning = 0
	sim = world(project, "barrages", laser.id); sim.player = sim.boss + Vector2(-100, -80)
	advance(sim, 1); check(sim.hits == 1, "曲线激光沿实际曲线判定")
	sim.free()
	project = fresh(); var area = project.barrages[4]; single(area)
	project.bullets[2].collision.kind = "ring"; project.bullets[2].collision.inner_ratio = 0.6; area.projectile.lifecycle.warning = 0
	sim = world(project, "barrages", area.id); sim.player = sim.boss
	advance(sim, 1); check(sim.hits == 0, "圆环中心空洞没有判定")
	sim.player = sim.boss + Vector2(65, 0); advance(sim, 1); check(sim.hits == 1, "圆环实体部分生效")
	sim.free()
	project = fresh(); single(project.barrages[0]); project.bullets[0].visual.geometry.size = Vector2(100, 100)
	project.barrages[0].projectile.motion_stages.assign([Defaults.stage("wait")])
	sim = world(project, "barrages", project.barrages[0].id); sim.player = sim.boss + Vector2(40, 0)
	advance(sim, 1); check(sim.hits == 0, "外观大小不改变独立碰撞体")
	sim.player = sim.boss; advance(sim, 1); check(sim.hits == 1, "独立圆形碰撞体有效")
	sim.free()
	project = fresh(); project.barrages[0].fire_pattern.direction = "random"
	var first = world(project, "barrages", project.barrages[0].id); var second = world(project, "barrages", project.barrages[0].id)
	advance(first, 100); advance(second, 100)
	var same = first.actors.size() == second.actors.size()
	for i in first.actors.size(): same = same and first.actors[i].position.is_equal_approx(second.actors[i].position)
	check(same, "固定种子随机方向可复现")
	first.free(); second.free()
	project = fresh(); project.bosses[0].phases[0].loop = false
	var wait = Defaults.action("wait"); wait.windup = 0; wait.recovery = 0; wait.duration = 0.02
	project.bosses[0].phases[0].behavior_flow = Defaults.flow([wait], true)
	sim = world(project, "bosses", project.bosses[0].id); advance(sim, 20); check(sim.boss_player.finished, "非循环随机行为执行一次结束")
	sim.free()
	print("SMOKE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

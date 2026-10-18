extends SceneTree
## 真实资源、逐个招式与敌人、连射重瞄、死亡演出和依赖导入的集成验证。
const Factory = preload("res://addons/stg_maker/authoring/templates/flytiger_enemy_library.gd")
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const Import = preload("res://addons/stg_maker/authoring/template_import.gd")
const Session = preload("res://addons/stg_maker/ui/session.gd")
const Movement = preload("res://stg/runtime/boss/movement_player.gd")
const Entity = preload("res://stg/runtime/level/entity_player.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func advance(world, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): world.step()
func world_for(project: STGProject, collection: String, id: String) -> STGSimulation:
	var result = STGSimulation.new()
	root.add_child(result)
	result.reset(project, collection, id)
	result.player = Vector2(-2000, -2000)
	return result


func attack_entry(project: STGProject, id: String) -> Dictionary:
	for collection in ["barrages", "behaviors"]:
		var asset = project.find(collection, id)
		if asset != null: return {"collection": collection, "asset": asset}
	return {"collection": "", "asset": null}

func world_for_attack(project: STGProject, id: String, preview: bool = false) -> STGSimulation:
	var entry = attack_entry(project, id + "_demo_behavior" if preview and project.find("behaviors", id + "_demo_behavior") != null else id)
	return world_for(project, entry.collection, entry.asset.id)

func run() -> void:
	var project = Factory.new().build()
	check(project.validate().is_empty(), "FlyTiger 工厂生成合法资源：" + "；".join(project.validate()))
	check(project.bosses.size() == 29 and project.barrages.size() >= 42, "28类小怪与1项补充机关均有攻击定义")
	for number in range(1, 43):
		var skill: Resource = attack_entry(project, "ft_skill_%02d" % number).asset
		check(skill != null and not skill.description.is_empty(), "表中第%d条招式完整并带来源口径" % number)
	var saved: STGProject = load("res://presets/flytiger_enemies.tres")
	check(saved != null and saved.validate().is_empty() and saved.bosses.size() == project.bosses.size(), "独立预设可以从磁盘重新加载")
	for skill in project.barrages:
		var world = world_for(project, "barrages", skill.id)
		var active_seen = false
		for i in 4800:
			world.step()
			active_seen = active_seen or not world.actors.is_empty() or world.boss.distance_to(Vector2(320, 0)) > 0.1
			if world.completed: break
		check(world.issue.is_empty() and world.boss.is_finite() and active_seen, skill.title + "：正式运行器执行发射 / 身体移动")
		check(world.completed and world.actors.is_empty() and world.barrages.is_empty(), skill.title + "：单次招式及分裂后继完整收尾")
		world.free()
	for enemy in project.bosses:
		var world = world_for(project, "bosses", enemy.id)
		var peak = 0
		for i in 1800:
			world.step()
			peak = maxi(peak, world.actors.size())
		check(world.issue.is_empty() and world.boss.is_finite() and peak < 500, enemy.title + "：敌人攻击流程稳定运行")
		world.damage_boss(100)
		advance(world, 10)
		check(world.completed and not world.boss_visible, enemy.title + "：死亡 / 死亡招式能收尾")
		world.free()
	test_salvos(project)
	test_fireball_branches(project)
	test_imports(project)
	test_death_delay()
	test_ballistic_body()
	test_loop_prefix()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_salvos(project: STGProject) -> void:
	var world = world_for_attack(project, "ft_skill_35")
	world.player = Vector2(-250, -80)
	world.step()
	check(world.actors.size() == 2, "双头飞蛇：第一对双头同时出弹")
	check(absf(wrapf(world.actors[0].rotation - Vector2(-590, -90).angle(), -PI, PI)) < 0.001 and absf(wrapf(world.actors[1].rotation - Vector2(-550, -70).angle(), -PI, PI)) < 0.001, "双头飞蛇：两头使用各自交叉目标偏移")
	var first_heading = world.actors[0].rotation
	world.player = Vector2(-250, 160)
	advance(world, 0.24)
	check(world.actors.size() == 4 and absf(world.actors[2].rotation - first_heading) > 0.1, "双头飞蛇：每对重新瞄准，已发子弹不跟随")
	advance(world, 0.45)
	check(world.actors.size() == 8, "双头飞蛇：4对共8发")
	world.free()

	world = world_for(project, "barrages", "ft_skill_36")
	world.player = Vector2(-250, -80)
	world.step()
	check(world.actors.size() == 1, "猫头鹰：首发只有1颗")
	advance(world, 1.30)
	check(world.actors.size() == 5, "猫头鹰：0.32秒间隔共5发")
	world.free()

func test_fireball_branches(project: STGProject) -> void:
	var world = world_for(project, "barrages", "ft_bullet_pig_fireball_projectile")
	world.clear_attacks()
	world.emit_projectile("ft_bullet_pig_fireball_projectile", world.boss, PI)
	world.player = world.boss
	world.step()
	check(world.hits == 0, "飞猪火球：命中母弹不重复结算伤害")
	world.player = Vector2(-2000, -2000)
	world.step()
	check(world.actors.filter(func(actor): return actor.definition.id == "ft_bullet_pig_flame_hit").size() == 12, "飞猪火球：命中玩家生成12碎片")
	world.free()
	world = world_for(project, "barrages", "ft_bullet_pig_fireball_projectile")
	world.clear_attacks()
	world.emit_projectile("ft_bullet_pig_fireball_projectile", world.boss, PI)
	advance(world, 4.1)
	check(world.actors.filter(func(actor): return actor.definition.id == "ft_bullet_pig_flame_expire").size() == 4, "飞猪火球：4秒到期生成4碎片")
	world.free()

func test_imports(source: STGProject) -> void:
	for collection in ["barrages", "behaviors", "bosses"]:
		for original in source.get(collection):
			var target = STGProject.create()
			target.schema_version = STGProject.VERSION
			var bundle = Import.copy_bundle(target, source, collection, original.id)
			for entry in bundle.entries: target.get(entry[0]).append(entry[1])
			check(bundle.issues.is_empty() and target.validate().is_empty() and target.find(collection, bundle.selected_id) != null, original.title + "：单独导入包含全部递归依赖")
	var session = Session.new()
	session.create()
	var original_size = session.project.bosses.size()
	for repeat in 2:
		var bundle = Import.copy_bundle(session.project, source, "bosses", "ft_enemy_pig")
		session.edit(func(next):
			for entry in bundle.entries: next.get(entry[0]).append(entry[1]))
	check(session.project.validate().is_empty() and session.project.bosses.size() == original_size + 2, "重复导入同种敌人生成独立资源，不覆盖旧资源")
	session.undo()
	check(session.project.bosses.size() == original_size + 1 and session.project.validate().is_empty(), "一次撤销移除整套新模板及事件依赖")
	session.redo()
	check(session.project.bosses.size() == original_size + 2 and session.project.validate().is_empty(), "重做恢复完整模板依赖")

func test_death_delay() -> void:
	var project = STGProject.create()
	project.schema_version = STGProject.VERSION
	var zone = D.bullet("area")
	project.bullets.append(zone)
	var skill = D.barrage(zone.id, "area")
	skill.projectile.lifecycle.warning = 0
	skill.projectile.lifecycle.fade = 0
	skill.projectile.motion_stages[0].duration = 0.05
	skill.fire_pattern.anchor = "boss"
	skill.fire_pattern.at = 0.5
	project.barrages.append(skill)
	var death_action = D.action("fire", skill.id)
	death_action.windup = 0
	death_action.recovery = 0
	death_action.end_when = "both"
	death_action.movement = D.movement("ballistic")
	death_action.movement.duration = 0.5
	death_action.movement.initial_velocity = Vector2(40, -100)
	death_action.movement.gravity = 400
	var death_flow = D.flow([death_action])
	death_flow.id = "test_death_flow"
	project.behaviors.append(death_flow)
	var enemy = D.boss()
	enemy.on_death_behavior_id = death_flow.id
	project.bosses.append(enemy)
	var wave = D.wave(enemy.id)
	var entity = Entity.new()
	root.add_child(entity)
	entity.setup(project, wave, Vector2.ZERO, 1, "test")
	entity.damage(100)
	check(entity.resolved_reason == "died" and not entity.is_drained(), "死亡演出尚未生成爆炸时，关卡保留实体攻击容器")
	entity.simulation.player = Vector2(-2000, -2000)
	advance(entity.simulation, 0.6)
	check(entity.is_drained() and entity.simulation.completed, "落地后死亡攻击自然耗尽，容器可回收")
	entity.free()

func test_ballistic_body() -> void:
	var project = STGProject.create()
	project.schema_version = STGProject.VERSION
	var enemy = D.boss()
	project.bosses.append(enemy)
	var world = world_for(project, "bosses", enemy.id)
	world.boss = Vector2.ZERO
	world.player = Vector2(-500, 100)
	var move = D.movement("ballistic")
	move.target_mode = "player"
	move.velocity_mode = "horizontal"
	move.initial_velocity = Vector2(260, -700)
	move.gravity = 1500
	move.duration = 1
	var player = Movement.new()
	player.prepare(world, move)
	player.start(world)
	player.tick(world, 0.5)
	check(world.boss.distance_to(Vector2(-130, -162.5)) < 0.001, "羊头跳撞：水平朝向锁定，垂直使用重力解析运动")
	world.player = Vector2(500, 100)
	player.tick(world, 0.5)
	check(world.boss.distance_to(Vector2(-260, 50)) < 0.001, "跳跃出手后不持续转向玩家")
	world.free()

func test_loop_prefix() -> void:
	var project = STGProject.create()
	project.schema_version = STGProject.VERSION
	var bullet = D.bullet()
	project.bullets.append(bullet)
	var skill = D.barrage(bullet.id)
	skill.projectile.lifecycle.fade = 0
	skill.projectile.motion_stages[0] = D.stage("wait")
	skill.projectile.motion_stages[0].duration = 0.02
	skill.fire_pattern.count = 1
	skill.fire_pattern.rounds = 1
	project.barrages.append(skill)
	var enter = D.action()
	enter.windup = 0
	enter.recovery = 0
	enter.duration = 0.05
	var fire = D.action("fire", skill.id)
	fire.windup = 0
	fire.recovery = 0
	var enemy = D.boss()
	enemy.phases[0].behavior_flow = D.flow([enter, fire])
	var flow = enemy.phases[0].behavior_flow
	flow.loop_entry_id = flow.nodes[1].id
	project.bosses.append(enemy)
	check(project.validate().is_empty(), "指定循环起点使用合法无回连流程")
	var world = world_for(project, "bosses", enemy.id)
	var counts = {"enter": 0, "fire": 0}
	world.boss_action_event.connect(func(id, event):
		if event == "completed": counts["enter" if id == flow.nodes[0].id else "fire"] += 1)
	advance(world, 0.8)
	check(counts.enter == 1 and counts.fire > 3, "入场前缀执行一次，后续从攻击节点循环")
	check(world.boss_player.runner.branches.is_empty(), "循环重开不会积累随机分支调用栈")
	world.free()

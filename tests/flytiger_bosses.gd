extends SceneTree
## 按表格编号逐条运行，并验证血条切换、限时结束、重复判伤、召唤与递归导入。
const Factory = preload("res://addons/stg_maker/authoring/templates/flytiger_boss_library.gd")
const Import = preload("res://addons/stg_maker/authoring/template_import.gd")
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
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
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, collection, id)
	world.player = Vector2(-250, 80)
	return world


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
	check(project.validate().is_empty(), "Boss 工厂：" + "；".join(project.validate()))
	var bosses = project.bosses.filter(func(item): return item.id.begins_with("ft_boss_"))
	check(bosses.size() == 29, "29 个注册 Boss 全部覆盖")
	var saved: STGProject = load("res://presets/flytiger_bosses.tres")
	check(saved != null and saved.validate().is_empty() and saved.bullets.size() == project.bullets.size(), "独立预设重新加载完整")
	for number in range(1, 186):
		var skill: Resource = attack_entry(project, "ft_boss_skill_%03d" % number).asset
		check(skill != null and ("第 %d 行" % (number + 6)) in skill.description, "第%d条招式带工作簿行号" % number)
		var world = world_for_attack(project, skill.id, true)
		var seen = false
		for i in 6000:
			world.step()
			seen = seen or not world.actors.is_empty() or not world.summons.is_empty() or world.boss.distance_to(Vector2(320, 0)) > 0.1
			if world.completed: break
		var empty_behavior = skill is STGBehaviorFlow and skill.nodes.all(func(node): return node.kind == "wait")
		check((seen or empty_behavior) and world.issue.is_empty() and world.boss.is_finite(), skill.title + " 使用正式招式或显式行为执行")
		check(world.completed and world.actors.is_empty() and world.summons.is_empty(), skill.title + " 单次完整收尾")
		world.free()
	for boss in bosses:
		var world = world_for(project, "bosses", boss.id)
		advance(world, 12)
		check(world.issue.is_empty() and world.boss.is_finite(), boss.title + " 默认行为稳定运行")
		for phase in boss.phases:
			for node in phase.behavior_flow.nodes:
				if node.action == null: continue
				check(node.action.attack.barrage_id not in ["ft_boss_skill_002", "ft_boss_skill_178", "ft_boss_skill_179", "ft_boss_skill_180", "ft_boss_skill_181", "ft_boss_skill_185"] and node.action.attack.behavior_id not in ["ft_boss_skill_002", "ft_boss_skill_178", "ft_boss_skill_179", "ft_boss_skill_180", "ft_boss_skill_181", "ft_boss_skill_185"], boss.title + " 不调用源码未接入分支")
		world.free()
	for collection in ["bosses", "barrages", "behaviors"]:
		var entries = bosses if collection == "bosses" else project.get(collection).filter(func(item): return item.id.begins_with("ft_boss_skill_") and item.id.length() == 17)
		for entry in entries:
			var target = STGProject.create(); target.schema_version = STGProject.VERSION
			var bundle = Import.copy_bundle(target, project, collection, entry.id)
			for part in bundle.entries: target.get(part[0]).append(part[1])
			check(bundle.issues.is_empty() and target.validate().is_empty(), entry.title + " 单独导入含后继 / 召唤依赖")
	test_lives(project)
	test_collision(project)
	test_summons(project)
	test_aim_and_gaps(project)
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_lives(project: STGProject) -> void:
	var world = world_for(project, "bosses", "ft_boss_BossMan")
	world.damage_boss(100)
	check(world.hp == 100 and world.boss_player.phase().life == 1 and not world.boss_player.death_started, "第一条血耗尽立即进入下一条血，关卡不会误判死亡")
	check(world.boss_invulnerable, "新血条转场保护立即生效")
	world.damage_boss(50)
	check(world.hp == 100, "转场期间伤害被保护挡住")
	advance(world, 2.1)
	world.damage_boss(100)
	advance(world, 5)
	check(world.completed and world.hp == 0, "最后血条耗尽才真实死亡")
	world.free()
	world = world_for(project, "bosses", "ft_boss_Sphinx")
	advance(world, 13.6)
	check(world.boss_player.phase_index == 1 and world.hp == 100, "限时跨阶段不补当前血条")
	world.damage_boss(100)
	check(world.boss_player.phase_index == 2 and world.hp == 60, "狮身像前两阶段清血进入下一阶段并补 60%")
	world.damage_boss(100)
	check(world.boss_player.phase().life == 1 and world.hp == 100, "狮身像完整周期后新血条补满")
	world.free()
	world = world_for(project, "bosses", "ft_boss_AssassinKing")
	world.boss_player.phase_index = world.boss_player.definition.phases.size() - 1
	world.boss_player._enter_phase(world)
	advance(world, 18)
	check(world.hp == 0 and world.completed, "刺客末阶段限时终结，即使还有 HP 也结束")
	world.free()

func test_collision(project: STGProject) -> void:
	for number in [93,95,96,163,173,175]:
		var id = "ft_boss_skill_%03d" % number
		var entry = attack_entry(project, id)
		var source = entry.asset
		var attacks: Array = [source] if source is STGBarrageSkill else []
		if source is STGBehaviorFlow:
			for node in source.nodes:
				for branch in node.children:
					for shot in branch.nodes:
						if shot.kind == "attack": attacks.append(project.find("barrages", shot.barrage_id))
		check(not attacks.is_empty() and attacks.all(func(attack): return not attack.projectile.lifecycle.damage_on_contact), "无命中分支%d没有补造伤害" % number)
	var bullet = D.bullet("area")
	bullet.id = "repeat_test"
	bullet.visual.geometry.size = Vector2(200, 200)
	bullet.collision.size = Vector2(200, 200)
	var attack = D.barrage(bullet.id, "area")
	attack.projectile.lifecycle.warning = 0
	attack.projectile.lifecycle.fade = 0
	attack.projectile.lifecycle.hit_mode = "repeat"
	attack.projectile.lifecycle.hit_interval = 0.5
	attack.projectile.motion_stages[0].duration = 2
	var target = STGProject.create()
	target.bullets.append(bullet)
	target.barrages.append(attack)
	var world = world_for(target, "barrages", attack.id)
	world.player = world.boss
	advance(world, 1.1)
	check(world.hits == 3, "持续范围按实例间隔命中三次")
	world.free()
	var rotating = project.find("barrages", "ft_boss_skill_183")
	world = world_for(project, "barrages", rotating.id)
	advance(world, 1.8)
	check(not world.actors.is_empty() and absf(world.actors[0].rotation - PI) > 0.5, "双向旋转激光连续改变实际几何朝向")
	world.free()

func test_summons(project: STGProject) -> void:
	var world = world_for(project, "barrages", "ft_boss_skill_027")
	advance(world, 5)
	check(world.summons.size() == 12, "斧王按 0.38 秒间隔召唤十二个真实敌人")
	check(world.summons.all(func(child): return child.world.boss_player != null), "召唤敌人运行自身行为流程")
	var owner: int = world.summons[0].owner
	world.stop_owner(owner)
	check(world.summons.is_empty(), "取消归属同时清理召唤实体")
	world.free()
	var target = STGProject.create(); target.schema_version = STGProject.VERSION
	var boss = D.boss(); boss.id = "recursive"
	var skill = D.barrage(""); skill.id = "recursive_skill"
	skill.fire_pattern.enemy_id = boss.id
	boss.phases[0].behavior_flow = D.flow([D.action("fire", skill.id)])
	target.bosses.append(boss); target.barrages.append(skill)
	check(not target.validate().is_empty(), "递归召唤在运行前被校验阻止")

func test_aim_and_gaps(project: STGProject) -> void:
	var world = world_for_attack(project, "ft_boss_skill_160")
	world.step()
	var first_angle: float = world.actors[2].rotation
	world.player = Vector2(-250, -190)
	advance(world, .51)
	var second_wave = world.actors.filter(func(actor): return actor.definition.id.ends_with("b01"))
	check(second_wave.size() == 5 and absf(second_wave[2].rotation - first_angle) < .001, "刺客三波锁定首轮瞄准方向，不跟随新玩家位置")
	world.free()
	world = world_for_attack(project, "ft_boss_skill_164")
	world.player = Vector2(-300, 0)
	world.step()
	check(world.actors.size() == 5 and world.actors.all(func(actor): return absf(actor.position.x + 300) >= 50), "上下墙弹保留玩家 X 安全缺口")
	world.free()
	world = world_for(project, "bosses", "ft_boss_CraneSage")
	world.damage_boss(100)
	advance(world, 1)
	check(world.boss_invulnerable and world.actors.size() >= 3, "鹤仙十秒转场保护期间继续发射风弹")
	world.free()

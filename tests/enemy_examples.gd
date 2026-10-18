extends SceneTree
## 敌人库集成检查：测试实际移动 / 攻击、玩家距离分支、变形、阶段收尾和共享场景。
## 测试使用内存副本，不重新生成或保存示例库。
const Factory = preload("res://addons/stg_maker/authoring/templates/enemy_library.gd")
const LIBRARY_PATH = "res://presets/enemy_library.tres"
const RUNTIME_LIBRARY_PATH = "res://examples/shared/enemy_library.tres"
var checks = 0
var failures = 0

func _initialize() -> void: # Godot 回调
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func world_for(project: STGProject, id: String) -> STGSimulation:
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, "bosses", id)
	return world

func advance(world: STGSimulation, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP):
		world.step()

func run() -> void:
	var project: STGProject = load(LIBRARY_PATH)
	check(project != null and project.validate().is_empty(), "示例资源库可以读取且配置合法")
	if project == null:
		quit(1)
		return
	var built = Factory.new().build()
	check(built.validate().is_empty() and built.bosses.size() == 10, "配置工厂独立生成恰好十个合法敌人")
	check(project.bosses.size() == 10 and project.bullets.size() == 15 and project.find("behaviors", "commander_combo") != null, "库保留十个敌人、十五种素材及显式组合行为")
	check(built != project and built.barrages.size() == project.barrages.size() and built.behaviors.size() == project.behaviors.size(), "模板从同一套正式资产提供独立制作快照")
	var ids: Dictionary = {}
	for enemy in project.bosses:
		ids[enemy.id] = true
		check(enemy.texture != null and built.find("bosses", enemy.id) != null, enemy.title + "：图标与稳定资源 ID 完整")
		test_enemy(project, enemy)
	check(ids.size() == 10, "十个敌人的 ID 唯一")
	test_distance_branch(project)
	test_burrow(project)
	test_multistage(project)
	test_commander(project)
	await test_editor()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_enemy(project: STGProject, enemy: STGBossDefinition) -> void:
	# 模拟玩家不断横移；循环运行 30 秒检查位置、攻击生成和实例数量是否稳定。
	var world = world_for(project, enemy.id)
	var attack_seen = false
	var moved = false
	var peak = 0
	for i in 3600:
		world.player = Vector2(-270 + cos(world.time * 0.8) * 30, sin(world.time * 0.6) * 170)
		if enemy.id == "06_charger":
			world.player = Vector2(240 + cos(world.time * 0.8) * 30, sin(world.time * 0.6) * 80)
		world.step()
		attack_seen = attack_seen or not world.actors.is_empty()
		moved = moved or world.boss.distance_to(enemy.start_position) > 20
		peak = maxi(peak, world.actors.size())
	check(world.issue.is_empty() and world.boss.is_finite() and peak < 300, enemy.title + "：连续运行不报错、不无限积累攻击")
	check(attack_seen and moved and not world.action_completed_at.is_empty(), enemy.title + "：实际移动、发射并完成动作")
	world.damage_boss(100)
	world.step()
	check(world.completed and world.actors.is_empty() and not world.boss_visible, enemy.title + "：死亡清理全部攻击")
	world.free()
	# 关闭循环验证一轮能自然结束：只修改副本，避免改变策划资源。
	var copy = project.snapshot()
	for phase in copy.find("bosses", enemy.id).phases:
		phase.loop = false
	world = world_for(copy, enemy.id)
	world.player = Vector2(1000, 1000)
	advance(world, 35)
	check(world.completed and world.issue.is_empty(), enemy.title + "：一轮行为和攻击完整收尾")
	world.free()
	# 每个场景必须引用外部共享库，运行入口不能另外嵌入一份旧配置。
	var scene: PackedScene = load("res://examples/enemies/" + enemy.id + ".tscn")
	var actor = scene.instantiate()
	actor.autoplay = false
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.play()
	actor.set_player(Vector2(70, 140))
	advance(actor.simulation, 2)
	check(actor.resource_id == enemy.id and actor.library.resource_path == RUNTIME_LIBRARY_PATH and actor.library.schema_version == STGProject.VERSION and actor.simulation.issue.is_empty(), enemy.title + "：当前共享库场景可以实例化运行")
	actor.stop()
	actor.free()

func test_distance_branch(project: STGProject) -> void:
	var world = world_for(project, "06_charger")
	world.player = Vector2(240, 0)
	advance(world, 0.03)
	var flow: STGBehaviorFlow = project.find("bosses", "06_charger").phases[0].behavior_flow
	check(world.boss_player.context.active_node_id == flow.nodes[1].id, "蛮牛：近距离选择冲刺分支")
	advance(world, 1.4)
	check(world.hits > 0, "蛮牛：冲刺身体沿移动路径命中玩家")
	world.free()
	world = world_for(project, "06_charger")
	advance(world, 0.03)
	check(world.boss_player.context.active_node_id == flow.nodes[2].id, "蛮牛：远距离选择点射分支")
	advance(world, 0.8)
	check(world.actors.any(func(actor): return actor.definition.id == "charger_round"), "蛮牛：远距离实际生成压迫弹")
	world.free()

func test_burrow(project: STGProject) -> void:
	var world = world_for(project, "05_ambusher")
	advance(world, 0.8)
	check(not world.boss_visible and world.boss_invulnerable, "伏击者：遁地时隐藏并无敌")
	world.damage_boss(20)
	check(world.hp == 100, "伏击者：地下不会受伤")
	advance(world, 1.2)
	check(world.boss_visible and not world.boss_invulnerable, "伏击者：出地恢复显示和受伤")
	advance(world, 0.7)
	check(world.actors.any(func(actor): return actor.definition.id == "burrow_zone"), "伏击者：出地后生成脚下预警区域")
	world.free()

func test_multistage(project: STGProject) -> void:
	var world = world_for(project, "08_weaver")
	world.player = Vector2(1000, 1000)
	advance(world, 2)
	check(world.actors.any(func(actor): return actor.definition.id == "weaver_star" and actor.stage_index == 0), "织网者：星弹先进入环绕阶段")
	advance(world, 1.7)
	check(world.actors.any(func(actor): return actor.definition.id == "weaver_star" and actor.stage_index == 1 and actor.visual_scale > 1), "织网者：环绕结束后锁定玩家，保留尺寸变化")
	world.free()
	world = world_for(project, "09_miner")
	world.player = Vector2(1000, 1000)
	advance(world, 1.4)
	check(world.actors.any(func(actor): return actor.definition.id == "mine_zone"), "布雷手：移动弹到达落点后变成攻击区域")
	check(world.actors.any(func(actor): return actor is STGBulletTrailActor and actor.segments.size() > 2), "布雷手：真实移动路径生成独立计时的攻击尾迹")
	world.free()

func test_commander(project: STGProject) -> void:
	var world = world_for(project, "10_commander")
	world.player = Vector2(1000, 1000)
	advance(world, 0.7)
	check(not world.actors.is_empty(), "指挥官：随机分支实际发射普通阶段子弹")
	world.damage_boss(60)
	world.step()
	check(world.boss_player.phase_index == 0 and world.boss_player.pending_phase == 1, "指挥官：45% 血量门槛等待旧攻击收尾")
	advance(world, 1)
	check(world.boss_player.phase_index == 0, "指挥官：旧阶段子弹存在时保持旧阶段")
	advance(world, 3)
	check(world.boss_player.phase_index == 1, "指挥官：攻击结束后进入狂暴阶段")
	advance(world, 2)
	check(world.actors.any(func(actor): return actor.definition.id == "commander_beam") and world.actors.any(func(actor): return actor.definition.id == "commander_zone"), "指挥官：第二阶段曲线激光和扩张区域同时生效")
	world.free()

func test_editor() -> void:
	root.size = Vector2i(1440, 900)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://enemy_examples_checks.cfg"
	root.add_child(studio)
	for i in 5: await process_frame
	studio.set_process(false)
	for control in studio.toolbar.get_children():
		if control is MenuButton and control.text == "项目":
			control.get_popup().id_pressed.emit(3)
	for i in 8: await process_frame
	check(studio.collection == "bosses" and studio.asset_list.item_count == 10 and studio.current() != null, "项目菜单直接打开十个敌人，显示 Boss 编辑页")
	check(not studio.session.file_path.is_empty() and studio.session.project.schema_version == STGProject.VERSION and studio.canvas.world.issue.is_empty(), "编辑器读取当前资源格式，预览共用正式运行器")
	studio.message_dialog.hide()
	studio.queue_free()
	for i in 8: await process_frame

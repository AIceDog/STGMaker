extends SceneTree
## 真实运行边界：共享素材、独立招式配置、精确等待、非阻塞/并行/复用与后继归属。
const Factory = preload("res://stg/definitions/definition_factory.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func library() -> STGProject:
	var project = STGProject.create()
	var material = Factory.bullet()
	material.id = "shared_material"
	project.bullets.append(material)
	for id in ["red", "blue"]:
		var attack = Factory.barrage(material.id)
		attack.id = id
		attack.fire_pattern.count = 1
		attack.fire_pattern.rounds = 1
		attack.fire_pattern.angle = 0
		attack.projectile.lifecycle.fade = 0
		attack.projectile.motion_stages[0].duration = 5
		attack.projectile.motion_stages[0].speed = 100
		project.barrages.append(attack)
	return project

func world(project: STGProject) -> STGSimulation:
	var result = STGSimulation.new()
	root.add_child(result)
	result._reset_combat_state(project, "barrages", 42)
	result.player = Vector2(5000, 5000)
	return result

func launch(id: String, target: String = "", kind: String = "attack") -> STGFlowNode:
	var result = STGFlowNode.new()
	result.id = id
	result.kind = kind
	if kind == "call": result.behavior_id = target
	else: result.barrage_id = target
	return result

func sequence(nodes: Array) -> STGBehaviorFlow:
	var result = STGBehaviorFlow.new()
	result.nodes.assign(nodes)
	result.entry_id = nodes[0].id
	for i in range(nodes.size() - 1): nodes[i].next_id = nodes[i + 1].id
	return result

func run() -> void:
	var project = library()
	var red = project.barrages[0]
	var blue = project.barrages[1]
	blue.projectile.lifecycle.damage = 7
	blue.projectile.motion_stages[0].speed = 20
	var sim = world(project)
	var first = sim.emit_projectile(red.id, Vector2.ZERO, 0)
	var second = sim.emit_projectile(blue.id, Vector2.ZERO, 0)
	check(first.definition == second.definition, "相同素材只共享静态外观与碰撞")
	check(first.lifecycle != second.lifecycle and first.lifecycle.damage == 1 and second.lifecycle.damage == 7, "不同招式的伤害配置不再写回共享素材")
	sim.step(0.01)
	check(is_equal_approx(first.position.x, 1) and is_equal_approx(second.position.x, 0.2), "同一素材可有不同运动过程")
	first.age = 9
	check(second.age < 1, "运行状态每颗独立")
	sim.free()

	project = library()
	var first_node = launch("first", "red")
	var wait = launch("delay", "", "wait")
	wait.delay = 0.015
	var second_node = launch("second", "blue")
	var combo = sequence([first_node, wait, second_node])
	combo.id = "combo"
	project.behaviors.append(combo)
	sim = world(project)
	var job = sim.play_behavior(combo.id, Vector2(20, 30))
	sim.step(0.01)
	check(sim.actors.size() == 1 and not job.emission_finished(), "非阻塞释放后立即进入等待，不等待第一批弹消失")
	sim.step(0.01)
	check(sim.actors.size() == 2, "精确相对延迟允许同一帧中途释放下一招")
	check(sim.actors[1].position.is_equal_approx(Vector2(20.5, 30)), "新弹只移动等待结束后的0.005秒")
	check(sim.actors[0].owner_id == sim.actors[1].owner_id, "复用行为的所有攻击共用归属")
	check(job.emission_finished() and not job.is_finished(sim), "流程发射完成和子弹耗尽是两个明确事件")
	sim.stop_owner(job.owner_id)
	sim.step(0.01)
	check(sim.actors.is_empty() and sim.barrages.is_empty() and sim.behaviors.is_empty(), "按归属停止同时取消未来发射与现有子弹")
	sim.free()

	project = library()
	var parallel = launch("parallel", "", "parallel")
	parallel.children.assign([sequence([launch("left", "red")]), sequence([launch("right", "blue")])])
	var pair = sequence([parallel])
	pair.id = "pair"
	project.behaviors.append(pair)
	var caller = sequence([launch("reuse", pair.id, "call")])
	caller.id = "caller"
	project.behaviors.append(caller)
	sim = world(project)
	job = sim.play_behavior(caller.id, Vector2.ZERO)
	sim.step(0.01)
	check(sim.actors.size() == 2, "可复用子流程的并行分支在同一个固定帧释放")
	check(job.emission_finished() and not job.is_finished(sim), "调用子流程后仍等待其所属弹体耗尽")
	sim.clear_attacks()
	check(sim.actors.is_empty() and sim.behaviors.is_empty(), "清屏取消整棵流程调用，不保留后台执行器")
	sim.free()

	project = library()
	var successor = sequence([launch("wait", "", "wait"), launch("after_hit", "blue")])
	successor.nodes[0].delay = 0.02
	successor.id = "on_hit"
	project.behaviors.append(successor)
	project.barrages[0].projectile.lifecycle.on_hit_behavior_id = successor.id
	sim = world(project)
	sim.player = Vector2.ZERO
	first = sim.emit_projectile("red", Vector2.ZERO, 0)
	var owner = first.owner_id
	sim.step(0.01)
	check(sim.actors.is_empty() and sim.behaviors.size() == 1, "母弹命中回收后，命中后继流程独立存在")
	check(sim.count_owned(owner) > 0, "延迟后继在没有活弹时仍保留归属")
	sim.player = Vector2(5000, 5000)
	sim.step(0.01)
	sim.step(0.01)
	check(sim.actors.size() == 1 and sim.actors[0].get_meta("source_skill") == "blue", "命中后继按延迟继续释放招式")
	check(sim.actors[0].owner_id == owner, "命中后继继承原弹体归属")
	sim.free()

	project = library()
	var transform = Factory.stage("transform")
	transform.transform_attack_id = "blue"
	project.barrages[0].projectile.motion_stages.assign([transform])
	project.barrages[1].projectile.lifecycle.damage = 9
	sim = world(project)
	first = sim.emit_projectile("red", Vector2.ZERO, 0)
	owner = first.owner_id
	sim.step(0.01)
	check(sim.actors.size() == 1 and sim.actors[0].lifecycle.damage == 9, "变形从目标招式读取完整弹体配置")
	check(sim.actors[0].owner_id == owner, "变形保留所属攻击")
	sim.free()

	project = library()
	sim = world(project)
	first = sim.preview_material("shared_material")
	sim.step(1)
	check(first.position == sim.boss and first.age == 0 and sim.hits == 0, "素材预览静态显示，不承载或执行攻击生命周期")
	sim.free()
	_test_parallel_pending_and_origin()
	_test_nonblocking_action()
	_test_sound_and_effects()
	print("ATTACK LIFECYCLE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_parallel_pending_and_origin() -> void:
	var project = library()
	project.barrages[0].fire_pattern.rounds = 2
	project.barrages[0].fire_pattern.interval = 0.05
	var node = launch("parallel", "", "parallel")
	node.children.assign([sequence([launch("first", "red")]), sequence([launch("second", "blue")])])
	var flow = sequence([node]); flow.id = "parallel_pending"; project.behaviors.append(flow)
	var sim = world(project); var job = sim.play_behavior(flow.id, Vector2.ZERO)
	sim.step(0.01)
	check(sim.actors.size() == 2 and not job.emission_finished(), "并行图结束后仍等待各分支未来轮次")
	job.origin = Vector2(80, 10)
	for i in 4: sim.step(0.01)
	check(sim.actors.size() == 3 and sim.actors[-1].position.y == 10 and sim.actors[-1].position.x > 80, "更新组合行为原点只改变后续发射")
	check(sim.actors[0].position.y == 0, "已有弹体不随发射者原点平移")
	check(job.emission_finished(), "最后一轮发完后并行行为报告发射结束")
	sim.free()

func _test_nonblocking_action() -> void:
	var project = library()
	project.barrages[0].fire_pattern.rounds = 3
	project.barrages[0].fire_pattern.interval = 0.03
	var action = Factory.action("fire", "red")
	action.windup = 0; action.recovery = 0; action.attack.finish_event = "immediate"
	var enemy = Factory.boss(); enemy.phases[0].loop = false
	enemy.phases[0].behavior_flow = Factory.flow([action]); project.bosses.append(enemy)
	var sim = STGSimulation.new(); root.add_child(sim); sim.reset(project, "bosses", enemy.id); sim.player = Vector2(5000, 5000)
	for i in 12: sim.step(0.01)
	check(sim.actors.size() == 3, "敌人非阻塞释放结束动作后，招式剩余轮次仍继续")
	check(not sim.boss_player.context.action_running and not sim.boss_player.finished, "动作已结束但阶段仍跟踪独立攻击归属")
	sim.free()

func _test_sound_and_effects() -> void:
	for unit in ["cast", "round", "projectile"]:
		var project = library(); var attack = project.barrages[0]
		attack.fire_pattern.sound_unit = unit; attack.fire_pattern.count = 3; attack.fire_pattern.rounds = 2; attack.fire_pattern.interval = 0.02
		attack.projectile.lifecycle.spawn_sound = AudioStreamWAV.new()
		var sim = world(project); sim.muted = false
		var sounds = []
		sim.audio_requested.connect(func(_sound, _at): sounds.append(true))
		sim.play_barrage("red", Vector2.ZERO)
		for i in 4: sim.step(0.01)
		check(sounds.size() == {"cast": 1, "round": 2, "projectile": 6}[unit], "发射声音按明确播放单位执行：" + unit)
		sim.free()
	var project = library(); var attack = project.barrages[0]
	var effect_node = Node2D.new(); var scene = PackedScene.new(); scene.pack(effect_node); effect_node.free()
	attack.projectile.lifecycle.expire_effect = scene; attack.projectile.lifecycle.effect_duration = 0.05
	attack.projectile.motion_stages[0].duration = 0.01
	var sim = world(project); sim.emit_projectile("red", Vector2.ZERO, 0); sim.step(0.01)
	check(sim.actors.is_empty() and sim.effects.size() == 1 and not sim.completed, "弹体结束后仍等待自然结束特效")
	for i in 5: sim.step(0.01)
	check(sim.effects.is_empty() and sim.completed, "特效按固定模拟时间回收，重放不依赖墙钟")
	sim.free()

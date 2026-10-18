extends SceneTree
## 运行与迁移集成：顺序、分支、攻击与移动协同、身体攻击、中断、动画和旧文件。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const Session = preload("res://addons/stg_maker/ui/session.gd")
const Targets = preload("res://stg/runtime/boss/target_resolver.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func advance(world, seconds: float) -> void:
	for i in ceili(seconds / STGSimulation.STEP): world.step()
func project_for(cards: Array) -> STGProject:
	var project = STGProject.create(); Defaults.populate(project)
	var boss = project.bosses[0]; boss.start_position = Vector2.ZERO
	boss.phases.resize(1); boss.phases[0].loop = false; boss.phases[0].behavior_flow = Defaults.flow(cards)
	return project
func world(project: STGProject) -> STGSimulation:
	var sim = STGSimulation.new(); root.add_child(sim)
	sim.reset(project, "bosses", project.bosses[0].id); sim.player = Vector2(5000, 5000)
	return sim
func card(template: String = "wait") -> STGBossAction:
	var action = Defaults.action(template); action.windup = 0; action.recovery = 0
	return action
func short_attack(project) -> void:
	project.barrages[0].projectile.motion_stages[0].duration = 0.25; project.barrages[0].projectile.lifecycle.fade = 0
	project.barrages[0].fire_pattern.rounds = 1; project.barrages[0].fire_pattern.count = 1
func visual_scene() -> PackedScene:
	var visual = Node2D.new(); visual.name = "Visual"
	var body = Polygon2D.new(); body.name = "Body"; body.polygon = PackedVector2Array([Vector2(-20, 20), Vector2(0, -20), Vector2(20, 20)])
	visual.add_child(body); body.owner = visual
	var player = AnimationPlayer.new(); player.name = "AnimationPlayer"; visual.add_child(player); player.owner = visual
	var library = AnimationLibrary.new()
	for name in ["windup", "active", "recovery", "RESET"]:
		var clip = Animation.new(); clip.length = 0.1
		var track = clip.add_track(Animation.TYPE_VALUE); clip.track_set_path(track, NodePath("Body:scale"))
		clip.track_insert_key(track, 0, Vector2.ONE)
		clip.track_insert_key(track, 0.1, Vector2.ONE * (2 if name == "windup" else 1))
		library.add_animation(name, clip)
	player.add_animation_library("", library)
	var packed = PackedScene.new(); packed.pack(visual); visual.free(); return packed

func run() -> void:
	var move = card("curve"); move.movement.mode = "line"; move.movement.target = Vector2(100, 0)
	move.windup = 0.05; move.movement.duration = 0.05; move.recovery = 0.1
	var next = card("teleport"); next.movement.target = Vector2(100, 0)
	var project = project_for([move, next])
	var flow = project.bosses[0].phases[0].behavior_flow
	check(flow.nodes[0].next_id == flow.nodes[1].id and flow.nodes[1].next_id.is_empty(), "默认动作直接按顺序连接")
	var sim = world(project); advance(sim, 0.04)
	check(sim.boss == Vector2.ZERO, "移动前摇不提前生效")
	advance(sim, 0.08)
	check(sim.boss.is_equal_approx(Vector2(100, 0)) and sim.boss_player.context.active_node_id == flow.nodes[0].id, "旧动作后摇期间不进入下个动作")
	advance(sim, 0.2)
	check(sim.boss.is_equal_approx(Vector2(200, 0)) and sim.completed, "后摇结束后顺序进入下一步")
	sim.free()
	project = project_for([card()]); project.bosses[0].phases[0].behavior_flow = Defaults.conditional_flow()
	flow = project.bosses[0].phases[0].behavior_flow
	flow.nodes[1].action.windup = 0; flow.nodes[1].action.recovery = 0
	flow.nodes[2].action.duration = 0.01
	sim = world(project); sim.player = Vector2(30, 0); advance(sim, 0.04)
	check(sim.boss_player.runner.states().has(flow.nodes[1].id) and not sim.boss_player.runner.states().has(flow.nodes[2].id), "玩家靠近走 是 分支")
	sim.player = Vector2(5000, 5000); advance(sim, 0.04)
	check(sim.boss_player.context.active_node_id == flow.nodes[1].id, "动作运行中不因距离改变重选分支")
	sim.free()
	sim = world(project); advance(sim, 0.04)
	check(sim.boss_player.runner.states().has(flow.nodes[2].id) and not sim.boss_player.runner.states().has(flow.nodes[1].id), "玩家远离走 否 分支")
	check(project.validate().is_empty(), "两个分支可以汇合到同一动作")
	sim.free()
	var sweep = card("fire"); sweep.movement.mode = "line"; sweep.movement.target = Vector2(200, 0)
	sweep.movement.duration = 2; sweep.recovery = 0.05
	project = project_for([sweep]); short_attack(project); sweep.attack.barrage_id = project.barrages[0].id
	sim = world(project); advance(sim, 0.1)
	check(sim.boss.x > 0 and not sim.actors.is_empty(), "同一动作段能够边移动边攻击")
	check(sim.barrages[0].origin.is_equal_approx(sim.boss), "连续发射原点跟随 Boss")
	advance(sim, 0.35); var stopped: Vector2 = sim.boss
	advance(sim, 0.1)
	check(sim.completed and sim.boss == stopped and sim.boss.x < 200, "攻击结束会停止未完成移动并完成后摇")
	sim.free()
	sweep.attack.finish_event = "emission"; sweep.movement.mode = "none"
	project = project_for([sweep]); short_attack(project); sweep.attack.barrage_id = project.barrages[0].id
	sim = world(project); advance(sim, 0.1)
	check(not sim.actors.is_empty() and not sim.boss_player.context.action_running, "发射完成与场上子弹结束是不同事件")
	check(not sim.boss_player.finished, "非循环流程也等待已有子弹收尾")
	advance(sim, 0.3); check(sim.completed, "已有子弹结束后流程报告完成")
	sim.free()
	sweep.attack.clear_on_end = true
	project = project_for([sweep]); short_attack(project); sweep.attack.barrage_id = project.barrages[0].id
	sim = world(project); advance(sim, 0.1)
	check(sim.actors.is_empty(), "显式清除只作用于本次攻击归属")
	sim.free()
	sweep.attack.clear_on_end = false; sweep.attack.finish_event = "duration"; sweep.duration = 0.05; sweep.recovery = 0
	project = project_for([sweep]); short_attack(project); sweep.attack.barrage_id = project.barrages[0].id
	project.barrages[0].fire_pattern.rounds = 10; project.barrages[0].fire_pattern.interval = 0.03
	sim = world(project); advance(sim, 0.12)
	check(sim.actors.size() <= 3 and not sim.actors.is_empty(), "动作结束停止未来发射但保留已有子弹")
	sim.free()
	sweep.attack.finish_event = "emission"; sweep.movement.mode = "line"; sweep.movement.duration = 0.05
	sweep.movement_start = "attack_end"; sweep.movement_delay = 0.04; sweep.end_when = "both"
	project = project_for([sweep]); short_attack(project); sweep.attack.barrage_id = project.barrages[0].id
	sim = world(project); advance(sim, 0.03)
	check(sim.boss == Vector2.ZERO, "移动可以等待攻击结束与额外延迟")
	advance(sim, 0.07); check(sim.boss.x > 0, "攻击结束事件触发后按配置开始移动")
	advance(sim, 0.1); check(sim.boss.is_equal_approx(Vector2(200, 0)), "等待双方完成时移动到目标再收尾")
	sim.free()
	sweep.attack_start = "movement_end"; check(not project.validate().is_empty(), "拒绝攻击与移动互相等待的死锁")
	var burrow = card("burrow"); burrow.windup = 0.03; burrow.movement.duration = 0.2
	project = project_for([burrow]); sim = world(project); advance(sim, 0.08)
	check(not sim.boss_visible and sim.boss_invulnerable, "遁地独立设置隐藏与无敌")
	sim.damage_boss(10); check(sim.hp == 100, "外部伤害接口尊重地下无敌")
	advance(sim, 0.3); check(sim.boss_visible and not sim.boss_invulnerable, "出地后恢复可见和受伤状态")
	sim.free()
	burrow.movement.invulnerable_while_buried = false; burrow.interrupt_on_hit = true
	project = project_for([burrow]); sim = world(project); advance(sim, 0.08); sim.damage_boss(1); advance(sim, 0.02)
	check(sim.boss_visible and not sim.boss_invulnerable and not sim.boss_player.context.action_running, "受击中断恢复移动、隐藏与无敌状态")
	sim.free()
	var dash = card("dash"); dash.movement.duration = 0.01; dash.movement.target_mode = "player"; dash.movement.target = Vector2.ZERO
	project = project_for([dash]); sim = world(project); sim.player = Vector2(100, 0); advance(sim, 0.04)
	check(sim.hits == 1, "高速冲刺身体判定扫过玩家且只命中一次")
	sim.free(); dash.movement.body_attack = false
	project = project_for([dash]); sim = world(project); sim.player = Vector2(100, 0); advance(sim, 0.04)
	check(sim.hits == 0, "冲刺可关闭身体攻击只做换位")
	sim.free()
	var teleport = card("teleport"); teleport.windup = 0.1; teleport.movement.target_mode = "player"; teleport.movement.target = Vector2.ZERO
	teleport.movement.lock_at = "windup"
	project = project_for([teleport]); sim = world(project); sim.player = Vector2(100, 0); advance(sim, 0.04); sim.player = Vector2(200, 0); advance(sim, 0.1)
	check(sim.boss.is_equal_approx(Vector2(100, 0)), "前摇开始锁定位置不会随玩家移动改变")
	sim.free(); teleport.movement.lock_at = "active"
	project = project_for([teleport]); sim = world(project); sim.player = Vector2(100, 0); advance(sim, 0.04); sim.player = Vector2(200, 0); advance(sim, 0.1)
	check(sim.boss.is_equal_approx(Vector2(200, 0)), "移动开始时可以重新锁定玩家")
	teleport.movement.aiming = "predict"; sim.player_velocity = Vector2(10, 0); teleport.movement.prediction = 0.5
	check(Targets.resolve(sim, teleport.movement, Vector2.ZERO).is_equal_approx(Vector2(205, 0)), "预测目标使用玩家速度与提前量")
	sim.free()
	move = card("curve"); move.movement.mode = "line"; move.movement.target_mode = "player"; move.movement.target = Vector2.ZERO
	move.movement.aiming = "track"; move.movement.turn_speed = 90; move.movement.duration = 1
	project = project_for([move]); sim = world(project); sim.player = Vector2(100, 0); advance(sim, 0.04)
	sim.player = Vector2(0, 100); var before_turn = sim.boss; sim.step()
	check(absf((sim.boss - before_turn).angle()) < 0.02, "追踪转向受角速度限制而非瞬间转向")
	sim.free()
	var idle = card(); idle.windup = 0.2; idle.duration = 0.1; idle.recovery = 0.2
	idle.presentation.windup_animation = "windup"; idle.presentation.active_animation = "active"; idle.presentation.recovery_animation = "recovery"
	project = project_for([idle]); project.bosses[0].visual_scene = visual_scene()
	check(project.validate().is_empty(), "表现场景与动画绑定合法")
	sim = world(project); advance(sim, 0.1)
	var body = sim.boss_presentation.visual.get_node("Body")
	check(body.scale.x > 1.3 and body.scale.x < 1.7, "美术前摇长度按逻辑前摇缩放")
	advance(sim, 0.14); check(sim.boss_presentation.animation_player.current_animation == "active", "逻辑生效时同步切换执行动画")
	advance(sim, 0.1); check(sim.boss_presentation.animation_player.current_animation == "recovery", "逻辑后摇同步切换收招动画")
	advance(sim, 0.3); check(sim.completed and body.scale == Vector2.ONE, "动作完成重置动画，不残留旧姿态")
	sim.free()
	project = project_for([card()]); flow = project.bosses[0].phases[0].behavior_flow
	var condition = Defaults.flow_node("condition"); condition.condition = "cooldown"; condition.reference_id = flow.entry_id; condition.comparison = "greater_equal"; condition.threshold = 1
	condition.next_id = flow.entry_id; condition.failure_id = ""; flow.nodes.push_front(condition); flow.entry_id = condition.id
	sim = world(project); advance(sim, 0.02); check(sim.boss_player.context.action_running, "从未使用的动作视为冷却完成")
	sim.free()
	project.bosses[0].phases[0].loop = true
	sim = world(project); sim.action_completed_at[condition.reference_id] = 0; advance(sim, 0.1)
	check(not sim.boss_player.context.action_running, "冷却未完成时不执行该动作")
	advance(sim, 1.1); check(sim.boss_player.context.action_running, "循环流程在冷却完成后可以执行动作")
	sim.free()
	flow.nodes[1].next_id = condition.id; check(not project.validate().is_empty(), "拒绝无限流程连接循环")
	flow.nodes[1].next_id = "missing"; check(not project.validate().is_empty(), "拒绝丢失连接目标")
	flow.nodes[1].next_id = ""; flow.nodes.append(Defaults.flow_node()); check(not project.validate().is_empty(), "孤立节点给出明确校验提示")
	var reactive = project_for([card("teleport"), card("teleport")]); flow = reactive.bosses[0].phases[0].behavior_flow
	flow.nodes[0].action.movement.target = Vector2(42, 0); flow.nodes[0].next_id = ""
	flow.nodes[1].action.movement.target = Vector2(99, 0)
	var hit = Defaults.flow_node("condition"); hit.condition = "recent_hit"; hit.threshold = 0.5
	hit.next_id = flow.nodes[0].id; hit.failure_id = flow.nodes[1].id; flow.nodes.push_front(hit); flow.entry_id = hit.id
	sim = world(reactive); sim.damage_boss(1); advance(sim, 0.1)
	check(sim.boss.x == 42, "外部受击事件能够触发 AI 条件分支")
	sim.free(); sim = world(reactive); advance(sim, 0.1)
	check(sim.boss.x == 99, "没有受击时执行另一个分支")
	sim.free()
	print("BEHAVIOR FLOW RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


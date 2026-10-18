@tool
extends RefCounted
## 默认值和起步模板的唯一工厂。无 UI 与运行状态；所有新建入口都调用这里。
const CombatSpace = preload("res://stg/definitions/combat_space.gd")

static func curve(values: Array = [Vector2(0, 1), Vector2(1, 1)]) -> Curve:
	var result = Curve.new() # Godot 内置资源：时间曲线
	result.max_value = 10.0
	for point in values:
		result.add_point(point, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return result

static func path(points: Array = [Vector2.ZERO, Vector2(50, 350), Vector2(0, 760)]) -> Curve2D:
	var result = Curve2D.new() # Godot 内置资源：空间贝塞尔曲线
	for i in points.size():
		var tangent: Vector2 = (points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]) / 6.0
		result.add_point(points[i], -tangent, tangent)
	return result

static func stage(mode: String = "path") -> STGMotionStage:
	var result = STGMotionStage.new()
	result.mode = mode
	result.orbit_center = "boss"
	result.orbit_end_radius = -1
	result.angular_speed = 0
	result.track_until_distance = 0
	result.preserve_heading = false
	result.track_target_offset = Vector2.ZERO
	result.title = {"path": "路径移动", "aim": "瞄准玩家", "track": "追踪玩家", "velocity": "沿发射方向直飞", "sine": "S 形飞行", "ballistic": "抛物线飞行", "orbit": "环绕 Boss", "wait": "停留", "transform": "变成另一种子弹", "extension": "自定义运动"}[mode]
	result.gravity = 520
	result.ballistic_aim = true
	result.flight_time = 0
	result.flight_speed = 300
	result.flight_min_time = 0.55
	result.flight_max_time = 1.5
	result.flight_min_distance = 120
	result.flight_distance_mode = "distance"
	result.initial_velocity = Vector2(0, -430)
	result.velocity_x_player_factor = 0
	result.velocity_x_limit = 50
	result.sine_amplitude = rad_to_deg(0.45)
	result.sine_frequency = 8
	result.sine_phase = 0
	result.path = path()
	result.progress_curve = curve([Vector2.ZERO, Vector2.ONE])
	result.visual_scale_curve = curve()
	result.collision_scale_curve = curve()
	return result

static func bullet(form: String = "moving") -> STGBulletDefinition:
	var result = STGBulletDefinition.new()
	result.id = uid("bullet")
	result.form = form
	result.title = {"moving": "新弹丸素材", "laser": "新激光素材", "area": "新区域素材", "trail": "新尾迹素材"}[form]
	result.scene = load("res://stg/runtime/scenes/" + form + ".tscn")
	result.visual = STGBulletVisual.new()
	result.visual.geometry = STGBulletGeometry.new()
	result.visual.color = Color("55dfbc")
	if form == "laser":
		result.visual.geometry.kind = "rectangle"
		result.visual.geometry.along_beam = true
		result.visual.geometry.size = Vector2(760, 24)
		result.visual.geometry.offset = Vector2.ZERO
	elif form == "area": result.visual.geometry.size = Vector2(150, 150)
	elif form == "trail":
		result.visual.geometry.kind = "rectangle"
		result.visual.geometry.size = Vector2(1, 24)
	if form != "moving": result.visual.color = Color("ffbc65")
	result.collision = result.visual.geometry.duplicate(true)
	return result

static func movement(mode: String = "none") -> STGBossMovement:
	var result = STGBossMovement.new()
	result.mode = mode
	result.speed = 0
	result.initial_velocity = Vector2(-260, -700)
	result.gravity = 1500
	result.velocity_mode = "fixed"
	result.target = Vector2(-100, 0)
	result.path = path([Vector2.ZERO, Vector2(-80, 50), Vector2(-150, 0)])
	result.orbit_progress_curve = curve([Vector2.ZERO, Vector2.ONE])
	return result

static func trail_attack(bullet_id: String) -> STGBarrageSkill:
	var result = barrage(bullet_id, "trail")
	result.title = "持续生成路径尾迹"
	result.trail_duration = 6
	result.projectile.lifecycle.warning = 0.12
	result.projectile.lifecycle.fade = 1.4
	result.projectile.motion_stages.assign([stage("wait")])
	result.projectile.motion_stages[0].duration = 0.8
	return result

static func trail_boss(skill_id: String) -> STGBossDefinition:
	var result = boss()
	result.title = "缩圈尾迹 Boss"
	var card = action("fire", skill_id)
	card.windup = 0.6
	card.movement = movement("orbit")
	card.movement.duration = 6
	card.movement.target_mode = "player"
	card.movement.target = Vector2.ZERO
	card.end_when = "both"
	result.phases[0].behavior_flow = flow([card, action()])
	return result

static func fire_pattern() -> STGFirePattern:
	var result = STGFirePattern.new()
	result.angle = rad_to_deg(CombatSpace.ENEMY_SHOT_ANGLE)
	result.path = path([Vector2(0, -100), Vector2.ZERO, Vector2(0, 100)])
	return result

static func projectile(bullet_id: String = "", mode: String = "velocity") -> STGProjectileDefinition:
	var result = STGProjectileDefinition.new()
	result.bullet_id = bullet_id
	result.lifecycle = STGAttackLifecycle.new()
	result.motion_stages.assign([stage(mode)])
	return result

static func barrage(bullet_id: String, template: String = "fan") -> STGBarrageSkill:
	var result = STGBarrageSkill.new()
	result.id = uid("barrage")
	result.title = {"fan": "扇形连射", "ring": "圆环齐射", "spiral": "螺旋发射", "aim": "瞄准连射", "cross": "交叉激光", "area": "区域预警", "trail": "路径尾迹"}.get(template, "新招式")
	result.fire_pattern = fire_pattern()
	_configure_fire_template(result.fire_pattern, template)
	result.projectile = projectile(bullet_id, "wait" if template in ["cross", "area", "trail"] else "velocity")
	if template in ["cross", "area"]:
		result.projectile.lifecycle.warning = 0.7
		result.projectile.motion_stages[0].duration = 1
	return result

static func _configure_fire_template(shot: STGFirePattern, template: String) -> void:
	match template:
		"ring":
			shot.arrangement = "circle"
			shot.direction = "outward"
			shot.count = 16
		"spiral":
			shot.direction = "parallel"
			shot.count = 1
			shot.rounds = 16
			shot.rotation_per_round = 23
		"aim":
			shot.direction = "aim"
			shot.count = 1
			shot.rounds = 3
		"cross":
			shot.direction = "fan"
			shot.angle = 0
			shot.spread = 270
			shot.count = 4
		"trail":
			shot.count = 1
			shot.direction = "parallel"
		"area":
			shot.direction = "parallel"
			shot.count = 1
			shot.anchor = "player"
		_:
			shot.rounds = 3

# template 是起步模板名，不是互斥的运行类型；一个动作段可同时拥有攻击与移动。
static func action(template: String = "wait", barrage_id: String = "") -> STGBossAction:
	var result = STGBossAction.new()
	result.attack = STGBossAttack.new()
	result.movement = movement()
	result.presentation = STGBossPresentation.new()
	result.title = {"fire": "使用弹幕招式", "curve": "路径移动", "line": "直线移动", "dash": "冲刺", "teleport": "瞬移", "burrow": "遁地换位", "wait": "等待"}.get(template, "动作段")
	if template == "fire":
		result.attack.enabled = true
		result.attack.barrage_id = barrage_id
		result.end_when = "attack"
		result.movement_start = "attack_start"
	elif template != "wait":
		result.movement.mode = template
		result.end_when = "movement"
		if template == "dash":
			result.movement.duration = 0.35
			result.movement.body_attack = true
	return result

static func flow_node(kind: String = "action", card: STGBossAction = null) -> STGFlowNode:
	var result = STGFlowNode.new()
	result.id = uid("flow")
	result.kind = kind
	result.title = STGFlowNode.LABELS[STGFlowNode.KINDS.find(kind)]
	if kind == "action":
		result.action = card if card != null else action()
		result.title = result.action.title
	return result

static func flow(actions: Array = [], random: bool = false) -> STGBehaviorFlow:
	var result = STGBehaviorFlow.new()
	result.loop_entry_id = ""
	var cards = actions if not actions.is_empty() else [action()]
	for i in cards.size():
		var node = flow_node("action", cards[i])
		node.editor_position = Vector2(250, 50 + i * 185)
		result.nodes.append(node)
		if i > 0 and not random:
			result.nodes[i - 1].next_id = node.id
	result.entry_id = result.nodes[0].id
	if random:
		_connect_random_branches(result)
	return result

static func _connect_random_branches(result: STGBehaviorFlow) -> void:
	# 分支返回点是稳定 ID，由流程运行器解释；这里仅编排连接和画布布局。
	var choice = flow_node("random")
	choice.editor_position = Vector2(40, 100)
	for i in result.nodes.size():
		choice.choices.append(result.nodes[i].id)
		result.nodes[i].next_id = STGFlowNode.SUCCESS
		result.nodes[i].failure_id = STGFlowNode.FAILURE
		result.nodes[i].editor_position = Vector2(370, 70 + i * 200)
	result.nodes.push_front(choice)
	result.entry_id = choice.id

static func phase(barrage_id: String = "") -> STGBossPhase:
	var result = STGBossPhase.new()
	result.life = 0
	result.entry_mode = "hp"
	result.life_hp = 100
	result.entry_delay = 0
	result.entry_invulnerable = false
	result.entry_barrage_id = ""
	result.time_limit = 0
	result.time_exit = "next"
	result.depleted_exit = "auto"
	result.depleted_refill = 100
	result.clear_on_enter = false
	var cards = [action()]
	if not barrage_id.is_empty():
		var sweep = action("fire", barrage_id)
		sweep.title = "移动扫射"
		sweep.movement.mode = "curve"
		cards = [sweep, action("curve"), action()]
	result.behavior_flow = flow(cards)
	return result

static func conditional_flow(barrage_id: String = "") -> STGBehaviorFlow:
	var result = STGBehaviorFlow.new()
	var condition = flow_node("condition")
	condition.title = "玩家是否靠近？"
	condition.editor_position = Vector2(250, 50)
	var dash = flow_node("action", action("dash"))
	dash.action.movement.target_mode = "player"
	dash.action.movement.target = Vector2.ZERO
	dash.editor_position = Vector2(80, 235)
	var distant = flow_node("action", action("fire", barrage_id) if not barrage_id.is_empty() else action())
	distant.editor_position = Vector2(420, 235)
	var wait = flow_node()
	wait.editor_position = Vector2(250, 445)
	condition.next_id = dash.id
	condition.failure_id = distant.id
	dash.next_id = wait.id
	distant.next_id = wait.id
	result.entry_id = condition.id
	result.nodes.assign([condition, dash, distant, wait])
	return result

static func boss(barrage_id: String = "", conditional: bool = false) -> STGBossDefinition:
	var result = STGBossDefinition.new()
	result.on_death_skill_id = ""
	result.description = ""
	result.id = uid("boss")
	result.start_position = CombatSpace.ENEMY_SPAWN
	result.entity_settings = entity_settings()
	result.phases.append(phase(barrage_id))
	if conditional:
		result.phases[0].behavior_flow = conditional_flow(barrage_id)
	return result

static func animated_boss(barrage_id: String) -> STGBossDefinition:
	var result = boss(barrage_id)
	result.title = "动画时序示例 Boss"
	result.visual_scene = load("res://stg/runtime/scenes/boss_visual.tscn")
	for node in result.phases[0].behavior_flow.nodes:
		node.action.presentation.windup_animation = "windup"
		node.action.presentation.active_animation = "active"
		node.action.presentation.recovery_animation = "recovery"
	return result

static func uid(prefix: String) -> String:
	return prefix + "_" + Resource.generate_scene_unique_id() # Godot 内置：生成资源 ID

# 关卡配置工厂：仍是唯一默认值入口；运行状态不放进这些 Resource。
static func entity_settings(scroll: bool = false) -> STGEntitySettings:
	var result = STGEntitySettings.new()
	result.movement_policy = "scroll" if scroll else "independent"
	result.exit_boundary = "left" if scroll else "never"
	return result

static func obstacle() -> STGObstacleDefinition:
	var result = STGObstacleDefinition.new()
	result.id = uid("obstacle")
	result.entity_settings = entity_settings(true)
	result.entity_settings.body_radius = 27
	return result

static func level_exit_rule(mode: String = "time_and_condition") -> STGLevelExitRule:
	var result = STGLevelExitRule.new()
	result.mode = mode
	return result

static func wave(enemy_id: String = "", obstacle: bool = false) -> STGWaveDefinition:
	var result = STGWaveDefinition.new()
	result.id = uid("wave")
	result.title = "岩石障碍编队" if obstacle else "敌人纵队"
	result.kind = "obstacle" if obstacle else "enemy"
	result.enemy_id = "" if obstacle else enemy_id
	result.obstacle_id = enemy_id if obstacle else ""
	result.counts_for_clear = not obstacle
	if obstacle:
		result.count = 4
		result.spacing = Vector2(80, 90)
		result.interval = 0.6
	return result

static func level_event(wave_id: String = "", at: float = 0) -> STGLevelEvent:
	var result = STGLevelEvent.new()
	result.id = uid("event")
	result.wave_id = wave_id
	result.at = at
	return result

static func level_segment(wave_id: String = "") -> STGLevelSegment:
	var result = STGLevelSegment.new()
	result.id = uid("segment")
	result.exit_rule = level_exit_rule()
	if not wave_id.is_empty():
		result.events.append(level_event(wave_id))
	return result

static func background_layer(ratio: float = 0.25) -> STGBackgroundLayer:
	var result = STGBackgroundLayer.new()
	result.title = "远景" if ratio < 0.5 else "近景"
	result.scroll_ratio = ratio
	return result

static func level(wave_id: String = "") -> STGLevelDefinition:
	var result = STGLevelDefinition.new()
	result.id = uid("level")
	result.player_spawn = CombatSpace.PLAYER_SPAWN
	result.background_layers.assign([background_layer(0.2), background_layer(0.7)])
	result.segments.append(level_segment(wave_id))
	return result

static func wave_preview(wave_id: String, wave: STGWaveDefinition = null) -> STGLevelDefinition:
	var result = level(wave_id)
	# 预览覆盖完整生成过程；持续战斗的敌人仍需击败 / 离场后才能清场。
	result.segments[0].duration = maxf(8, (wave.count - 1) * wave.interval + 2) if wave != null else 8
	return result

static func obstacle_preview(wave_id: String) -> STGLevelDefinition:
	var result = level(wave_id)
	result.segments[0].duration = 12
	result.segments[0].exit_rule = level_exit_rule("time")
	return result


static func extension_binding(definition: STGExtensionDefinition = null) -> STGExtensionBinding:
	var result = STGExtensionBinding.new()
	result.definition = definition
	result.parameters = definition.default_parameters() if definition != null else {}
	return result

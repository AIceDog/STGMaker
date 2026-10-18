@tool
extends RefCounted
## 动作移动接口 prepare/start/tick/cancel；出生与卷轴偏移由 Simulation.move_boss_frame 注入。
const Targets = preload("res://stg/runtime/boss/target_resolver.gd")
var definition: STGBossMovement
var origin: Vector2
var target: Vector2
var direction: Vector2
var elapsed: float = 0 # 本次移动的秒数；不与动作段前摇 / 后摇时钟混用。
var running: bool = false
var completed: bool = false
var contact_hit: bool = false
var orbit_start_radius: float = 0
var orbit_start_angle: float = 0
var initial_velocity: Vector2 = Vector2.ZERO

## 自定义准备：先按锁定规则取目标；origin / target 均为战斗坐标。
func prepare(world, config: STGBossMovement) -> void:
	definition = config
	origin = world.boss
	target = Targets.resolve(world, config, origin)
	completed = config.mode == "none"

## 自定义开始：执行期锁定的目标在这里重新采样；瞬移直接完成，不产生连续冲刺判定。
func start(world) -> void:
	if completed:
		return
	origin = world.boss
	if definition.lock_at == "active":
		target = Targets.resolve(world, definition, origin)
	direction = (target - origin).normalized()
	if definition.speed > 0 and definition.mode in ["line", "dash"]:
		target = origin + direction * definition.speed * definition.duration
	initial_velocity = definition.initial_velocity
	if definition.mode == "ballistic":
		if definition.velocity_mode == "direction":
			initial_velocity = direction * definition.initial_velocity.length()
		elif definition.velocity_mode == "horizontal":
			initial_velocity.x = absf(initial_velocity.x) * (-1 if target.x < origin.x else 1)
	elapsed = 0
	running = true
	if definition.mode == "orbit":
		orbit_start_radius = origin.distance_to(target)
		orbit_start_angle = (origin - target).angle()
	if definition.mode == "teleport":
		world.boss = target
		completed = true
		running = false
	elif definition.mode == "burrow":
		world.boss_visible = not definition.hide_while_buried
		world.boss_invulnerable = definition.invulnerable_while_buried

## 自定义更新：dt 为秒，先移动再检查扫过的本体伤害；前摇可禁止本体攻击。
func tick(world, dt: float, allow_body_attack: bool = true) -> void:
	if not running:
		return
	elapsed += dt
	var previous: Vector2 = world.boss
	var progress = clampf(elapsed / definition.duration, 0, 1)
	_update_location(world, dt, progress)
	_check_body_hit(world, previous, allow_body_attack)
	if elapsed + 0.000001 >= definition.duration:
		completed = true
		cancel(world)

func _update_location(world, dt: float, progress: float) -> void:
	if definition.mode == "orbit":
		var center = Targets.resolve(world, definition, origin) if definition.orbit_follow_center and definition.target_mode == "player" else target
		var radius = lerpf(orbit_start_radius, definition.orbit_end_radius, definition.orbit_progress_curve.sample(progress))
		var angle = orbit_start_angle + TAU * definition.orbit_turns * progress
		world.boss = center + Vector2.from_angle(angle) * radius
	elif definition.mode == "ballistic":
		var seconds = minf(elapsed, definition.duration)
		world.boss = origin + initial_velocity * seconds + Vector2(0, definition.gravity * seconds * seconds / 2)
	elif definition.mode == "curve":
		world.boss = origin + definition.path.sample_baked(definition.path.get_baked_length() * progress, true) - definition.path.get_point_position(0)
	elif definition.aiming == "track" and definition.target_mode == "player":
		var desired = Targets.resolve(world, definition, origin) - world.boss
		if desired.length_squared() > 0.00001:
			# 配置转速为度 / 秒，Godot 向量角度为弧度；每步限制转向量。
			var max_turn = deg_to_rad(definition.turn_speed) * dt
			var angle_difference = wrapf(desired.angle() - direction.angle(), -PI, PI)
			direction = direction.rotated(clampf(angle_difference, -max_turn, max_turn))
			var distance = definition.speed * dt if definition.speed > 0 else minf(desired.length(), origin.distance_to(target) / definition.duration * dt)
			world.boss += direction * distance
	else:
		world.boss = origin.lerp(target, progress)

func _check_body_hit(world, previous: Vector2, allow_body_attack: bool) -> void:
	if allow_body_attack and definition.body_attack and definition.mode != "burrow" and not contact_hit:
		# Godot 内置 Geometry2D：扫过的线段也参与判定，避免高速冲刺穿过玩家。
		if world.player.distance_to(Geometry2D.get_closest_point_to_segment(world.player, previous, world.boss)) < definition.body_radius + world.player_radius:
			world.register_hit(definition.body_damage)
			contact_hit = true

## 自定义停止：恢复可见 / 可受伤状态，不清除敌人已经发出的攻击。
func cancel(world) -> void:
	running = false
	world.boss_visible = true
	world.boss_invulnerable = false

func rebase(displacement: Vector2) -> void:
	# 自定义接口：把尚在执行的路径起点与锁定终点平移到同一卷轴坐标框架。
	origin += displacement
	target += displacement

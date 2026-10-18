@tool
extends STGMotionExtension
## 内置运动也是一个能力实现；只在内部适配层读取 actor，公开 SDK 不暴露它。
var stage: STGMotionStage
func _init(config: STGMotionStage) -> void: stage = config
func start(context: STGMotionContext, _parameters: Dictionary) -> void:
	var actor = context._actor
	var world = context._world
	actor.track_locked = false
	if stage.mode in ["aim", "track"] and not stage.preserve_heading:
		actor.rotation = (world.player + stage.track_target_offset - actor.position).angle()
	if stage.mode == "ballistic":
		actor.stage_velocity = _ballistic_velocity(actor.position, world.player, stage) * actor.speed_scale
	actor.orbit_angle = (actor.position - _orbit_center(actor, world, stage)).angle()
func tick(context: STGMotionContext, dt: float) -> void:
	var actor = context._actor
	var world = context._world
	var movement_dt = dt
	var progress = clampf(actor.stage_elapsed / stage.duration, 0, 1)
	var previous: Vector2 = actor.position
	match stage.mode:
		"path":
			var distance = stage.path.get_baked_length() * stage.progress_curve.sample(progress)
			var offset = stage.path.sample_baked(distance, true) - stage.path.get_point_position(0)
			actor.position = actor.stage_origin + offset.rotated(actor.stage_heading - PI / 2)
		"aim", "track":
			if stage.track_until_distance > 0 and actor.position.distance_to(world.player) <= stage.track_until_distance:
				actor.track_locked = true
			if stage.mode == "track" and not actor.track_locked:
				actor.rotation = rotate_toward(actor.rotation, (world.player + stage.track_target_offset - actor.position).angle(), deg_to_rad(stage.turn_speed) * dt)
			actor.position += Vector2.from_angle(actor.rotation) * stage.speed * actor.speed_scale * dt
		"velocity":
			actor.position = actor.stage_origin + Vector2.from_angle(actor.stage_heading) * stage.speed * actor.speed_scale * actor.stage_elapsed
		"sine":
			actor.rotation = actor.stage_heading + deg_to_rad(stage.sine_amplitude) * sin(actor.stage_elapsed * stage.sine_frequency + stage.sine_phase)
			actor.position += Vector2.from_angle(actor.rotation) * stage.speed * actor.speed_scale * movement_dt
		"ballistic":
			var time: float = actor.stage_elapsed
			actor.position = actor.stage_origin + actor.stage_velocity * time + Vector2(0, 0.5 * stage.gravity * time * time)
			var velocity: Vector2 = actor.stage_velocity + Vector2(0, stage.gravity * time)
			if velocity.length_squared() > 0.000001:
				actor.rotation = velocity.angle()
		"orbit":
			actor.orbit_angle += deg_to_rad(stage.orbit_speed) * dt
			var radius = lerpf(stage.orbit_radius, stage.orbit_end_radius, progress) if stage.orbit_end_radius >= 0 else stage.orbit_radius
			actor.position = _orbit_center(actor, world, stage) + Vector2.from_angle(actor.orbit_angle) * radius
	if stage.mode in ["path", "orbit"] and actor.position.distance_squared_to(previous) > 0.000001:
		actor.rotation = (actor.position - previous).angle()

static func _orbit_center(actor, world, stage: STGMotionStage) -> Vector2:
	match stage.orbit_center:
		"player": return world.player
		"origin": return actor.stage_origin
	return world.boss

static func _ballistic_velocity(origin: Vector2, target: Vector2, stage: STGMotionStage) -> Vector2:
	var delta = target - origin
	if not stage.ballistic_aim:
		var velocity = stage.initial_velocity
		velocity.x += clampf(delta.x * stage.velocity_x_player_factor, -stage.velocity_x_limit, stage.velocity_x_limit)
		return velocity
	var flight = stage.flight_time
	if flight <= 0:
		var distance = absf(delta.x) if stage.flight_distance_mode == "horizontal" else delta.length()
		flight = clampf(maxf(stage.flight_min_distance, distance) / stage.flight_speed, stage.flight_min_time, stage.flight_max_time)
	return Vector2(delta.x / flight, (delta.y - 0.5 * stage.gravity * flight * flight) / flight)


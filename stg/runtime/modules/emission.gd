@tool
extends STGEmissionExtension
const Geometry = preload("res://stg/definitions/fire_geometry.gd")
var locked_player: Vector2
var planned: Array[Dictionary] = []
var next_index: int = 0
var elapsed: float = 0.0
var batch: int = 0

func start(context: STGEmissionContext, _parameters: Dictionary) -> void:
	var world = context._world
	var shot: STGFirePattern = context._pattern
	var origin = context.origin()
	var heading = context.heading()
	var owner_id = context._owner_id
	var round_index = context.round_index
	locked_player = context._locked_player
	var center: Vector2 = origin
	match shot.anchor:
		"boss":
			center = world.boss
		"player":
			center = world.player
		"world":
			center = Vector2.ZERO
	if shot.anchor_axes == "x": center.y = 0
	elif shot.anchor_axes == "y": center.x = 0
	center += shot.offset
	for i in shot.count:
		var spawn = Geometry.spawn_point(shot, i)
		if shot.safe_gap_radius > 0:
			var delta = center + spawn - world.player
			if absf(delta.x if shot.safe_gap_axis == "x" else delta.y) < shot.safe_gap_radius: continue
		var angle = deg_to_rad(shot.angle + round_index * shot.rotation_per_round + i * shot.rotation_per_projectile) + heading
		angle = _shot_angle(world, shot, i, spawn, center, angle, round_index)
		# 关闭随机参数时不消耗随机数，确保旧预设的其他随机选择保持一致。
		if shot.angle_jitter > 0:
			angle += deg_to_rad(world.rng.randf_range(-shot.angle_jitter, shot.angle_jitter))
		var speed = 1.0
		if shot.enemy_id.is_empty(): speed = world.rng.randf_range(shot.speed_scale_min, shot.speed_scale_max) if shot.speed_scale_min != shot.speed_scale_max else shot.speed_scale_min
		# 召唤不消耗速度随机数，保持旧内容随机序列。
		# 先按完整轮规划，再调度批次；分组不能重新编号、重算扇面或另建弹道。
		if shot.group_size == 0: context.emit(center + spawn, angle, speed)
		else: planned.append({"at": center + spawn, "angle": angle, "speed": speed, "index": i})
	if shot.group_size == 0:
		# 齐射保持逐颗计算与生成的顺序，包含召唤实例取随机种子的时机。
		context.finish()
		return
	_emit_batch(context)
	if shot.group_interval <= 0:
		while next_index < planned.size(): _emit_batch(context)
	if next_index >= planned.size(): context.finish()

func tick(context: STGEmissionContext, dt: float) -> void:
	elapsed += dt
	while next_index < planned.size() and elapsed + 0.000001 >= batch * context._pattern.group_interval:
		context._step_duration = maxf(0, minf(dt, elapsed - batch * context._pattern.group_interval))
		_emit_batch(context)
	if next_index >= planned.size(): context.finish()

func _emit_batch(context: STGEmissionContext) -> void:
	var size: int = context._pattern.group_size
	var end = mini(planned.size(), next_index + size) if size > 0 else planned.size()
	# 安全缺口只跳过原序号，不把后续弹体提前填进这一批。
	var boundary: int = (batch + 1) * size
	while next_index < end and (size == 0 or planned[next_index].index < boundary):
		var shot = planned[next_index]
		context.emit(shot.at, shot.angle, shot.speed)
		next_index += 1
	batch += 1

func _shot_angle(world, shot: STGFirePattern, index: int, spawn: Vector2, center: Vector2, angle: float, round_index: int = 0) -> float:
	# 发射配置用度，运行角度用弧度；spawn 是相对 center 的排列偏移。
	match shot.direction:
		"fan":
			return angle + (deg_to_rad(shot.spread * (index / maxf(1, shot.count - 1) - 0.5)) if shot.count > 1 else 0.0)
		"outward":
			return spawn.angle() if spawn.length_squared() > 0.00001 else TAU * index / shot.count + angle
		"inward":
			return (-spawn).angle() if spawn.length_squared() > 0.00001 else TAU * index / shot.count + angle
		"aim":
			var fan = shot.spread * (index / maxf(1, shot.count - 1) - 0.5) if shot.aim_spread and shot.count > 1 else 0.0
			var round_offset = (round_index * shot.rotation_per_round if shot.aim_spread else 0.0) + index * shot.rotation_per_projectile
			var target: Vector2 = locked_player if shot.aim_lock == "call_start" else world.player
			return (target + shot.aim_target_offset - center - spawn).angle() + deg_to_rad(shot.aim_offset + round_offset + fan)
		"random":
			return world.rng.randf_range(0, TAU)
	return angle



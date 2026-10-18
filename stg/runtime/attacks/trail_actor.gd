@tool
class_name STGBulletTrailActor
extends STGBulletActor
## 尾迹子弹接口 attach_source/tick/rebase。每段使用独立出生时间，旧段留在战斗坐标里。
const TrailVisual = preload("res://stg/runtime/attacks/trail_visual.gd")
const MAX_SEGMENTS = 1024
var segments: Array = [] # {a, b, born, distance}；端点为战斗坐标，born 为本实例的出生秒数。
var source
var recording: bool = false
var last_sample: Vector2
var last_emitter: Vector2
var has_sample: bool = false
var distance: float = 0 # 已生成尾迹的累计长度，用于连续贴图 UV。
var emitter_path: Array = [] # {point, distance}；仅保留尾部偏移所需的一小段真实路径。
var path_distance: float = 0 # 发射者真实路径的累计长度，用于按路程取尾部偏移。

## 自定义覆盖：尾迹段保存绝对战斗坐标，Node2D 保持原点，忽略普通子弹的朝向。
func setup(prefab: STGBulletDefinition, config: STGProjectileDefinition, origin: Vector2, _angle: float, instance_owner: int) -> void:
	definition = prefab
	projectile = config
	lifecycle = config.lifecycle
	motion_stages = config.motion_stages
	owner_id = instance_owner
	position = Vector2.ZERO # 段的位置已经是战斗坐标，不再跟随 Boss 变换。
	last_sample = origin
	last_emitter = origin
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var geometry: STGBulletGeometry = prefab.collision.duplicate(true)
	geometry.offset = Vector2.ZERO
	geometry.rotation_degrees = 0
	collision = Collision.for_geometry(geometry)

## 自定义绑定：instance 是发射计划；录制停止后旧段仍按各自寿命继续运行。
func attach_source(instance, origin: Vector2) -> void:
	source = instance
	recording = true
	last_emitter = origin
	has_sample = false
	segments.clear()
	emitter_path = [{"point": origin, "distance": 0.0}]
	path_distance = 0

func seed_preview(origin: Vector2) -> void:
	# 单独编辑尾迹定义时展示静态示意，不假装这就是 Boss 的实际路径。
	segments = [{"a": origin, "b": origin + Vector2(100, 30), "born": 0.0, "distance": 0.0}, {"a": origin + Vector2(100, 30), "b": origin + Vector2(200, 0), "born": 0.0, "distance": 104.4}]

func tick(world, dt: float) -> void:
	if not alive or static_preview:
		return
	if first_step_duration >= 0:
		dt = minf(dt, first_step_duration)
		first_step_duration = -1
	age += dt
	show_collision = world.show_collision
	if source != null:
		recording = not source.cancelled and source.elapsed + 0.000001 < source.prefab.trail_duration
		if recording:
			_sample(world.boss)
	_tick_segments(world)
	if not recording and segments.is_empty():
		world.present_lifecycle(lifecycle.expire_sound, lifecycle.expire_effect, last_emitter, rotation, lifecycle.effect_duration)
		_emit_successor(world, lifecycle.on_expire_barrage_id, lifecycle.on_expire_behavior_id, last_emitter)
		stop()
		source = null
	queue_redraw()

func _tick_segments(world) -> void:
	# 每段使用 age - born；后生成的段不能继承整条尾迹已经消耗的寿命。
	var life = lifecycle.warning + motion_stages[0].duration + lifecycle.fade
	for i in range(segments.size() - 1, -1, -1):
		var part = segments[i]
		var part_age: float = age - part.born
		if part_age + 0.000001 >= life:
			segments.remove_at(i)
			continue
		var can_hit = age >= next_hit_at if lifecycle.hit_mode == "repeat" else not hit_once
		if can_hit and is_active(part_age):
			var ends = definition.collision.trail_endpoints(part.a, part.b)
			var closest = Geometry2D.get_closest_point_to_segment(world.player, ends[0], ends[1])
			if _segment_hits(part, part_age, world.player, world.player_radius):
				hit_once = true
				next_hit_at = age + lifecycle.hit_interval
				preload("res://stg/runtime/extensions/hit_effects.gd").apply(self, world, lifecycle.damage, closest)
				world.present_lifecycle(lifecycle.hit_sound, lifecycle.hit_effect, closest, rotation, lifecycle.effect_duration)
				_emit_successor(world, lifecycle.on_hit_barrage_id, lifecycle.on_hit_behavior_id, closest)

func _segment_hits(part: Dictionary, part_age: float, target: Vector2, radius: float) -> bool:
	var geometry = definition.collision
	if geometry.kind == "rectangle":
		var ends = geometry.trail_endpoints(part.a, part.b)
		var closest = Geometry2D.get_closest_point_to_segment(target, ends[0], ends[1])
		return target.distance_to(closest) <= collision_radius(part_age) + radius
	var placement = Transform2D((part.b - part.a).angle(), (part.a + part.b) / 2) * geometry.local_transform()
	var scale_factor = motion_stages[0].collision_scale_curve.sample(stage_progress(part_age))
	placement *= Transform2D(0, Vector2(part.a.distance_to(part.b), scale_factor), 0, Vector2.ZERO)
	return collision.hits_at(placement, Vector2.ZERO, target, radius)

func _sample(at: Vector2) -> void:
	var delta = at - last_emitter
	var previous_emitter = last_emitter
	last_emitter = at
	if delta.length() > definition.trail_break_distance:
		has_sample = false
		emitter_path = [{"point": at, "distance": 0.0}]
		path_distance = 0
		return # 瞬移会断开尾迹，不生成横跨画面的攻击线。
	if delta.length_squared() < 0.000001:
		return
	if emitter_path.is_empty():
		emitter_path.append({"point": previous_emitter, "distance": 0.0})
	var step_length: float = at.distance_to(emitter_path[-1].point)
	if step_length < definition.trail_spacing:
		return
	path_distance += step_length
	emitter_path.append({"point": at, "distance": path_distance})
	if path_distance < definition.trail_offset:
		return
	# 按走过的路程向后取点；直接减当前朝向会在突然转弯时把尾迹甩出真实路径。
	var sample_distance = path_distance - definition.trail_offset
	var point = _point_at_path_distance(sample_distance)
	_append_segment(point)

func _point_at_path_distance(sample_distance: float) -> Vector2:
	# 只保留目标路程左右的相邻样本，避免发射者历史路径无限增长。
	while emitter_path.size() > 1 and emitter_path[1].distance <= sample_distance:
		emitter_path.pop_front()
	var point: Vector2 = emitter_path[0].point
	if emitter_path.size() > 1:
		var before = emitter_path[0]
		var after = emitter_path[1]
		point = before.point.lerp(after.point, (sample_distance - before.distance) / (after.distance - before.distance))
	return point

func _append_segment(point: Vector2) -> void:
	if not has_sample:
		last_sample = point
		has_sample = true
		return
	var length = last_sample.distance_to(point)
	if length < definition.trail_spacing:
		return
	segments.append({"a": last_sample, "b": point, "born": age, "distance": distance})
	if segments.size() > MAX_SEGMENTS:
		segments.pop_front()
	distance += length
	last_sample = point
	if source != null and source.prefab.trail_max_length > 0:
		var cutoff: float = distance - source.prefab.trail_max_length
		while not segments.is_empty():
			var part = segments[0]
			var part_length: float = part.a.distance_to(part.b)
			if part.distance + part_length <= cutoff:
				segments.pop_front()
			elif part.distance < cutoff:
				part.a = part.a.lerp(part.b, (cutoff - part.distance) / part_length)
				part.distance = cutoff
				break
			else: break

## 自定义查询：part_age 为某一段的秒数；预警和淡出期间不产生伤害。
func is_active(part_age: float) -> bool:
	return part_age >= lifecycle.warning and part_age < lifecycle.warning + motion_stages[0].duration

## 自定义查询：把单段执行期秒数换成 0..1，供表现 / 碰撞曲线共享。
func stage_progress(part_age: float) -> float:
	return clampf((part_age - lifecycle.warning) / motion_stages[0].duration, 0, 1)

## 自定义查询：返回单段当前碰撞半径，独立于贴图的视觉宽度。
func collision_radius(part_age: float) -> float:
	return definition.collision.size.y / 2 * motion_stages[0].collision_scale_curve.sample(stage_progress(part_age))

## 自定义查询：返回单段透明度，预警、执行和淡出使用各自的年龄区间。
func segment_opacity(part_age: float) -> float:
	if part_age < lifecycle.warning:
		return 0.25
	var fade_age = part_age - lifecycle.warning - motion_stages[0].duration
	if fade_age <= 0:
		return 1
	return maxf(0, 1 - fade_age / maxf(0.000001, lifecycle.fade))

## 自定义导出接口：一次性把预览战斗坐标转为攻击原点坐标；不用于卷轴移动。
func rebase(offset: Vector2) -> void:
	for part in segments:
		part.a -= offset
		part.b -= offset
	for sample in emitter_path:
		sample.point -= offset
	last_sample -= offset
	last_emitter -= offset

func _draw() -> void: # Godot 回调；实际绘制在独立模块。
	if definition != null:
		TrailVisual.draw(self)



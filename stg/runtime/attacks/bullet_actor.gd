@tool
class_name STGBulletActor
extends Node2D
## 子弹场景实例。setup/tick/stop 是自定义运行接口，finished 在原实例结束时发出。
signal finished
const MotionRunner = preload("res://stg/runtime/attacks/motion_runner.gd")
const Collision = preload("res://stg/runtime/attacks/bullet_collision.gd")
const Visual = preload("res://stg/runtime/attacks/bullet_visual.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Frames = preload("res://stg/definitions/texture_frames.gd")
const Presentation = preload("res://stg/runtime/attacks/projectile_presentation.gd")
var presentation: Node2D
var particle_presentation: Node2D
var material_preview_time: float = 0.0
@export var definition: STGBulletDefinition
var projectile: STGProjectileDefinition
var lifecycle: STGAttackLifecycle
var motion_stages: Array[STGMotionStage] = []
var static_preview: bool = false
var first_step_duration: float = -1.0
var owner_id: int = 0
var age: float = 0.0 # 从实例出生起的秒数，包含预警。
var stage_index: int = -1
var stage_elapsed: float = 0.0 # 只记录当前运动阶段的执行秒数，不包含前一阶段。
var stage_origin: Vector2
var stage_heading: float = 0.0
var stage_velocity: Vector2 = Vector2.ZERO
var speed_scale: float = 1.0 # 发射时采样，整颗子弹的后续运动阶段沿用同一个倍率。
var orbit_angle: float = 0.0
var visual_scale: float = 1.0
var collision_scale: float = 1.0
var base_visual_scale: float = 1.0
var base_collision_scale: float = 1.0
var previous: Vector2
var fading: bool = false
var fade_elapsed: float = 0.0
var alive: bool = true
var hit_once: bool = false
var next_hit_at: float = 0.0
var track_locked: bool = false
var activation_checked: bool = false
var bounds_armed: bool = false
var show_collision: bool = false
var collision
var motion_session # 每次进入扩展阶段新建；共享定义资源中不保存这个对象。

## 自定义初始化：origin 为战斗坐标，angle 为弧度；碰撞形状只在出场时构建一次。
func setup(prefab: STGBulletDefinition, config: STGProjectileDefinition, origin: Vector2, angle: float, instance_owner: int) -> void:
	definition = prefab
	projectile = config
	lifecycle = config.lifecycle
	motion_stages = config.motion_stages
	position = origin
	previous = origin
	rotation = angle
	owner_id = instance_owner
	collision = Collision.build(prefab)
	bounds_armed = CombatSpace.BOUNDS.grow(lifecycle.bounds_margin).has_point(origin)

## 自定义固定步长更新：预警 → 运动 / 命中 → 下一阶段或淡出；dt 的单位是秒。
func tick(world, dt: float) -> void:
	if not alive or static_preview:
		return
	if first_step_duration >= 0:
		dt = minf(dt, first_step_duration)
		first_step_duration = -1
	previous = position
	age += dt
	if age < lifecycle.warning:
		queue_redraw()
		return
	if fading:
		fade_elapsed += dt
		if fade_elapsed + 0.000001 >= lifecycle.fade:
			stop()
		queue_redraw()
		return
	if stage_index < 0:
		_enter_stage(world, 0)
	if not alive:
		return
	var stage = motion_stages[stage_index]
	MotionRunner.advance(self, world, stage, dt)
	if not alive: return
	var can_check = age >= next_hit_at if lifecycle.hit_mode == "repeat" else not hit_once and (lifecycle.hit_mode == "persistent" or not activation_checked)
	activation_checked = true
	if can_check and collision.hits(self, world.player, world.player_radius):
		hit_once = true
		next_hit_at = age + lifecycle.hit_interval
		preload("res://stg/runtime/extensions/hit_effects.gd").apply(self, world, _contact_damage(world.player))
		world.present_lifecycle(lifecycle.hit_sound, lifecycle.hit_effect, position, rotation, lifecycle.effect_duration)
		if definition.visual.hit_clip != null or definition.form == "moving" and definition.hit_particles != null: world.present_material_hit(self)
		_emit_successor(world, lifecycle.on_hit_barrage_id, lifecycle.on_hit_behavior_id)
		if definition.form == "moving" and lifecycle.hit_mode != "repeat":
			stop()
	if alive and _crossed_exit():
		_expire(world)
		queue_redraw()
		return
	if alive and stage_elapsed + 0.000001 >= stage.duration:
		if stage_index + 1 < motion_stages.size():
			_enter_stage(world, stage_index + 1)
		else:
			_expire(world)
	queue_redraw() # Godot 内置：申请重绘

func _crossed_exit() -> bool:
	if lifecycle.exit_mode == "ground":
		if previous.y <= lifecycle.ground_y and position.y >= lifecycle.ground_y:
			var vertical_distance = position.y - previous.y
			if vertical_distance > 0.000001:
				position = previous.lerp(position, (lifecycle.ground_y - previous.y) / vertical_distance)
			return true
		return false
	if lifecycle.exit_mode == "bounds":
		var inside = CombatSpace.BOUNDS.grow(lifecycle.bounds_margin).has_point(position)
		if inside:
			bounds_armed = true
		return bounds_armed and not inside
	return false

func _contact_damage(target: Vector2) -> float:
	var geometry = definition.collision
	if definition.form == "area" and geometry.kind == "circle":
		var point = geometry.local_transform().affine_inverse() * ((target - position).rotated(-rotation) / maxf(collision_scale, 0.00001))
		var distance = (point / (geometry.size / 2)).length()
		if distance >= lifecycle.damage_falloff_start:
			return lifecycle.damage * lifecycle.damage_falloff_scale
	return lifecycle.damage

func _expire(world) -> void:
	MotionRunner.cancel(self, "expired")
	world.present_lifecycle(lifecycle.expire_sound, lifecycle.expire_effect, position, rotation, lifecycle.effect_duration)
	_emit_successor(world, lifecycle.on_expire_barrage_id, lifecycle.on_expire_behavior_id)
	fading = true
	fade_elapsed = 0
	if lifecycle.fade <= 0:
		stop()

func _emit_successor(world, barrage_id: String, behavior_id: String, event_position: Vector2 = Vector2.INF) -> void:
	var at = position if event_position == Vector2.INF else event_position
	if not barrage_id.is_empty():
		world.play_barrage(barrage_id, at, owner_id, rotation)
	if not behavior_id.is_empty():
		world.play_behavior(behavior_id, at, owner_id, rotation)

func _enter_stage(world, index: int) -> void:
	MotionRunner.cancel(self, "completed")
	stage_index = index
	var stage = motion_stages[index]
	MotionRunner.enter(self, world, stage)
	if stage.mode == "transform" and projectile.delivery != "position":
		world.emit_projectile(stage.transform_attack_id, position, rotation, owner_id)
		stop() # 变形后的实例继承归属，弹幕完成判定会继续等待它。

## 自定义结束接口：只标记并发信号；实际节点回收由所属 Simulation 统一完成。
func stop() -> void:
	if not alive:
		return
	alive = false
	MotionRunner.cancel(self, "stopped")
	finished.emit()

func _exit_tree() -> void:
	MotionRunner.cancel(self, "removed")

## 表现与正式运行状态分开，创建和推进由 simulation 统一调用。
func configure_presentation() -> void:
	if definition.visual_scene != null:
		presentation = Presentation.new()
		add_child(presentation)
		presentation.configure(definition.visual_scene, definition.visual_animation)
		presentation.place(self)
	if definition.form == "moving" and definition.run_particles != null:
		particle_presentation = Presentation.new()
		add_child(particle_presentation)
		particle_presentation.configure(definition.run_particles, "")
		particle_presentation.set_emitting(lifecycle.warning <= 0)
		particle_presentation.place(self)

func tick_presentation(dt: float) -> void:
	material_preview_time += dt
	for visual in [presentation, particle_presentation]:
		if not is_instance_valid(visual): continue
		visual.place(self)
		if visual == particle_presentation:
			visual.set_emitting(static_preview or age >= lifecycle.warning and not fading)
		visual.tick(dt)
	queue_redraw()

func current_texture() -> Texture2D:
	var visual = definition.visual
	var seconds = material_preview_time if static_preview else age
	if fading and visual.expire_clip != null:
		return Frames.texture_at(visual.expire_clip, fade_elapsed / maxf(lifecycle.fade, 0.000001) * Frames.duration(visual.expire_clip))
	if not static_preview and visual.spawn_clip != null:
		if lifecycle.warning > 0 and seconds < lifecycle.warning:
			return Frames.texture_at(visual.spawn_clip, seconds / lifecycle.warning * Frames.duration(visual.spawn_clip))
		if lifecycle.warning <= 0 and seconds < Frames.duration(visual.spawn_clip): return Frames.texture_at(visual.spawn_clip, seconds)
	var run_start: float = lifecycle.warning
	if not static_preview and lifecycle.warning <= 0 and visual.spawn_clip != null: run_start = Frames.duration(visual.spawn_clip)
	if visual.run_clip != null: return Frames.texture_at(visual.run_clip, maxf(0, seconds - run_start), true)
	return visual.texture

## 自定义绘制查询：返回当前透明度，不改变预警或淡出的运行状态。
func opacity() -> float:
	if definition == null:
		return 1
	if age < lifecycle.warning:
		return 0.2 + 0.25 * (sin(age * 18) + 1) / 2
	if fading:
		return maxf(0, 1 - fade_elapsed / maxf(0.00001, lifecycle.fade))
	return 1

func _draw() -> void: # Godot 回调：引擎要求重绘时调用
	Visual.draw(self)




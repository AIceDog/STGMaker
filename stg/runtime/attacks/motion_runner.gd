@tool
extends RefCounted
## 阶段时钟和通用尺寸变化归运行器所有；所有运动通过同一个能力会话执行。
const Session = preload("res://stg/runtime/extensions/extension_session.gd")
const Builtin = preload("res://stg/runtime/modules/motion.gd")
static func enter(actor, world, stage: STGMotionStage) -> void:
	actor.stage_origin = actor.position
	actor.stage_heading = actor.rotation
	actor.stage_elapsed = 0
	actor.base_visual_scale = actor.visual_scale
	actor.base_collision_scale = actor.collision_scale
	# 指定位置生成仍推进同一阶段及尺寸曲线，只是不创建运动能力。
	if actor.projectile.delivery == "position": return
	actor.motion_session = Session.new()
	var binding = stage.extension if stage.mode == "extension" else null
	var context = STGMotionContext.new(world)
	context._actor = actor
	if not actor.motion_session.begin(binding.definition if binding != null else null, binding.parameters if binding != null else {}, "motion", context, Builtin.new(stage) if stage.mode != "extension" else null):
		world.issue = actor.motion_session.issue
		actor.stop()

static func advance(actor, world, stage: STGMotionStage, dt: float) -> void:
	var movement_dt = minf(dt, maxf(0, stage.duration - actor.stage_elapsed))
	actor.stage_elapsed = minf(stage.duration, actor.stage_elapsed + dt)
	if actor.motion_session != null: actor.motion_session.tick(movement_dt)
	if actor.motion_session != null and actor.motion_session.finished:
		if actor.motion_session.failed:
			world.issue = "自定义运动执行失败"
			actor.stop()
			return
		actor.stage_elapsed = stage.duration
	var progress = clampf(actor.stage_elapsed / stage.duration, 0, 1)
	if stage.angular_speed != 0:
		actor.rotation = actor.stage_heading + deg_to_rad(stage.angular_speed) * actor.stage_elapsed
	actor.visual_scale = actor.base_visual_scale * stage.visual_scale_curve.sample(progress)
	actor.collision_scale = actor.base_collision_scale * stage.collision_scale_curve.sample(progress)

static func cancel(actor, reason: String) -> void:
	if actor.motion_session == null: return
	var session = actor.motion_session
	actor.motion_session = null
	session.cancel(reason)

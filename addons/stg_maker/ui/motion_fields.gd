@tool
extends RefCounted
## 招式的弹体飞行过程表单。
## scope 由调用者提供；表单不决定资源共享关系，不复制运行规则。
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Factory = preload("res://stg/definitions/definition_factory.gd")

static func build(host, box, stage: STGMotionStage, scope: Array) -> void:
	var modes = ["path", "aim", "track", "velocity", "sine", "ballistic", "orbit", "wait", "transform", "extension"]
	var names = ["沿曲线移动", "直线瞄准玩家", "持续追踪玩家", "沿发射方向直飞", "沿发射方向 S 形飞行", "重力抛射", "环绕 Boss", "停留", "变成另一种子弹", "自定义运动扩展"]
	F.select_inline(box, "飞行方式", stage.mode, modes, names, func(value):
		R.edit(host, scope, func(target, _project):
			target.mode = value
			if value == "path" and target.path == null: target.path = Factory.path()))
	var motion = box
	if stage.mode == "transform":
		R.resource_reference(host, motion, scope, "transform_attack_id", stage.transform_attack_id, "barrages", "变形后使用的招式弹体", func(item):
			var material = host.session.project.find("bullets", item.projectile.bullet_id) if item.projectile != null else null
			return material != null and material.form != "trail" and item.fire_pattern.enemy_id.is_empty())
		return
	R.number(host, motion, scope, stage, "duration", "持续时间 s", 0.01, 60)
	if stage.mode == "extension": _extension(host, motion, stage, scope)
	if stage.mode == "path": F.button(motion, "在画面编辑移动曲线", func(): host.edit_beam = false; host.set_tool("flight_path" if host.collection == "barrages" else "path"))
	if stage.mode in ["aim", "track", "velocity", "sine"]: R.number(host, motion, scope, stage, "speed", "速度 px/s", 0, 2000)
	if stage.mode == "sine":
		R.number(host, motion, scope, stage, "sine_amplitude", "方向摆幅 °", 0, 180)
		R.number(host, motion, scope, stage, "sine_frequency", "摆动频率 rad/s", 0, 60)
		R.number(host, motion, scope, stage, "sine_phase", "起始相位 rad", -TAU, TAU)
	if stage.mode == "ballistic": _ballistic(host, motion, stage, scope)
	if stage.mode == "track":
		R.number(host, motion, scope, stage, "turn_speed", "追踪转速 °/s")
		F.toggle(motion, "保留初始扇形方向再追踪", stage.preserve_heading, R.setter(host, scope, "preserve_heading"))
		R.vector(host, motion, scope, stage, "track_target_offset", "追踪目标偏移")
		R.number(host, motion, scope, stage, "track_until_distance", "停止追踪距离（0 不停止）", 0, 2000)
	if stage.mode == "orbit":
		F.select(motion, "环绕中心", stage.orbit_center, ["boss", "player", "origin"], ["Boss", "玩家", "出生点"], R.setter(host, scope, "orbit_center"))
		R.number(host, motion, scope, stage, "orbit_end_radius", "结束半径（-1 保持）", -1, 2000)
		R.number(host, motion, scope, stage, "orbit_radius", "环绕半径")
		R.number(host, motion, scope, stage, "orbit_speed", "环绕转速 °/s", -720, 720)
	var advanced = F.fold(box, "更多飞行参数", false, "motion.advanced")
	F.text(advanced, "过程名称", stage.title, R.setter(host, scope, "title", true))
	R.number(host, advanced, scope, stage, "angular_speed", "几何旋转 °/s", -1440, 1440)
	F.button(advanced, "编辑尺寸时间曲线", func(): host.open_curve(scope, "visual_scale_curve"))
	if stage.mode == "path": F.button(advanced, "编辑路径进度曲线", func(): host.open_curve(scope, "progress_curve"))

static func _extension(host, box, _stage: STGMotionStage, scope: Array) -> void:
	preload("res://addons/stg_maker/ui/extension_fields.gd").slot(host, box, scope, "extension", "motion", "运动扩展", false)

static func _ballistic(host, box, stage: STGMotionStage, scope: Array) -> void:
	R.number(host, box, scope, stage, "gravity", "重力 px/s²", -2000, 2000)
	F.toggle(box, "抛向玩家发射时的位置", stage.ballistic_aim, R.setter(host, scope, "ballistic_aim", true))
	if not stage.ballistic_aim:
		R.vector(host, box, scope, stage, "initial_velocity", "世界坐标初速度 px/s")
		R.number(host, box, scope, stage, "velocity_x_player_factor", "玩家横向距离 × 速度系数", -2, 2, 0.01)
		R.number(host, box, scope, stage, "velocity_x_limit", "横向速度上限 px/s", 0, 2000)
		F.note(box, "Y 正方向朝下。距离系数为 0 时，完全使用设定初速度。")
		return
	R.number(host, box, scope, stage, "flight_time", "飞抵目标时间 s（0 自动）", 0, 60, 0.01)
	var automatic = F.fold(box, "自动估算飞行时间", false, "bullet.ballistic.auto")
	F.select(automatic, "估算距离", stage.flight_distance_mode, ["distance", "horizontal"], ["直线距离", "横向距离"], R.setter(host, scope, "flight_distance_mode"))
	R.number(host, automatic, scope, stage, "flight_speed", "估算速度 px/s", 1, 2000)
	R.number(host, automatic, scope, stage, "flight_min_distance", "最小估算距离", 0, 2000)
	R.number(host, automatic, scope, stage, "flight_min_time", "最短飞行时间 s", 0.01, 60)
	R.number(host, automatic, scope, stage, "flight_max_time", "最长飞行时间 s", 0.01, 60)
	F.note(automatic, "仅在飞抵目标时间为 0 时使用；进入阶段时计算一次初速度。")


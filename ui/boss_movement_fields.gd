@tool
extends RefCounted
## 移动表单共用接口 build：Boss 动作与攻击库招式使用同一组字段。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const Coordinates = preload("res://addons/stg_maker/ui/coordinate_fields.gd")

static func build(host, box, move: STGBossMovement, scope: Array, mode_changed: Callable = Callable()) -> void:
	var change_mode = mode_changed if mode_changed.is_valid() else func(value):
		R.edit(host, scope, func(config, _project):
			config.mode = value
			if value in ["teleport", "ballistic"] and config.aiming == "track": config.aiming = "snapshot"
		)
	F.select(box, "移动方式", move.mode, STGBossMovement.MODES, STGBossMovement.LABELS, change_mode)
	if move.mode == "none": return
	var parameters = F.group(box, "移动参数")
	if move.mode != "teleport": R.number(host, parameters, scope, move, "duration", "移动时长 s", 0.01, 60)
	if move.mode in ["line", "dash"]: R.number(host, parameters, scope, move, "speed", "固定速度 px/s（0 按目标插值）", 0, 3000)
	if move.mode == "curve": F.button(parameters, "在画面编辑移动曲线", func(): host.set_tool("skill_path" if host.collection == "barrages" else "path"))
	elif move.mode == "orbit": _orbit(host, parameters, move, scope)
	elif move.mode == "ballistic": _ballistic(host, parameters, move, scope)
	else: _target(host, parameters, move, scope)
	if move.mode == "burrow":
		var underground = F.group(parameters, "地下状态")
		F.toggle(underground, "地下隐藏外观", move.hide_while_buried, R.setter(host, scope, "hide_while_buried"))
		F.toggle(underground, "地下不受伤害", move.invulnerable_while_buried, R.setter(host, scope, "invulnerable_while_buried"))
	elif move.mode != "teleport":
		var collision = F.fold(parameters, "身体攻击", false, "movement.body")
		F.toggle(collision, "移动中身体造成伤害", move.body_attack, R.setter(host, scope, "body_attack", true))
		if move.body_attack:
			R.number(host, collision, scope, move, "body_radius", "身体半径", 1, 300)
			R.number(host, collision, scope, move, "body_damage", "伤害", 0, 1000)

static func _ballistic(host, box, move: STGBossMovement, scope: Array) -> void:
	F.select(box, "初速度方向", move.velocity_mode, ["fixed", "direction", "horizontal"], ["固定世界坐标方向", "朝目标方向冲出", "横向朝目标，保留纵向速度"], R.setter(host, scope, "velocity_mode", true))
	R.vector(host, box, scope, move, "initial_velocity", "初速度 px/s")
	R.number(host, box, scope, move, "gravity", "重力 px/s²", -2000, 3000)
	if move.velocity_mode != "fixed": _target(host, box, move, scope)
	if move.velocity_mode == "direction": F.note(box, "朝目标冲出时，初速度长度决定速度大小，方向取目标方向。")
	elif move.velocity_mode == "horizontal": F.note(box, "X 速度大小按设定，左右方向取目标所在侧；Y 速度保持设定。")
	F.note(box, "移动开始时确定初速度；之后按重力运动。Y 正方向朝下，负 Y 初速度向上跳。")

static func _target(host, box, move, scope: Array) -> void:
	Coordinates.target(host, box, scope, move)
	F.button(box, "在画面拖动目标点", func(): host.set_tool("skill_target" if host.collection == "barrages" else "target"))
	var target = F.fold(box, "目标坐标与追踪", false, "movement.target")
	R.vector(host, target, scope, move, "target", "固定坐标" if move.target_mode == "world" else "相对基准的偏移")
	if move.target_mode != "player": return
	var modes = ["snapshot", "predict"] if move.mode in ["teleport", "ballistic"] else ["snapshot", "track", "predict"]
	var names = ["锁定位置", "预测位置"] if move.mode in ["teleport", "ballistic"] else ["锁定位置", "持续追踪", "预测位置"]
	F.select(target, "瞄准方式", move.aiming, modes, names, R.setter(host, scope, "aiming", true))
	if move.aiming != "track": F.select(target, "读取玩家位置", move.lock_at, ["windup", "active"], ["前摇开始时", "移动开始时"], R.setter(host, scope, "lock_at"))
	if move.aiming == "predict": R.number(host, target, scope, move, "prediction", "预测提前 s", 0, 5)
	if move.aiming == "track": R.number(host, target, scope, move, "turn_speed", "转向 °/s", 0, 1440)

static func _orbit(host, box, move, scope: Array) -> void:
	Coordinates.target(host, box, scope, move, "环绕圆心基准")
	if move.target_mode == "player": F.toggle(box, "圆心持续跟随玩家", move.orbit_follow_center, R.setter(host, scope, "orbit_follow_center", true))
	R.number(host, box, scope, move, "orbit_end_radius", "结束半径", 0, 1000)
	R.number(host, box, scope, move, "orbit_turns", "环绕圈数（负数反向）", -20, 20, 0.1)
	F.label(box, "从 Boss 与圆心的当前距离开始；结束半径更小就缩圈，尾迹保留在原路径上。")
	F.button(box, "编辑缩圈速度曲线", func(): host.open_curve(scope, "orbit_progress_curve"))
	var center = F.fold(box, "圆心坐标与锁定", false, "movement.center")
	R.vector(host, center, scope, move, "target", "固定坐标" if move.target_mode == "world" else "圆心偏移")
	F.button(center, "在画面拖动圆心", func(): host.set_tool("skill_target" if host.collection == "barrages" else "target"))
	if move.target_mode == "player" and not move.orbit_follow_center: F.select(center, "锁定圆心时机", move.lock_at, ["windup", "active"], ["前摇开始", "移动开始"], R.setter(host, scope, "lock_at"))

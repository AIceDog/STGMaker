@tool
extends RefCounted
## Boss 移动在动作段与招式中共用，校验也只保留一份。
const Curves = preload("res://stg/definitions/curve_validation.gd")

static func check(move: STGBossMovement, issues: PackedStringArray, title: String) -> void:
	if move == null:
		issues.append(title + "：缺少移动配置")
		return
	for value in [move.duration, move.speed, move.prediction, move.turn_speed, move.body_radius, move.body_damage, move.orbit_end_radius]:
		if not is_finite(value) or value < 0:
			issues.append(title + "：移动参数需要非负有限数值")
	if move.duration <= 0 or move.body_radius <= 0:
		issues.append(title + "：移动时长与身体半径必须大于零")
	if not move.target.is_finite():
		issues.append(title + "：移动目标坐标无效")
	if move.mode not in STGBossMovement.MODES or move.target_mode not in ["relative", "player", "world"]:
		issues.append(title + "：移动方式 / 坐标基准无效")
	if move.aiming not in ["snapshot", "track", "predict"] or move.lock_at not in ["windup", "active"]:
		issues.append(title + "：瞄准 / 锁定方式无效")
	if move.mode == "curve":
		Curves.check_path(move.path, issues, title)
	if move.mode == "orbit":
		if not is_finite(move.orbit_turns) or absf(move.orbit_turns) > 20:
			issues.append(title + "：环绕圈数需在 -20 到 20 之间")
		Curves.check_curve(move.orbit_progress_curve, issues, title, true)
	if move.mode == "ballistic":
		if not move.initial_velocity.is_finite() or not is_finite(move.gravity) or move.gravity < 0:
			issues.append(title + "：重力跳跃的初速度 / 重力无效")
		if move.velocity_mode not in ["fixed", "direction", "horizontal"]:
			issues.append(title + "：重力跳跃的初速度方向无效")

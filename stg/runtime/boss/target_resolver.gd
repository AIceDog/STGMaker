@tool
extends RefCounted
## 唯一目标解析接口 resolve：预览与实机使用同样的玩家坐标、速度和锁定时机。
## 自定义纯坐标查询：origin 为移动起点；返回相对 / 玩家 / 固定目标的战斗坐标。
static func resolve(world, movement: STGBossMovement, origin: Vector2) -> Vector2:
	match movement.target_mode:
		"relative":
			return origin + movement.target
		"player":
			var prediction = world.player_velocity * movement.prediction if movement.aiming == "predict" else Vector2.ZERO
			return world.player + prediction + movement.target
	# 独立 Boss 的世界偏移为 0；关卡实例的固定目标随出生点及卷轴整体平移。
	# 玩家目标仍读取当前玩家位置，已经发射的攻击不使用这个移动坐标偏移。
	return movement.target + world.environment_offset

@tool
extends RefCounted
## 坐标说明只描述偏移如何计算；“使用玩家坐标”与“持续跟随”是不同设置。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")

static func target(host, box, scope: Array, movement: STGBossMovement, title: String = "目标位置基准") -> void:
	F.select(box, title, movement.target_mode, ["relative", "player", "world"], ["Boss 起点 + 偏移", "玩家位置 + 偏移", "固定战斗坐标"], R.setter(host, scope, "target_mode", true))
	F.label(box, explanation(movement.target_mode))

static func explanation(mode: String) -> String:
	match mode:
		"relative": return "以移动开始时的 Boss 位置为基准。例如 (0, -100) 表示从起点向上 100。"
		"player": return "在指定时机读取玩家位置再加偏移。持续跟随由追踪 / 跟随圆心设置决定。"
	return "直接指定战斗中的固定位置；预览网格中心为 (0, 0)，不随 Boss 或玩家移动。"

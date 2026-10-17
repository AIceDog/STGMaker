@tool
extends RefCounted
## 复用实体表单；卷轴、离场与碰撞属于实体定义。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")

static func build(host, box, settings: STGEntitySettings) -> void:
	var scope = ["entity_settings"]
	var movement = F.group(box, "卷轴与离场")
	F.select(movement, "环境移动", settings.movement_policy, ["scroll", "independent"], ["跟随卷轴 + 自身行为", "独立行动"], R.setter(host, scope, "movement_policy", true))
	if settings.movement_policy == "scroll": R.number(host, movement, scope, settings, "scroll_factor", "卷轴倍率", 0, 3)
	F.select(movement, "边界回收", settings.exit_boundary, ["left", "screen", "never"], ["越过左侧", "离开任意边界", "不按边界回收"], R.setter(host, scope, "exit_boundary", true))
	if settings.exit_boundary != "never":
		R.number(host, movement, scope, settings, "exit_margin", "屏幕外余量", 0, 300)
		F.toggle(movement, "进入过屏幕后才回收", settings.require_screen_entry, R.setter(host, scope, "require_screen_entry"))
	R.number(host, movement, scope, settings, "lifetime", "最多停留 s", 0, 600)
	F.note(movement, "0 表示不按时间离场。追踪玩家在行为动作的移动模块设置，关卡不另写追踪规则。")
	F.toggle(movement, "关卡阶段结束后继续存在", settings.persist_across_segments, R.setter(host, scope, "persist_across_segments"))
	var body = F.fold(box, "实体碰撞与受击", false)
	R.number(host, body, scope, settings, "body_radius", "实体半径", 1, 150)
	F.toggle(body, "可以被玩家破坏", settings.destructible, R.setter(host, scope, "destructible"))
	R.number(host, body, scope, settings, "contact_damage", "接触伤害", 0, 100)
	F.note(body, "用于关卡接触和测试射击；子弹碰撞仍在子弹定义中设置。")

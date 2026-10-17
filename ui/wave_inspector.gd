@tool
extends RefCounted
## 编队只安排出场与目标参与；实体移动、外形、碰撞在引用的定义中修改。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")

static func build(host, box, wave: STGWaveDefinition) -> void:
	F.select(box, "实体类型", wave.kind, ["enemy", "obstacle"], ["敌人 / Boss", "障碍物"], R.setter(host, [], "kind", true))
	var collection = "bosses" if wave.kind == "enemy" else "obstacles"
	var key = "enemy_id" if wave.kind == "enemy" else "obstacle_id"
	R.resource_reference(host, box, [], key, wave.get(key), collection, "使用实体定义")
	R.reference_editor(host, box, collection, wave.get(key), "编辑实体的行为 / 外形 / 离场 →")
	if wave.kind == "obstacle": F.button(box, "新建障碍定义并使用 →", func(): host.LevelCommands.add_obstacle_for_wave(host))
	var group = F.group(box, "出场排列")
	R.number(host, group, [], wave, "count", "数量", 1, 32, 1)
	R.number(host, group, [], wave, "interval", "出场间隔 s", 0, 10)
	R.vector(host, group, [], wave, "spacing", "相邻实体偏移")
	F.toggle(box, "参与本阶段清场", wave.counts_for_clear, R.setter(host, [], "counts_for_clear"))
	F.note(box, "全部击败统计本阶段所有敌人；指定击败统计选定出场的所有成员，不受这个清场选项影响。")
	F.note(box, "编队条表示生成过程，条结束不会删除敌人。卷轴、追踪、贴图与碰撞由实体定义负责。")

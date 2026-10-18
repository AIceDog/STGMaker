@tool
class_name STGLevelExitRule
extends Resource
## mode 决定时间是否参与结束判定；condition 决定目标。目标型阶段的 duration 只是计划长度。
const MODES = ["time", "condition", "time_and_condition"]
const MODE_LABELS = ["到时继续", "目标达成后继续", "到时且目标达成后继续"]
const CONDITIONS = ["clear", "defeat_all", "defeat_target"]
const CONDITION_LABELS = ["本阶段清场（允许离场）", "本阶段敌人全部击败", "指定敌人批次全部击败"]
@export_enum("time", "condition", "time_and_condition") var mode: String = "time_and_condition"
@export_enum("clear", "defeat_all", "defeat_target") var condition: String = "clear"
@export var target_event_id: String = ""
@export var wait_attacks: bool = true

## 自定义纯查询：事件是否属于本阶段的条件目标。实际生成数量与死亡结果由运行器记录。
## 指定目标仍按事件 ID 筛选；目标必须引用敌人的约束由保存 / 运行前校验负责。
func includes_event(event_id: String, entity_kind: String, counts_for_clear: bool) -> bool:
	match condition:
		"defeat_target":
			return event_id == target_event_id
		"defeat_all":
			return entity_kind == "enemy"
	return counts_for_clear

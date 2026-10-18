@tool
class_name STGFlowNode
extends Resource
## 动作段、条件分支、随机分支。空连接表示本轮结束；没有隐式父子关系。
const KINDS = ["action", "condition", "random", "attack", "wait", "parallel", "call"]
const LABELS = ["动作段", "条件分支", "随机分支", "释放招式", "等待", "并行", "调用行为"]
const SUCCESS = "@success" # 随机分支的返回点；由流程运行器处理。
const FAILURE = "@failure"
@export var id: String = ""
@export var title: String = "动作段"
@export_enum("action", "condition", "random", "attack", "wait", "parallel", "call") var kind: String = "action"
@export var next_id: String = ""
@export var failure_id: String = ""
@export var choices: PackedStringArray = []
@export var editor_position: Vector2 = Vector2.ZERO # 编辑图画布坐标，不是敌人在战斗中的位置。
@export var action: STGBossAction
@export_enum("distance", "hp", "cooldown", "recent_hit", "extension") var condition: String = "distance"
@export_enum("less_equal", "greater_equal") var comparison: String = "less_equal"
@export var threshold: float = 150 # distance 为设计单位，hp 为百分比，cooldown / recent_hit 为秒。
@export var extension: STGExtensionBinding
@export var reference_id: String = ""
@export var barrage_id: String = ""
@export var behavior_id: String = ""
@export_enum("immediate", "emission", "cleared") var wait_mode: String = "immediate"
@export var delay: float = 1.0
# 节点不反向静态依赖流程脚本，避免 Godot 全局类型互相持有而无法卸载；校验限定为行为流程。
@export var children: Array[Resource] = []

func outputs() -> PackedStringArray:
	if kind == "random":
		var result = choices.duplicate()
		result.append(next_id)
		result.append(failure_id)
		return result
	return PackedStringArray([next_id, failure_id])

func output_labels() -> PackedStringArray:
	if kind == "condition":
		return PackedStringArray(["是", "否"])
	if kind != "random":
		return PackedStringArray(["完成 → 下一步", "中断 / 失败"])
	var result = PackedStringArray()
	for i in choices.size():
		result.append("分支 %d" % (i + 1))
	result.append("分支完成")
	result.append("全部失败")
	return result

func set_output(port: int, target: String) -> void:
	if kind == "random" and port < choices.size():
		choices[port] = target
	elif port == (choices.size() if kind == "random" else 0):
		next_id = target
	else:
		failure_id = target

static func is_terminal(id: String) -> bool:
	return id.is_empty() or id in [SUCCESS, FAILURE]

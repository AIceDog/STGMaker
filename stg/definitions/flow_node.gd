@tool
class_name STGFlowNode
extends Resource
## 节点只保存契约预设、参数与图结构；不存在旧节点类型和专属配置回退。
const SUCCESS = "@success"
const FAILURE = "@failure"
@export var id: String = ""
@export var title: String = "行为节点"
@export var editor_position: Vector2 = Vector2.ZERO
@export var behavior_preset: STGBehaviorPreset
@export var program_parameters: Dictionary = {}
@export var connections: Dictionary = {}
@export var children: Array[Resource] = []
func parameters() -> Dictionary: return behavior_preset.parameters(program_parameters) if behavior_preset != null else {}
func ports() -> Array[Dictionary]:
    return behavior_preset.program.ports(parameters()) if behavior_preset != null and behavior_preset.program != null else []
func outputs() -> PackedStringArray:
    var result = PackedStringArray()
    for port in ports(): result.append(str(connections.get(str(port.get("id","")),"")))
    return result
func output_labels() -> PackedStringArray:
    var result = PackedStringArray()
    for port in ports(): result.append(str(port.get("label",port.get("id",""))))
    return result
func set_output(index: int, target: String) -> void:
    var values = ports()
    if index >= 0 and index < values.size(): connections[str(values[index].get("id",""))] = target
func target(port: String) -> String: return str(connections.get(port,""))
static func is_terminal(value: String) -> bool: return value.is_empty() or value in [SUCCESS,FAILURE]

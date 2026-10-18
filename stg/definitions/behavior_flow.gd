@tool
class_name STGBehaviorFlow
extends Resource
## 行为流程：连线就是下一步。稳定 ID 避免 Resource 之间互相引用。
@export var id: String = ""
@export var title: String = "新行为流程"
@export_multiline var description: String = ""
@export var entry_id: String = ""
@export var loop_entry_id: String = "" # 阶段循环时的起点，空值沿用 entry_id；入场等前缀可以只执行一次。
@export var nodes: Array[STGFlowNode] = []

func find(id: String) -> STGFlowNode:
	for node in nodes:
		if node != null and node.id == id:
			return node
	return null

func index_of(id: String) -> int:
	for i in nodes.size():
		if nodes[i] != null and nodes[i].id == id:
			return i
	return -1

func links() -> Array:
	var result: Array = []
	for node in nodes:
		if node == null:
			continue
		for port in node.outputs().size():
			result.append({"from": node.id, "port": port, "to": node.outputs()[port]})
	return result

@tool
class_name STGWorldLocation
extends Resource
## 世界地图中的战斗入口。引用稳定的关卡 ID，通关前置关系也使用地点 ID。
@export var id: String = ""
@export var title: String = "新地点"
@export_multiline var description: String = ""
@export var map_position: Vector2 = Vector2.ZERO
@export var level_id: String = ""
@export var requires_completion: Array[String] = []
@export_range(0, 999999) var reward: int = 100

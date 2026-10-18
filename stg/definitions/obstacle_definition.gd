@tool
class_name STGObstacleDefinition
extends Resource
## 障碍是可复用实体定义：有外形和生命周期，不执行敌人 AI。
@export var id: String = ""
@export var title: String = "岩石障碍"
@export var texture: Texture2D
@export var color: Color = Color("c49b74")
@export var entity_settings: STGEntitySettings

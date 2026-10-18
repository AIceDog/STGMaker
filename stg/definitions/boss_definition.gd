@tool
class_name STGBossDefinition
extends Resource
@export var visual_scene: PackedScene
## Boss 的表现与行为编排。阶段按 enter_hp 从大到小排列。
@export var id: String = ""
@export var title: String = "新 Boss"
@export_multiline var description: String = ""
@export var on_death_skill_id: String = "" # 真正死亡后调用一次；离场不会触发。死亡招式继续使用正式动作运行器。
@export var on_death_behavior_id: String = ""
@export var texture: Texture2D
@export var color: Color = Color("aa8bff")
@export var start_position: Vector2 = Vector2(0, -150) # 资产定义的战斗坐标；运行中位置由实例持有。
@export var phases: Array[STGBossPhase] = []
@export var entity_settings: STGEntitySettings # 卷轴、离场、关卡实体碰撞；不改变独立 Boss 的 AI。

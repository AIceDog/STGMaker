@tool
class_name STGProjectileDefinition
extends Resource
## 招式拥有的单颗弹体配置。素材只保存外观和碰撞；运动与战斗生命周期在此组合。
@export var bullet_id: String = ""
@export var motion_stages: Array[STGMotionStage] = []
@export var lifecycle: STGAttackLifecycle
@export_enum("trajectory", "position") var delivery: String = "trajectory" # position 使用同一阶段时钟，但不执行运动能力。

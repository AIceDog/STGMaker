@tool
class_name STGBarrageSkill
extends Resource
## 招式只保存程序预设快照及开放参数覆盖，不存在旧发射/运动配置分支。
@export var id: String = ""
@export var title: String = "新招式"
@export_multiline var description: String = ""
@export var attack_preset: STGAttackPreset
@export var program_parameters: Dictionary = {}
@export var reference_override: String = ""
func kind(_project) -> String:
 if attack_preset==null or attack_preset.program==null:return "moving"
 return {"Body2D":"moving","Beam2D":"laser","Polyline2D":"laser","Trail2D":"trail","Area2D":"area","SummonEnemy":"summon"}.get(attack_preset.program.capability,"moving")

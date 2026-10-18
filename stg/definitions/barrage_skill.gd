@tool
class_name STGBarrageSkill
extends Resource
## 一份招式只有一套发射规则和一份弹体配置；不同攻击的组合交给行为流程。
@export var id: String = ""
@export var title: String = "新弹幕招式"
@export_multiline var description: String = ""
@export var fire_pattern: STGFirePattern
@export var projectile: STGProjectileDefinition
@export var trail_duration: float = 6 # 生成多久；停止生成后，已有段仍按定义的寿命收尾。
@export var trail_max_length: float = 0 # 战斗坐标中的路径长度；0 表示只由每段寿命限制。

func kind(project) -> String:
	if fire_pattern != null and not fire_pattern.enemy_id.is_empty(): return "summon"
	var material = project.find("bullets", projectile.bullet_id) if projectile != null else null
	return material.form if material != null else "moving"

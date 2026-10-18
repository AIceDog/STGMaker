@tool
class_name STGPlayerDefinition
extends Resource
## 主角的共享配置。生命、位置和无敌倒计时由游戏会话持有，不能写回资源。
@export var controller: STGExtensionBinding
@export var weapon: STGExtensionBinding
@export var ability: STGExtensionBinding
@export_range(1, 99) var max_health: int = 3
@export var move_speed: float = 260
@export var hit_radius: float = 4
@export var fire_interval: float = 0.15
@export var shot_speed: float = 720
## 当前战斗框架使用最大生命值百分比扣血，25 表示命中四次击败普通单血条敌人。
@export var shot_damage: float = 25
@export var shot_lifetime: float = 1.5

func validate() -> PackedStringArray:
	var errors = PackedStringArray()
	if max_health < 1 or max_health > 99:
		errors.append("主角生命必须在 1～99 之间")
	for field in ["move_speed", "hit_radius", "fire_interval", "shot_speed", "shot_damage", "shot_lifetime"]:
		var value: float = get(field)
		if not is_finite(value) or value <= 0:
			errors.append("主角参数 %s 必须为有限正数" % field)
	for slot in [controller, weapon, ability]:
		if slot != null: errors.append_array(slot.validate("player"))
	return errors

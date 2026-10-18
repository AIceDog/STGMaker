@tool
extends "res://stg/definitions/definition_factory.gd"
## 编辑器默认项目；共享构造规则在 definition_factory.gd，成品不包含示例填充。

static func populate(project) -> void:
	project.schema_version = STGProject.VERSION
	var trail_id = _populate_example_bullets(project)
	_append_example_barrages(project)
	project.bosses.append(_create_example_boss(project))
	project.barrages.append(trail_attack(trail_id))

static func _populate_example_bullets(project) -> String:
	var moving = bullet()
	moving.title = "翡翠曲线弹"
	moving.id = "bullet_green"
	var laser = bullet("laser")
	laser.title = "预警激光"
	laser.id = "bullet_laser"
	var area = bullet("area")
	area.title = "圆形预警弹"
	area.id = "bullet_area"
	var trail = bullet("trail")
	trail.id = "bullet_trail"
	project.bullets.assign([moving, laser, area, trail])
	return trail.id

static func _append_example_barrages(project) -> void:
	var moving_id: String = project.bullets[0].id
	var laser_id: String = project.bullets[1].id
	var area_id: String = project.bullets[2].id
	for pair in [[moving_id, "fan"], [moving_id, "ring"], [moving_id, "spiral"], [laser_id, "cross"], [area_id, "area"]]:
		project.barrages.append(barrage(pair[0], pair[1]))

static func _create_example_boss(project) -> STGBossDefinition:
	var first_boss = boss(project.barrages[0].id)
	first_boss.title = "示例 Boss"
	var rage = phase(project.barrages[3].id)
	rage.title = "狂暴阶段"
	rage.enter_hp = 50
	var teleport = action("teleport")
	teleport.movement.target_mode = "player"
	teleport.movement.target = Vector2(100, 0)
	rage.behavior_flow = flow([teleport, action("fire", project.barrages[3].id), action("wait")])
	first_boss.phases.append(rage)
	return first_boss

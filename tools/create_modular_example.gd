extends SceneTree
## 可重复生成独立资产示例；只写 game/content/modular_example 内登记的文件。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Assets = preload("res://addons/stg_maker/authoring/asset_store.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")

func _initialize() -> void:
	var library = STGProject.create()
	library.schema_version = STGProject.VERSION
	var bullet = Factory.bullet()
	bullet.id = "modular_orb"
	bullet.title = "模块示例弹丸"
	var spark: STGBulletDefinition = Copy.copy(bullet)
	spark.id = "modular_spark"
	spark.title = "命中火花"
	spark.visual.geometry.size = Vector2(6, 6)
	spark.collision.size = Vector2(6, 6)
	library.bullets.assign([bullet, spark])
	var followup = Factory.barrage(spark.id)
	followup.id = "modular_followup"
	followup.title = "命中后的短促弹圈"
	followup.fire_pattern.direction = "outward"
	followup.projectile.motion_stages[0].speed = 110
	followup.projectile.motion_stages[0].duration = 0.35
	var burst = Factory.extension_binding(load("res://game/extensions/effects/hit_burst.tres"))
	burst.parameters.skill = followup.id
	
	var skill = Factory.barrage(bullet.id)
	skill.id = "modular_spiral"
	skill.title = "模块示例 · 分批螺旋"
	skill.projectile.motion_stages[0].speed = 110
	skill.projectile.motion_stages[0].duration = 2
	skill.projectile.lifecycle.hit_effects.append(burst)
	skill.fire_pattern.extension = Factory.extension_binding(load("res://game/extensions/emissions/spiral.tres"))
	library.barrages.assign([skill, followup])
	var enemy = Factory.boss(skill.id)
	enemy.id = "modular_bat"
	enemy.title = "模块示例 · 俯冲敌人"
	var flow = enemy.phases[0].behavior_flow
	var node = flow.nodes[0]
	node.action.extension = Factory.extension_binding(load("res://game/extensions/actions/dive.tres"))
	node.action.extension.parameters.skill = skill.id
	node.action.duration = 1.5
	var condition = STGFlowNode.new()
	condition.id = "health_gate"
	condition.title = "自定义血量条件"
	condition.kind = "condition"
	condition.condition = "extension"
	condition.extension = Factory.extension_binding(load("res://game/extensions/conditions/health_gate.tres"))
	condition.next_id = node.id
	flow.nodes.append(condition)
	flow.entry_id = condition.id
	library.bosses.append(enemy)
	var wave = Factory.wave(enemy.id)
	wave.id = "modular_wave"
	wave.count = 1
	library.waves.append(wave)
	var level = Factory.level(wave.id)
	level.id = "modular_level"
	level.title = "统一模块示例"
	level.segments[0].duration = 5
	level.segments[0].exit_rule.mode = "time"
	library.levels.append(level)
	var game = STGGameDefinition.new()
	game.title = "STGMaker · 模块扩展示例"
	game.library = library
	game.player = STGPlayerDefinition.new()
	game.player.weapon = Factory.extension_binding(load("res://game/extensions/players/spread_weapon.tres"))
	game.player.ability = Factory.extension_binding(load("res://game/extensions/players/dash.tres"))
	game.world = STGWorldDefinition.new()
	var location = STGWorldLocation.new()
	location.id = "module_island"
	location.title = "模块演练场"
	location.level_id = level.id
	game.world.locations.append(location)
	game.start_location_id = location.id
	var issues = game.validate()
	if not issues.is_empty():
		push_error("；".join(issues))
		quit(1)
		return
	var issue = Assets.save_game(game, "res://game/content/modular_example/game.tres", "res://game/content/modular_example/library.tres")
	if not issue.is_empty(): push_error(issue)
	print("MODULAR EXAMPLE RESULT: 1 checks, %d failures" % (0 if issue.is_empty() else 1))
	quit(0 if issue.is_empty() else 1)


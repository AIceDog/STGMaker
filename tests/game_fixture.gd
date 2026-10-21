extends RefCounted
## 只在测试使用的小型游戏。用于游戏运行和构建回归，不生成默认游戏。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")

static func create() -> STGGameDefinition:
    var library = preload("res://tests/unified14_fixture.gd").project()
    var enemy = library.bosses[0]
    enemy.title = "测试守卫"
    enemy.phases.resize(1)
    var idle = D.flow_node("wait", {"execution_duration":20.0})
    enemy.phases[0].behavior_flow = D.flow([idle])
    enemy.entity_settings.movement_policy = "independent"
    enemy.entity_settings.lifetime = 0
    var wave = D.wave(enemy.id)
    wave.count = 1
    library.waves.append(wave)
    var level = D.level(wave.id)
    level.title = "巡航试炼"
    level.segments[0].duration = 0.1
    level.segments[0].scroll_speed = 0
    level.segments[0].exit_rule.condition = "defeat_all"
    level.segments[0].events[0].spawn_position = Vector2(80, 0)
    library.levels.append(level)
    var game = STGGameDefinition.new()
    game.title = "STGMaker · 首航"
    game.library = library
    game.player = STGPlayerDefinition.new()
    game.world = STGWorldDefinition.new()
    var first = STGWorldLocation.new()
    first.id = "coast"
    first.title = "海岸巡航"
    first.description = "沿海岸进入战斗，击败守卫。\n通关后解锁远处的山谷入口。"
    first.level_id = level.id
    first.map_position = Vector2(0, 0)
    first.reward = 100
    var second = STGWorldLocation.new()
    second.id = "valley"
    second.title = "山谷遭遇战"
    second.description = "继续深入山谷。每次战斗拥有独立的关卡时间轴。"
    second.level_id = level.id
    second.map_position = Vector2(1, -0.5)
    second.requires_completion.assign([first.id])
    second.reward = 150
    game.world.locations.assign([first, second])
    game.start_location_id = first.id
    return game

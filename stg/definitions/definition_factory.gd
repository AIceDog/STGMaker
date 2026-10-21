@tool
extends RefCounted
## 默认值和起步模板的唯一工厂。无 UI 与运行状态；所有新建入口都调用这里。
const CombatSpace = preload("res://stg/definitions/combat_space.gd")

static func curve(values: Array = [Vector2(0, 1), Vector2(1, 1)]) -> Curve:
    var result = Curve.new() # Godot 内置资源：时间曲线
    result.max_value = 10.0
    for point in values:
        result.add_point(point, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
    return result

static func path(points: Array = [Vector2.ZERO, Vector2(50, 350), Vector2(0, 760)]) -> Curve2D:
    var result = Curve2D.new() # Godot 内置资源：空间贝塞尔曲线
    for i in points.size():
        var tangent: Vector2 = (points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]) / 6.0
        result.add_point(points[i], -tangent, tangent)
    return result



static func bullet(form: String = "moving") -> STGBulletDefinition:
    var result = STGBulletDefinition.new()
    result.id = uid("bullet")
    result.form = form
    result.title = {"moving": "新弹丸素材", "laser": "新激光素材", "area": "新区域素材", "trail": "新尾迹素材"}[form]
    result.visual = STGBulletVisual.new()
    result.visual.geometry = STGBulletGeometry.new()
    result.visual.color = Color("55dfbc")
    if form == "laser":
        result.visual.geometry.kind = "rectangle"
        result.visual.geometry.size = Vector2(760, 24)
        result.visual.geometry.offset = Vector2.ZERO
    elif form == "area": result.visual.geometry.size = Vector2(150, 150)
    elif form == "trail":
        result.visual.geometry.kind = "rectangle"
        result.visual.geometry.size = Vector2(1, 24)
    if form != "moving": result.visual.color = Color("ffbc65")
    result.collision = result.visual.geometry.duplicate(true)
    return result

static func behavior_preset(program: STGBehaviorProgramDefinition) -> STGBehaviorPreset:
    var preset=STGBehaviorPreset.new()
    preset.id=uid("behavior_preset");preset.title=program.title;preset.program=program
    preset.default_parameters=program.default_parameters()
    for field in program.fields: preset.exposed_parameters.append(str(field.name))
    return preset

static func flow_node(program: String = "wait", parameters: Dictionary = {}) -> STGFlowNode:
    var result=STGFlowNode.new()
    result.id=uid("node")
    var definition=load("res://stg/behaviors/"+program+".tres") as STGBehaviorProgramDefinition
    if definition!=null:
        result.behavior_preset=behavior_preset(definition)
        result.title=definition.title
        result.program_parameters=parameters.duplicate(true)
        if program=="curve": result.behavior_preset.default_parameters.path=path([Vector2.ZERO,Vector2(-80,50),Vector2(-150,0)])
    return result

static func flow(nodes: Array = []) -> STGBehaviorFlow:
    var result=STGBehaviorFlow.new()
    var entries=nodes if not nodes.is_empty() else [flow_node()]
    for i in entries.size():
        var node:STGFlowNode=entries[i]
        node.editor_position=Vector2(250,50+i*260)
        result.nodes.append(node)
        if i>0: result.nodes[i-1].connections["completed"]=node.id
    result.entry_id=result.nodes[0].id
    return result

static func phase(barrage_id: String = "") -> STGBossPhase:
    var result=STGBossPhase.new()
    result.behavior_flow=flow([flow_node("attack",{"barrage_id":barrage_id,"wait_mode":"emission"})] if not barrage_id.is_empty() else [])
    return result

static func conditional_flow(barrage_id: String = "") -> STGBehaviorFlow:
    var condition=flow_node("condition")
    var dash=flow_node("dash",{"target_mode":"player","target":Vector2.ZERO})
    var distant=flow_node("attack",{"barrage_id":barrage_id}) if not barrage_id.is_empty() else flow_node()
    var wait=flow_node()
    var result=flow([condition,dash,distant,wait])
    condition.connections={"yes":dash.id,"no":distant.id}
    dash.connections={"completed":wait.id};distant.connections={"completed":wait.id}
    return result

static func boss(barrage_id: String = "", conditional: bool = false) -> STGBossDefinition:
    var result = STGBossDefinition.new()
    result.on_death_skill_id = ""
    result.description = ""
    result.id = uid("boss")
    result.start_position = CombatSpace.ENEMY_SPAWN
    result.entity_settings = entity_settings()
    result.phases.append(phase(barrage_id))
    if conditional:
        result.phases[0].behavior_flow = conditional_flow(barrage_id)
    return result

static func uid(prefix: String) -> String:
    return prefix + "_" + Resource.generate_scene_unique_id() # Godot 内置：生成资源 ID

# 关卡配置工厂：仍是唯一默认值入口；运行状态不放进这些 Resource。
static func entity_settings(scroll: bool = false) -> STGEntitySettings:
    var result = STGEntitySettings.new()
    result.movement_policy = "scroll" if scroll else "independent"
    result.exit_boundary = "left" if scroll else "never"
    return result

static func obstacle() -> STGObstacleDefinition:
    var result = STGObstacleDefinition.new()
    result.id = uid("obstacle")
    result.entity_settings = entity_settings(true)
    result.entity_settings.body_radius = 27
    return result

static func level_exit_rule(mode: String = "time_and_condition") -> STGLevelExitRule:
    var result = STGLevelExitRule.new()
    result.mode = mode
    return result

static func wave(enemy_id: String = "", obstacle: bool = false) -> STGWaveDefinition:
    var result = STGWaveDefinition.new()
    result.id = uid("wave")
    result.title = "岩石障碍编队" if obstacle else "敌人纵队"
    result.kind = "obstacle" if obstacle else "enemy"
    result.enemy_id = "" if obstacle else enemy_id
    result.obstacle_id = enemy_id if obstacle else ""
    result.counts_for_clear = not obstacle
    if obstacle:
        result.count = 4
        result.spacing = Vector2(80, 90)
        result.interval = 0.6
    return result

static func level_event(wave_id: String = "", at: float = 0) -> STGLevelEvent:
    var result = STGLevelEvent.new()
    result.id = uid("event")
    result.wave_id = wave_id
    result.at = at
    return result

static func level_segment(wave_id: String = "") -> STGLevelSegment:
    var result = STGLevelSegment.new()
    result.id = uid("segment")
    result.exit_rule = level_exit_rule()
    if not wave_id.is_empty():
        result.events.append(level_event(wave_id))
    return result

static func background_layer(ratio: float = 0.25) -> STGBackgroundLayer:
    var result = STGBackgroundLayer.new()
    result.title = "远景" if ratio < 0.5 else "近景"
    result.scroll_ratio = ratio
    return result

static func level(wave_id: String = "") -> STGLevelDefinition:
    var result = STGLevelDefinition.new()
    result.id = uid("level")
    result.player_spawn = CombatSpace.PLAYER_SPAWN
    result.background_layers.assign([background_layer(0.2), background_layer(0.7)])
    result.segments.append(level_segment(wave_id))
    return result

static func wave_preview(wave_id: String, wave: STGWaveDefinition = null) -> STGLevelDefinition:
    var result = level(wave_id)
    # 预览覆盖完整生成过程；持续战斗的敌人仍需击败 / 离场后才能清场。
    result.segments[0].duration = maxf(8, (wave.count - 1) * wave.interval + 2) if wave != null else 8
    return result

static func obstacle_preview(wave_id: String) -> STGLevelDefinition:
    var result = level(wave_id)
    result.segments[0].duration = 12
    result.segments[0].exit_rule = level_exit_rule("time")
    return result


static func extension_binding(definition: STGExtensionDefinition = null) -> STGExtensionBinding:
    var result = STGExtensionBinding.new()
    result.definition = definition
    result.parameters = definition.default_parameters() if definition != null else {}
    return result

static func barrage(reference_id: String = "", algorithm: String = "straight") -> STGBarrageSkill:
 var preset=STGAttackPreset.new()
 preset.program=load("res://stg/programs/"+algorithm+".tres")
 preset.id=uid("preset");preset.title=preset.program.title;preset.reference_id=reference_id
 preset.default_parameters=preset.program.default_parameters()
 for field in preset.program.fields:preset.exposed_parameters.append(str(field.name))
 var skill=STGBarrageSkill.new();skill.id=uid("attack");skill.title=preset.title;skill.attack_preset=preset
 return skill

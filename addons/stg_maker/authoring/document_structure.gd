@tool
extends RefCounted
## 未完成文档可以保存。缺失容器先显示明确修复操作，避免编辑表单访问空节点。
const D = preload("res://stg/definitions/definition_factory.gd")

static func issue(item: Resource) -> String:
    if item is STGBulletDefinition:
        if item.visual == null or item.visual.geometry == null or item.collision == null: return "外观或碰撞配置缺失"
    elif item is STGBarrageSkill:
        if item.attack_preset==null or item.attack_preset.program==null:return "招式程序缺失"
    elif item is STGBehaviorFlow:
        if item.nodes.is_empty() or item.nodes.has(null): return "行为节点缺失"
    elif item is STGBossDefinition:
        if item.entity_settings == null or item.phases.is_empty(): return "敌人阶段或实体设置缺失"
        for phase in item.phases:
            if phase == null or phase.behavior_flow == null: return "敌人阶段或行为流程缺失"
            for node in phase.behavior_flow.nodes:
                if node == null: return "行为节点缺失"
                if node.behavior_preset == null or node.behavior_preset.program == null: return "行为程序声明缺失"
    elif item is STGLevelDefinition:
        if item.segments.is_empty() or item.background_layers.has(null): return "关卡阶段或背景层缺失"
        for segment in item.segments:
            if segment == null or segment.exit_rule == null or segment.events.has(null): return "关卡阶段、推进条件或出场事件缺失"
    elif item is STGObstacleDefinition and item.entity_settings == null: return "实体设置缺失"
    return ""

static func repair(item: Resource, project: STGProject) -> void:
    var bullet_id = _first_id(project.bullets)
    var skill_id = _first_id(project.barrages)
    if item is STGBulletDefinition:
        if item.visual == null: item.visual = STGBulletVisual.new()
        if item.visual.geometry == null: item.visual.geometry = STGBulletGeometry.new()
        if item.collision == null: item.collision = STGBulletGeometry.new()
    elif item is STGBarrageSkill:
        if item.attack_preset==null:item.attack_preset=D.barrage().attack_preset
    elif item is STGBehaviorFlow:
        if item.nodes.is_empty(): item.nodes.append(D.flow_node())
        for i in item.nodes.size():
            if item.nodes[i] == null: item.nodes[i] = D.flow_node()
        if item.find(item.entry_id) == null: item.entry_id = item.nodes[0].id
    elif item is STGBossDefinition:
        if item.entity_settings == null: item.entity_settings = D.entity_settings()
        if item.phases.is_empty(): item.phases.append(D.phase(skill_id))
        for i in item.phases.size():
            if item.phases[i] == null: item.phases[i] = D.phase(skill_id)
            var phase = item.phases[i]
            if phase.behavior_flow == null: phase.behavior_flow = D.flow()
            for j in phase.behavior_flow.nodes.size():
                var node = phase.behavior_flow.nodes[j]
                if node == null:
                    phase.behavior_flow.nodes[j] = D.flow_node()
                    node = phase.behavior_flow.nodes[j]
                if node.behavior_preset==null:node.behavior_preset=D.flow_node().behavior_preset
    elif item is STGLevelDefinition:
        if item.segments.is_empty(): item.segments.append(D.level_segment())
        for i in item.segments.size():
            if item.segments[i] == null: item.segments[i] = D.level_segment()
            var segment = item.segments[i]
            if segment.exit_rule == null: segment.exit_rule = D.level_exit_rule("time")
            for j in segment.events.size():
                if segment.events[j] == null: segment.events[j] = D.level_event()
        for i in item.background_layers.size():
            if item.background_layers[i] == null: item.background_layers[i] = D.background_layer()
    elif item is STGObstacleDefinition and item.entity_settings == null: item.entity_settings = D.entity_settings(true)

static func _first_id(items: Array) -> String:
    for item in items:
        if item != null: return item.id
    return ""

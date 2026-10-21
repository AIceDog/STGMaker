@tool
extends RefCounted
## 通用声明校验；与编辑、运行、构建共享预设及引用模型，不维护节点类型表。
const Locations=preload("res://stg/definitions/validation_locations.gd")
const Timing=preload("res://stg/definitions/behavior_timing.gd")
const Scenes=preload("res://stg/definitions/scene_contract.gd")
static func check(flow:STGBehaviorFlow,project,issues:PackedStringArray,title:String,locations:Variant=null,boss_id:String="",phase_index:int=0,parents:Array=[],scope:Array=[]) -> void:
    if flow==null or flow.nodes.is_empty():issues.append(title+"：需要行为流程");return
    if flow in parents or parents.size()>=32:issues.append(title+"：内嵌流程循环或超过32层");return
    if flow.nodes.size()>128:issues.append(title+"：流程最多128个节点")
    var ids={}
    var flow_scope=scope if not parents.is_empty() or phase_index<0 else ["phases",phase_index,"behavior_flow"]
    for i in flow.nodes.size():
        var node=flow.nodes[i]
        var start=issues.size()
        if node==null:issues.append(title+"：空节点");continue
        if node.id.is_empty() or ids.has(node.id) or STGFlowNode.is_terminal(node.id):issues.append(title+"：节点 ID 无效或重复")
        ids[node.id]=true
        if not node.editor_position.is_finite():issues.append(title+"：图坐标无效")
        if node.behavior_preset==null:issues.append(node.title+"：缺少行为程序声明")
        else:
            var node_issues=node.behavior_preset.validate(node.program_parameters)
            issues.append_array(node_issues)
            var program=node.behavior_preset.program
            if program!=null and node_issues.is_empty():
                var required=Timing.required_execution(node,flow,project)
                if not is_finite(required):issues.append(node.title+"：子行为预算无法计算，请检查缺失引用或循环")
                elif float(node.parameters().execution_duration)+Timing.EPSILON<required:
                    issues.append(node.title+"：执行预算不足，至少需要 %.6f 秒"%required)
                var ports=node.ports().map(func(port):return port.id)
                for key in node.connections:
                    if key not in ports:issues.append(node.title+"：存在未声明端口连线："+str(key))
                if program.branch_mode=="children" and node.children.is_empty():issues.append(node.title+"：至少需要一个分支")
                if program.branch_mode=="none" and not node.children.is_empty():issues.append(node.title+"：声明不接受内嵌分支")
                if program.branch_mode=="children":
                    var owner:int=node.parameters().get("animation_branch",-1)
                    if owner>=node.children.size():issues.append(node.title+"：动画控制分支不存在")
                    if owner<0:
                        var count=0
                        for branch in node.children:
                            if has_animation(branch,project,{}):count+=1
                        if count>1:issues.append(node.title+"：多个分支配置动画，请指定动画控制分支")
        for target in node.outputs():
            if not STGFlowNode.is_terminal(target) and flow.find(target)==null:issues.append(node.title+"：连接目标不存在")
        for j in node.children.size():
            var child=node.children[j]
            if not child is STGBehaviorFlow:issues.append(node.title+"：分支必须是行为流程")
            else:check(child,project,issues,title+" / "+node.title,locations,boss_id,phase_index,parents+[flow],flow_scope+["nodes",i,"children",j])
        Locations.mark(issues,start,locations,"behaviors" if phase_index<0 else "bosses",boss_id,flow_scope+["nodes",i])
    if flow.find(flow.entry_id)==null:issues.append(title+"：开始节点不存在");return
    if not flow.loop_entry_id.is_empty() and flow.find(flow.loop_entry_id)==null:issues.append(title+"：循环起点不存在")
    var visited={}
    _walk(flow,flow.entry_id,[],visited,issues,title)
    if visited.size()!=ids.size():issues.append(title+"：存在未接入流程的节点")
static func _walk(flow,id:String,parents:Array,visited:Dictionary,issues:PackedStringArray,title:String) -> void:
    if STGFlowNode.is_terminal(id):return
    if id in parents:issues.append(title+"：连接形成循环，请使用阶段循环");return
    if visited.has(id):return
    var node=flow.find(id)
    if node==null:return
    visited[id]=true
    for target in node.outputs():_walk(flow,target,parents+[id],visited,issues,title)
static func has_animation(flow:Resource,project,visited:Dictionary) -> bool:
    if not flow is STGBehaviorFlow or visited.has(flow.get_instance_id()):return false
    visited[flow.get_instance_id()]=true
    for node in flow.nodes:
        if node==null:continue
        var p=node.parameters()
        for key in ["windup_animation","active_animation","recovery_animation"]:
            if not str(p.get(key,"")).is_empty():return true
        for child in node.children:
            if has_animation(child,project,visited):return true
        if node.behavior_preset!=null and node.behavior_preset.program!=null:
            for reference in node.behavior_preset.program.references(p):
                if reference.collection=="behaviors" and has_animation(project.find("behaviors",reference.id),project,visited):return true
    return false
static func check_presentation(boss:STGBossDefinition,project,issues:PackedStringArray) -> void:
    var visual:Node
    var player:AnimationPlayer
    if boss.visual_scene!=null:
        visual=boss.visual_scene.instantiate()
        if not visual is Node2D:issues.append(boss.title+"：表现场景根节点必须是 Node2D")
        player=Scenes.find_player(visual)
    for phase in boss.phases:
        if phase!=null:
            _animations(phase.behavior_flow,player,issues,{},project)
            _animations(project.find("behaviors",phase.entry_behavior_id),player,issues,{},project)
    _animations(project.find("behaviors",boss.on_death_behavior_id),player,issues,{},project)
    if visual!=null:visual.free()
static func _animations(flow,player:AnimationPlayer,issues:PackedStringArray,visited:Dictionary,project) -> void:
    if flow==null or visited.has(flow.get_instance_id()):return
    visited[flow.get_instance_id()]=true
    for node in flow.nodes:
        if node==null:continue
        var p=node.parameters()
        for key in ["windup_animation","active_animation","recovery_animation"]:
            var name=str(p.get(key,""))
            if name.is_empty():continue
            if player==null or not player.has_animation(name):issues.append(node.title+"：动画不存在："+name)
            elif not is_finite(player.get_animation(name).length) or player.get_animation(name).length<=0:issues.append(node.title+"：动画长度必须大于零")
        for child in node.children:_animations(child,player,issues,visited,project)
        if node.behavior_preset!=null and node.behavior_preset.program!=null:
            for reference in node.behavior_preset.program.references(p):
                if reference.collection=="behaviors":_animations(project.find("behaviors",reference.id),player,issues,visited,project)

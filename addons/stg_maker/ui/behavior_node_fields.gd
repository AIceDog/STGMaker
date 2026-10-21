@tool
extends RefCounted
const F=preload("res://addons/stg_maker/ui/fields.gd")
const R=preload("res://addons/stg_maker/ui/resource_fields.gd")
const Fields=preload("res://addons/stg_maker/ui/attack_parameter_fields.gd")
const Catalog=preload("res://addons/stg_maker/authoring/behavior_programs.gd")
const D=preload("res://stg/definitions/definition_factory.gd")
const Stages=preload("res://addons/stg_maker/ui/behavior_stage_fields.gd")
const Timing=preload("res://stg/definitions/behavior_timing.gd")
const Copy=preload("res://stg/definitions/config_copy.gd")
static func build(host,parent) -> void:
    if not host.flow_path.is_empty():F.button(parent,"← 返回上级流程",host.leave_flow_branch,"link")
    var node=host.boss_node()
    if node==null:F.note(parent,"在流程图中选择节点。");return
    var scope=host.boss_node_scope()
    if host.inspector_tab==0:
        F.text(parent,"节点名称",node.title,R.setter(host,scope,"title"))
        var sources=[];var ids=[];var labels=[]
        for program in Catalog.definitions():
            sources.append(D.behavior_preset(program));ids.append(program.id);labels.append(program.title)
        for preset in host.session.project.behavior_presets:
            sources.append(preset);ids.append(preset.id);labels.append("预设 · "+preset.title)
        var selected=node.behavior_preset.id if node.behavior_preset!=null else ""
        if selected not in ids and node.behavior_preset!=null and node.behavior_preset.program!=null:selected=node.behavior_preset.program.id
        F.select(parent,"节点类型 / 预设",selected,ids,labels,func(id):
            var preset:STGBehaviorPreset=Copy.copy(sources[ids.find(id)])
            R.edit(host,scope,func(target,_project):
                target.behavior_preset=preset;target.program_parameters.clear();target.connections.clear()
                if preset.program.branch_mode!="children":target.children.clear()))
        F.button(parent,"保存为行为节点预设…",func():
            if node.behavior_preset==null:return
            var preset:STGBehaviorPreset=Copy.copy(node.behavior_preset)
            preset.id=D.uid("behavior_preset");preset.title=node.title;preset.default_parameters=node.parameters()
            host.session.edit(func(project):project.behavior_presets.append(preset))
            open_presets(host,preset.id))
        F.button(parent,"管理行为节点预设…",func():open_presets(host))
    if node.behavior_preset==null or node.behavior_preset.program==null:F.note(parent,"请选择符合契约的行为程序。");return
    var declaration_issues=node.behavior_preset.program.validate_fields()
    if not declaration_issues.is_empty():F.note(parent,"声明需修正："+"；".join(declaration_issues));return
    var parameters=node.parameters();var groups={}
    if host.inspector_tab==1:
        var required=Timing.required_execution(node,host.boss_flow(),host.session.project)
        var total=F.note(parent,"节点总时长 %.3f s"%Timing.node_duration(node))
        total.set_meta("refresh_text",func():return "节点总时长 %.3f s"%Timing.node_duration(host.boss_node()))
        if is_finite(required):
            var budget=F.note(parent,"子行为所需最短执行时长 %.6f s"%required)
            budget.set_meta("refresh_text",func():return "子行为所需最短执行时长 %.6f s"%Timing.required_execution(host.boss_node(),host.boss_flow(),host.session.project))
            var use=F.button(parent,"使用所需时长",func():
                var needed=Timing.required_execution(host.boss_node(),host.boss_flow(),host.session.project)
                if is_finite(needed):host.edit_configuration(scope,func(target,_project):target.program_parameters.execution_duration=needed,false,"execution_duration"))
            use.set_meta("refresh_disabled",func():return float(host.boss_node().parameters().execution_duration)+Timing.EPSILON>=Timing.required_execution(host.boss_node(),host.boss_flow(),host.session.project))
            use.disabled=float(parameters.execution_duration)+Timing.EPSILON>=required
        else:F.note(parent,"子行为预算无法计算，请先修正引用与连线。")
        Stages.summary(parent,parameters,Stages.scene_for(host),func():return host.boss_node().parameters())
        F.button(parent,"预览动画 / 试听",func():Stages.preview(host,node.parameters()))
    for field in node.behavior_preset.editable_fields():
        var timing=field.get("group","")=="时序与动画"
        if timing!=(host.inspector_tab==1):continue
        var group=str(field.get("group","节点参数"))
        if not groups.has(group):groups[group]=F.group(parent,group)
        var key=str(field.name)
        var callback=func(value):host.edit_configuration(scope,func(target,_project):target.program_parameters[key]=value,false,key)
        var control=Stages.add(groups[group],field,parameters.get(key),callback,host.session.project,Stages.scene_for(host))
        if control!=null:control.set_meta("config_scope",scope+["program_parameters"]);control.set_meta("config_field",key)
        if field.type=="resource" and field.get("resource_class")=="Curve2D" and parameters.get(key)==null:
            F.button(groups[group],"创建默认曲线路径",func():callback.call(D.path([Vector2.ZERO,Vector2(-80,50),Vector2(-150,0)])))
    if host.inspector_tab==0 and node.behavior_preset.program.branch_mode=="children":
        for index in node.children.size():
            var row=HFlowContainer.new();parent.add_child(row)
            F.button(row,"编辑分支 %d →"%(index+1),func():host.enter_flow_branch(index))
            F.button(row,"删除分支",func():R.edit(host,scope,func(target,_project):target.children.remove_at(index)),"danger")
        F.button(parent,"＋ 并行分支",func():R.edit(host,scope,func(target,_project):target.children.append(D.flow())))
static func open_presets(host,id:String="") -> void:
    var editor=load("res://addons/stg_maker/ui/behavior_preset_editor.gd").new()
    host.add_child(editor);editor.open_for(host,id)

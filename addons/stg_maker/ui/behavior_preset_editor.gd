@tool
extends Window
## 行为预设制作窗口；声明驱动参数，所有修改进入同一 Session 撤销与保存。
const F=preload("res://addons/stg_maker/ui/fields.gd")
const Fields=preload("res://addons/stg_maker/ui/attack_parameter_fields.gd")
const Stages=preload("res://addons/stg_maker/ui/behavior_stage_fields.gd")
const Catalog=preload("res://addons/stg_maker/authoring/behavior_programs.gd")
const D=preload("res://stg/definitions/definition_factory.gd")
var host
var selected:String=""
var body:VBoxContainer
func current():return host.session.project.find("behavior_presets",selected)
func open_for(workspace,id:String="") -> void:
    host=workspace;selected=id;title="行为节点预设制作";theme=host.theme
    size=Vector2i(1000,760);min_size=Vector2i(720,520)
    var scroll=ScrollContainer.new();scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(scroll)
    body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
    close_requested.connect(func():_commit();queue_free())
    _build();popup_centered_clamped(size,.85)
func _commit() -> void:
    var focus=gui_get_focus_owner()
    if focus!=null:focus.release_focus()
func _edit(change:Callable,rebuild:bool=false) -> void:
    var id=selected
    host.session.edit_asset("behavior_presets",id,func(project):change.call(project.find("behavior_presets",id)),{"structure":false,"collection":"behavior_presets","id":id})
    if rebuild:_build.call_deferred()
    else:
        for label in body.find_children("*","Label",true,false):
            if label.has_meta("refresh_text"):label.text=label.get_meta("refresh_text").call()
func _build() -> void:
    F.close_popups(body)
    for child in body.get_children():body.remove_child(child);child.queue_free()
    var toolbar=HFlowContainer.new();body.add_child(toolbar)
    F.button(toolbar,"＋ 新建预设",func():
        _commit()
        var preset=D.behavior_preset(Catalog.definitions()[0]);selected=preset.id
        host.session.edit(func(project):project.behavior_presets.append(preset));_build())
    F.button(toolbar,"撤销",func():_commit();host.session.undo();_build())
    F.button(toolbar,"重做",func():_commit();host.session.redo();_build())
    F.button(toolbar,"保存项目",func():_commit();host.save_project())
    F.button(toolbar,"关闭",func():_commit();queue_free())
    var presets=host.session.project.behavior_presets
    if current()==null and not presets.is_empty():selected=presets[0].id
    if presets.is_empty():F.note(body,"新建一个行为预设，再选择程序与开放参数。");return
    F.select(body,"当前预设",selected,presets.map(func(p):return p.id),presets.map(func(p):return p.title),func(id):_commit();selected=id;_build())
    var preset=current()
    F.text(body,"预设名称",preset.title,func(value):_edit(func(p):p.title=value))
    var programs=Catalog.definitions()
    F.select(body,"行为程序",preset.program.id if preset.program!=null else "",programs.map(func(p):return p.id),programs.map(func(p):return p.title),func(id):
        var program=programs.filter(func(p):return p.id==id)[0]
        _edit(func(p):
            p.program=program;p.default_parameters=program.default_parameters();p.parameter_options.clear();p.exposed_parameters.clear()
            for field in program.fields:p.exposed_parameters.append(str(field.name)),true))
    if preset.program==null:return
    var declaration_issues=preset.program.validate_fields()
    if not declaration_issues.is_empty():F.note(body,"声明需修正："+"；".join(declaration_issues));return
    Stages.summary(body,preset.parameters(),Stages.scene_for(host),func():return current().parameters())
    F.button(body,"预览动画 / 试听",func():Stages.preview(host,preset.parameters()))
    for field in preset.program.fields:
        var key=str(field.name)
        var group=F.group(body,str(field.get("label",key)))
        if field.get("group","")!="时序与动画":
            F.toggle(group,"允许节点编辑",key in preset.exposed_parameters,func(enabled):_edit(func(p):
                if enabled and key not in p.exposed_parameters:p.exposed_parameters.append(key)
                elif not enabled:p.exposed_parameters.erase(key)))
        Stages.add(group,field,preset.parameters().get(key),func(value):_edit(func(p):p.default_parameters[key]=value),host.session.project,Stages.scene_for(host))
        var options=preset.parameter_options.get(key,{})
        if not options is Dictionary:options={}
        F.text(group,"显示名称",str(options.get("label",field.get("label",key))),func(value):_option(key,"label",value))
        F.text(group,"说明",str(options.get("help",field.get("help",""))),func(value):_option(key,"help",value))
        if field.type in ["float","int"]:
            for bound in ["min","max"]:
                F.number(group,"最小值" if bound=="min" else "最大值",float(options.get(bound,field.get(bound,0))),func(value):_option(key,bound,value),float(field.get("min",-100000)),float(field.get("max",100000)),float(field.get("step",.1)))
    F.button(body,"删除此预设",func():
        var id=selected
        host.session.edit(func(project):project.behavior_presets=project.behavior_presets.filter(func(p):return p.id!=id));selected="";_build(),"danger")
func _option(key:String,name:String,value) -> void:
    _edit(func(p):
        if not p.parameter_options.has(key):p.parameter_options[key]={}
        p.parameter_options[key][name]=value)

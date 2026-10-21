@tool
extends RefCounted
const F=preload("res://addons/stg_maker/ui/fields.gd")
const Fields=preload("res://addons/stg_maker/ui/attack_parameter_fields.gd")
const Scenes=preload("res://stg/definitions/scene_contract.gd")
const Timing=preload("res://stg/definitions/behavior_timing.gd")
static func scene_for(host) -> PackedScene:
    var boss=host.session.project.find("bosses",host.selected_id) if host.collection=="bosses" else null
    return boss.visual_scene if boss!=null else null
static func clips(scene:PackedScene) -> Dictionary:
    var result={}
    if scene==null:return result
    var visual=scene.instantiate();var player=Scenes.find_player(visual)
    if player!=null:
        for name in player.get_animation_list():result[str(name)]=player.get_animation(name).length
    visual.free();return result
static func stage_summary(p:Dictionary,stage:String,lengths:Dictionary) -> String:
    var name=str(p.get(stage+"_animation",""))
    var duration=float(p.execution_duration if stage=="active" else p[stage])
    var plan=Timing.animation_plan(float(lengths.get(name,0)),duration,stage,str(p.active_animation_mode),int(p.active_cycles))
    var label={"windup":"前摇","active":"执行中","recovery":"后摇"}[stage]
    return "%s：%.3f s · %d 次 · 动画 / 音频 %.4f×%s"%[label,duration,plan.cycles,plan.rate," · 保持末帧" if plan.hold else ""]
static func summary(parent,p:Dictionary,scene:PackedScene,getter:Callable=Callable()) -> void:
    var lengths=clips(scene)
    for stage in ["windup","active","recovery"]:
        var caption=F.note(parent,stage_summary(p,stage,lengths))
        caption.set_meta("behavior_stage",stage)
        if getter.is_valid():caption.set_meta("refresh_text",func():return stage_summary(getter.call(),stage,lengths))
static func add(parent,field:Dictionary,value,callback:Callable,project,scene:PackedScene):
    if field.get("presentation","")=="enemy_animation" and scene!=null:
        var names=Array(clips(scene).keys());names.sort();names.push_front("")
        if str(value) not in names:names.append(str(value))
        var labels=names.map(func(name):return "无动画" if name.is_empty() else name)
        var control=F.select(parent,str(field.label),str(value),names,labels,callback)
        control.set_meta("program_parameter",str(field.name));return control
    return Fields.add(parent,field,value,callback,project)
static func preview(host,p:Dictionary) -> void:
    var window=load("res://addons/stg_maker/ui/behavior_stage_preview.gd").new()
    host.add_child(window);window.open_for(host,p,scene_for(host))

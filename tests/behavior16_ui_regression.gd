@tool
extends RefCounted
const D=preload("res://stg/definitions/definition_factory.gd")
const Stages=preload("res://addons/stg_maker/ui/behavior_stage_fields.gd")
static func frames(studio,count:int=3):
    for i in count:await studio.get_tree().process_frame
static func parameter(studio,key:String):
    for control in studio.inspector.find_children("*","Control",true,false):
        if control.get_meta("program_parameter","")==key:return control
    return null
static func run(studio,check:Callable,prefix:String):
    var was_processing=studio.is_processing();studio.set_process(false)
    var p=preload("res://tests/unified14_fixture.gd").project()
    p.bosses[0].visual_scene=preload("res://tests/behavior_visual_fixture.gd").animated_scene()
    var stream=AudioStreamWAV.new();stream.mix_rate=8000
    var data=PackedByteArray();data.resize(16000);stream.data=data
    var node=D.flow_node("wait",{"execution_duration":3.5,"windup":.2,"recovery":.2,"active_animation":"active","windup_animation":"windup","recovery_animation":"recovery","active_sound":stream,"active_sound_loop":true})
    p.bosses[0].phases[0].behavior_flow=D.flow([node]);p.bosses[0].phases[0].loop=false
    studio.session.project=p;studio.show_collection("bosses","enemy");studio.flow_node_id=node.id;studio.inspector_tab=1;studio.refresh(true);await frames(studio)
    check.call(parameter(studio,"execution_duration") is SpinBox and parameter(studio,"active_sound")!=null,prefix+"统一时长和三段音频属性可编辑")
    check.call(parameter(studio,"active_animation") is OptionButton,prefix+"动画从敌人表现场景选择")
    var duration=parameter(studio,"execution_duration");duration.value=7.0;await frames(studio)
    check.call(is_equal_approx(studio.boss_node().parameters().execution_duration,7),prefix+"执行时长生效")
    studio.undo_edit();await frames(studio)
    check.call(is_equal_approx(studio.boss_node().parameters().execution_duration,3.5),prefix+"公共时长撤销")
    studio.redo_edit();await frames(studio)
    check.call(is_equal_approx(studio.boss_node().parameters().execution_duration,7),prefix+"公共时长重做")
    var cycles=parameter(studio,"active_cycles");cycles.value=2;await frames(studio)
    check.call(parameter(studio,"active_animation_mode").selected>=0,prefix+"覆盖值编辑后预设默认选项仍可见")
    var labels=studio.inspector.find_children("*","Label",true,false)
    check.call(labels.any(func(label):return label.get_meta("behavior_stage","")=="active" and label.text.contains("0.2857")),prefix+"倍率随编辑实时更新")
    Stages.preview(studio,studio.boss_node().parameters());await frames(studio)
    var preview
    for child in studio.get_children():
        if child is Window and child.get_script()!=null and child.get_script().resource_path.ends_with("behavior_stage_preview.gd"):preview=child
    check.call(preview!=null and preview.visible,prefix+"三段预览试听窗口真实打开")
    if preview!=null:
        preview.set_process(false);preview.restart();preview.advance(.2)
        check.call(preview.phase_index==1 and preview.voice!=null and is_equal_approx(preview.voice.audio.pitch_scale,2.0/7),prefix+"试听复用动画倍率")
        var elapsed=preview.elapsed;preview.playing=false;preview._clock();preview._process(.1)
        check.call(preview.elapsed==elapsed and preview.voice.audio.stream_paused,prefix+"预览暂停同时停止时钟和声音")
        preview.rate=2;preview.playing=true;preview._clock()
        check.call(is_equal_approx(preview.voice.audio.pitch_scale,4.0/7),prefix+"试听叠加全局倍速")
        var folder="res://tests/.test_run_logs/behavior16";DirAccess.make_dir_recursive_absolute(folder)
        await frames(studio,3);RenderingServer.force_draw(false)
        studio.get_tree().root.get_texture().get_image().save_png(folder+"/"+prefix+"_preview.png")
        preview.close_requested.emit();await frames(studio)
        check.call(not is_instance_valid(preview),prefix+"关闭试听窗口统一回收")
    var parallel=D.flow_node("parallel",{"execution_duration":.01})
    parallel.children.append(D.flow([D.flow_node("wait",{"windup":.1,"execution_duration":.2,"recovery":.3})]))
    studio.session.edit(func(project):project.bosses[0].phases[0].behavior_flow=D.flow([parallel]))
    studio.flow_node_id=parallel.id;studio.inspector_tab=1;studio.refresh(true);await frames(studio)
    var buttons=studio.inspector.find_children("*","Button",true,false)
    var found=buttons.filter(func(button):return button.text=="使用所需时长")
    check.call(found.size()==1 and not found[0].disabled,prefix+"预算不足显示修正操作")
    if found.size()==1:found[0].pressed.emit();await frames(studio)
    check.call(is_equal_approx(studio.boss_node().parameters().execution_duration,.6) and studio.session.project.validate().is_empty(),prefix+"使用所需时长通过校验")
    studio.undo_edit();await frames(studio)
    check.call(is_equal_approx(studio.boss_node().parameters().execution_duration,.01),prefix+"预算修正可撤销")
    studio.redo_edit();await frames(studio)
    var path="user://behavior16_ui_"+prefix+"_%d/library.tres"%Time.get_ticks_usec()
    var store=preload("res://addons/stg_maker/authoring/asset_store.gd")
    check.call(store.save_library(studio.session.project,path).is_empty(),prefix+"新参数事务保存")
    var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
    check.call(reopened!=null and reopened.schema_version==16 and reopened.validate().is_empty(),prefix+"格式16保存重开")
    RenderingServer.force_draw(false);studio.get_tree().root.get_texture().get_image().save_png("res://tests/.test_run_logs/behavior16/"+prefix+"_timing.png")
    studio.session.recoverable_changes=false;studio.set_process(was_processing)

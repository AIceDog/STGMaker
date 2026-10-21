extends SceneTree
const D=preload("res://stg/definitions/definition_factory.gd")
const Commands=preload("res://addons/stg_maker/ui/flow_commands.gd")
const Nodes=preload("res://addons/stg_maker/ui/behavior_node_fields.gd")
var checks=0
var failures=0
var studio
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
    checks+=1
    if not ok:failures+=1;push_error(message)
func frames(count=3):
    for i in count:await process_frame
func run():
    root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
    studio=load("res://addons/stg_maker/studio.tscn").instantiate()
    studio.restore_last_project=false;studio.settings_path="user://behavior15_ui.cfg"
    root.add_child(studio);await frames()
    studio.session.project=preload("res://tests/unified14_fixture.gd").project()
    studio.show_collection("bosses","enemy");await frames()
    check(studio.flow_editor.is_visible_in_tree(),"行为图真实渲染")
    for name in ["wait","condition","random","attack","call","parallel","dash","teleport","orbit"]:
        Commands.add(studio,name);await frames(2)
        check(studio.boss_node().behavior_preset.program.id=="behavior."+name,"声明驱动插入："+name)
        studio.inspector_tab=1;studio.refresh(true);await frames(2)
        var controls=studio.inspector.find_children("*","Control",true,false)
        check(controls.any(func(control):return control.get_meta("program_parameter","")=="windup") and controls.any(func(control):return control.get_meta("program_parameter","")=="recovery"),"所有节点均可编辑前后摇："+name)
    studio.inspector_tab=0;studio.refresh(true);await frames()
    var selected=studio.boss_node()
    var failure_port=selected.ports().map(func(port):return port.id).find("failure")
    studio.flow_editor.graph.connection_request.emit(selected.id,failure_port,"failure_end",0);await frames()
    check(studio.boss_node().target("failure")==STGFlowNode.FAILURE,"失败返回端点可通过真实连线编辑")
    studio.undo_edit();await frames()
    Commands.duplicate_node(studio);await frames();var count=studio.boss_flow().nodes.size()
    studio.undo_edit();await frames();check(studio.boss_flow().nodes.size()==count-1,"新模型复制可撤销")
    studio.redo_edit();await frames();check(studio.boss_flow().nodes.size()==count,"新模型复制可重做")
    var preset=D.behavior_preset(load("res://stg/behaviors/dash.tres"));preset.id="ui_preset";preset.title="可编辑冲刺"
    studio.session.edit(func(project):project.behavior_presets.append(preset));await frames()
    Nodes.open_presets(studio,preset.id);await frames()
    var editor
    for child in studio.get_children():
        if child is Window and child.get_script()!=null and child.get_script().resource_path.ends_with("behavior_preset_editor.gd"):editor=child
    check(editor!=null and editor.visible,"行为节点预设窗口可打开并渲染")
    if editor!=null:
        editor._edit(func(p):p.default_parameters.windup=.12)
        check(is_equal_approx(studio.session.project.behavior_presets[0].default_parameters.windup,.12),"预设默认参数进入事务")
        editor._edit(func(p):p.exposed_parameters.erase("speed"))
        check("speed" not in studio.session.project.behavior_presets[0].exposed_parameters,"预设可选择开放字段")
        editor._option("execution_duration","max",2.0)
        check(studio.session.project.behavior_presets[0].parameter_options.execution_duration.max==2.0,"预设范围可收紧")
        var folder="res://tests/.test_run_logs/behavior15";DirAccess.make_dir_recursive_absolute(folder)
        RenderingServer.force_draw(false);root.get_texture().get_image().save_png(folder+"/presets.png")
        editor.queue_free();await frames()
    studio.inspector_tab=1;studio.refresh(true);await frames()
    RenderingServer.force_draw(false);root.get_texture().get_image().save_png("res://tests/.test_run_logs/behavior15/timing.png")
    studio.inspector_tab=0;studio.refresh(true);await frames()
    RenderingServer.force_draw(false);root.get_texture().get_image().save_png("res://tests/.test_run_logs/behavior15/flow.png")
    await preload("res://tests/behavior16_ui_regression.gd").run(studio,check,"standalone")
    studio.session.recoverable_changes=false;studio.queue_free();await frames(4)
    print("UNIFIED15 BEHAVIOR UI RESULT: %d checks, %d failures"%[checks,failures])
    quit(1 if failures else 0)

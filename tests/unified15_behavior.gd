extends SceneTree
const D=preload("res://stg/definitions/definition_factory.gd")
const Fixture=preload("res://tests/unified14_fixture.gd")
const Catalog=preload("res://addons/stg_maker/authoring/behavior_programs.gd")
const Assets=preload("res://addons/stg_maker/authoring/asset_store.gd")
const References=preload("res://stg/definitions/resource_references.gd")
const Copy=preload("res://stg/definitions/config_copy.gd")
const Compiler=preload("res://addons/stg_maker/build/compiler.gd")
var checks=0
var failures=0
var probe_path:String
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
    checks+=1
    if not ok:failures+=1;push_error(message)
func advance(world,seconds:float):
    for i in ceili(seconds/STGSimulation.STEP):world.step()
func make_world(nodes:Array,project:STGProject=null):
    var p=project if project!=null else Fixture.project()
    p.bosses[0].phases[0].behavior_flow=D.flow(nodes)
    p.bosses[0].phases[0].loop=false
    p.bosses[0].start_position=Vector2.ZERO
    var world=STGSimulation.new();root.add_child(world);world.presentation_enabled=false
    world.reset(p,"bosses",p.bosses[0].id)
    return world
func run():
    check(STGProject.VERSION==16 and STGProject.create().behavior_presets.is_empty(),"格式16与空白新建库")
    var definitions=Catalog.definitions()
    check(definitions.size()==13,"13种行为声明统一注册")
    for program in definitions:
        var values=program.default_parameters()
        if values.get("mode")=="curve":values.path=D.path([Vector2.ZERO,Vector2(20,0)])
        check(program.validate(values,"behavior").is_empty(),"所有声明遵守同一入口："+program.id)
        check(program.implementation.resource_path.begins_with("res://stg/behaviors/"),"实现目录："+program.id)
    var missing=STGFlowNode.new();missing.id="missing"
    var invalid=Fixture.project();invalid.bosses[0].phases[0].behavior_flow=D.flow([missing])
    check(not invalid.validate().is_empty(),"缺少声明的节点不能运行")
    var naked=D.flow_node();naked.behavior_preset.program=STGBehaviorProgramDefinition.new()
    check(not naked.behavior_preset.validate().is_empty(),"没有实现的声明被拒绝")
    var wait=D.flow_node("wait",{"execution_duration":.2,"windup":.1,"recovery":.15})
    var world=make_world([wait]);advance(world,.09)
    check(world.boss_player.runner.node_run.stage=="windup","前摇期间未启动程序")
    advance(world,.12);check(world.boss_player.runner.node_run.stage=="active","执行时间不包含前摇")
    advance(world,.11);check(world.boss_player.runner.node_run.stage=="recovery","完成后进入后摇")
    advance(world,.15);check(world.boss_player.flow_finished,"后摇结束后流程返回");world.free()
    wait=D.flow_node("wait",{"execution_duration":0.0})
    world=make_world([wait]);world.step();check(world.boss_player.flow_finished,"零时长各阶段不额外等待一帧");world.free()
    var condition=D.flow_node("condition",{"query":"player_x","threshold":0.0,"windup":.05,"recovery":.05})
    var yes=D.flow_node("teleport",{"target_mode":"world","target":Vector2(100,0)})
    var no=D.flow_node("teleport",{"target_mode":"world","target":Vector2(-100,0)})
    var flow=D.flow([condition,yes,no]);condition.connections={"yes":yes.id,"no":no.id};yes.connections.clear();no.connections.clear()
    var p=Fixture.project();p.bosses[0].phases[0].behavior_flow=flow;p.bosses[0].phases[0].loop=false
    world=STGSimulation.new();root.add_child(world);world.reset(p,"bosses","enemy");world.player=Vector2(600,0);advance(world,.04)
    check(world.boss==p.bosses[0].start_position,"条件前摇不提前判断")
    advance(world,.08);check(world.boss==Vector2(-100,0) and world.issue.is_empty() and not world.boss_player.runner.failed,"条件否走正常出口且不报告失败");world.free()
    var parallel=D.flow_node("parallel")
    parallel.children.assign([D.flow([D.flow_node("dash",{"target":Vector2(-100,0),"execution_duration":.2})]),D.flow([D.flow_node("attack",{"barrage_id":"fan","wait_mode":"emission","follow_enemy":true})])])
    world=make_world([parallel]);advance(world,.12)
    check(world.boss.x<0 and world.actors.size()>0 and world.issue.is_empty(),"冲刺与招式并行")
    advance(world,8);check(world.completed,"并行及后继攻击有限收尾");world.free()
    parallel=D.flow_node("parallel")
    parallel.children.assign([D.flow([D.flow_node("dash",{"execution_duration":1.0})]),D.flow([D.flow_node("dash",{"execution_duration":1.0})])])
    world=make_world([parallel]);advance(world,.03)
    check(world.issue.contains("位移争用"),"并行位移冲突明确报错")
    world.boss_player.runner.cancel();check(int(world.behavior_control.movement)==0,"中断释放位移控制权");world.free()
    for mode in ["line","dash","teleport","burrow","orbit","ballistic","curve"]:
        var node=D.flow_node(mode)
        if mode!="teleport":node.program_parameters.execution_duration=.15
        if mode=="orbit":node.program_parameters.target=Vector2.ZERO
        world=make_world([node]);advance(world,.18)
        check(world.issue.is_empty() and world.boss.is_finite() and world.boss_player.flow_finished,"独立移动程序："+mode)
        world.free()
    var coordinate_node=D.flow_node("line",{"target_mode":"world","target":Vector2(30,40),"execution_duration":.1})
    world=make_world([coordinate_node]);world.move_boss_frame(Vector2(100,200));advance(world,.15)
    check(world.boss.is_equal_approx(Vector2(130,240)),"关卡出生与卷轴偏移继续作用于固定移动目标")
    world.free()
    var fire=D.flow_node("attack",{"barrage_id":"fan","execution_duration":0.0,"wait_mode":"immediate","follow_enemy":true})
    var move=D.flow_node("dash",{"target":Vector2(-200,0),"execution_duration":.5})
    p=Fixture.project();p.find("barrages","fan").program_parameters={"rounds":3,"interval":.15,"duration":1.0}
    world=make_world([fire,move],p);advance(world,.08)
    var plan=world.barrages[0];var initial=world.actors[0].position
    advance(world,.12)
    check(plan.context.initial_origin()==Vector2.ZERO,"跟随原点不会改写调用时的原点快照")
    check(plan.origin.is_equal_approx(world.boss),"调用节点结束后原点跟随仍然生效")
    check(not world.actors[0].position.is_equal_approx(initial+(world.boss-plan.context.initial_origin())),"原点跟随不平移既有弹体")
    world.free()
    _test_animation_and_cancel()
    _test_random()
    _test_invalid_metadata_and_interrupt()
    _test_presets()
    _test_custom_contract()
    print("UNIFIED15 BEHAVIOR RESULT: %d checks, %d failures"%[checks,failures])
    quit(1 if failures else 0)
func _test_random():
    var random=D.flow_node("random",{"execution_duration":.02})
    var first=D.flow_node("wait",{"execution_duration":.01});first.connections={"completed":STGFlowNode.FAILURE}
    var second=D.flow_node("wait",{"execution_duration":.01});second.connections={"completed":STGFlowNode.SUCCESS}
    var flow=D.flow([random,first,second]);first.connections={"completed":STGFlowNode.FAILURE};second.connections={"completed":STGFlowNode.SUCCESS};random.connections={"choice_0":first.id,"choice_1":second.id}
    var p=Fixture.project();p.bosses[0].phases[0].loop=false;p.bosses[0].phases[0].behavior_flow=flow
    var traces=[]
    for i in 2:
        var world=STGSimulation.new();root.add_child(world);world.reset(p,"bosses","enemy",42);advance(world,.2)
        check(world.boss_player.flow_finished and not world.boss_player.runner.failed,"随机失败回退直到正常返回")
        traces.append(world.rng.state);world.free()
    check(traces[0]==traces[1],"固定种子随机流程确定性")
func _test_presets():
    var node=D.flow_node("attack",{"barrage_id":"fan"})
    var p=Fixture.project();p.behavior_presets.append(Copy.copy(node.behavior_preset))
    var previous=node.parameters().windup;p.behavior_presets[0].default_parameters.windup=.3
    check(node.parameters().windup==previous,"预设模板与节点快照隔离")
    node.behavior_preset.exposed_parameters.erase("barrage_id")
    check(not node.behavior_preset.validate(node.program_parameters).is_empty(),"禁止覆盖未开放字段")
    var wait=D.flow_node();wait.behavior_preset.exposed_parameters.clear();wait.program_parameters={"windup":.1,"recovery":.2}
    check(wait.behavior_preset.validate(wait.program_parameters).is_empty(),"前后摇始终可编辑")
    p.bosses[0].phases[0].behavior_flow=D.flow([D.flow_node("attack",{"barrage_id":"fan"})])
    check(References.users(p,"barrages","fan").size()>0,"声明参数进入引用保护")
    var compiled=Compiler.compile_library(p,[{"collection":"bosses","id":"enemy"}])
    check(compiled.issue.is_empty() and compiled.library.find("barrages","fan")!=null,"行为参数引用进入编译闭包")
    var path="user://behavior15_%d/library.tres"%Time.get_ticks_usec()
    check(Assets.save_library(p,path).is_empty(),"预设和节点通过正式事务保存")
    var loaded=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
    check(loaded!=null and loaded.schema_version==16 and loaded.behavior_presets.size()==1 and loaded.validate().is_empty(),"独立预设与节点保存重开")
    var invalid=Copy.copy(wait);invalid.program_parameters.windup=-.1
    check(not invalid.behavior_preset.validate(invalid.program_parameters).is_empty(),"负前摇被拒绝")
func _test_custom_contract():
    probe_path="res://stg/behaviors/contract_probe_%d.gd"%Time.get_ticks_usec()
    var file=FileAccess.open(probe_path,FileAccess.WRITE)
    file.store_string('@tool\n@static_unload\nextends STGBehaviorProgram\nvar held\nfunc start(ctx:STGBehaviorContext,p:Dictionary):\n held=ctx\n ctx.complete("custom")\nfunc cancel(_reason:String):\n Engine.set_meta("behavior15_cancelled",int(Engine.get_meta("behavior15_cancelled",0))+1)\n Engine.set_meta("behavior15_closed",not held.active() and not held.set_position(Vector2(999,999)))\n held=null\n');file.close()
    Engine.set_meta("behavior15_cancelled",0)
    var program=STGBehaviorProgramDefinition.new();program.id="custom.probe";program.title="契约探针";program.implementation=load(probe_path)
    program.outputs.assign([{"id":"custom","label":"自定义出口"},{"id":"failure","label":"失败"}])
    var declaration_path=probe_path.replace(".gd",".tres")
    check(ResourceSaver.save(program,declaration_path)==OK,"自定义节点声明与实现均存于统一目录")
    program=load(declaration_path)
    check(Catalog.definitions().any(func(item):return item.id=="custom.probe"),"自定义声明自动进入节点目录，无需注册白名单")
    var node=STGFlowNode.new();node.id="probe";node.behavior_preset=D.behavior_preset(program);node.program_parameters.execution_duration=0.0
    var world=make_world([node]);world.step()
    check(world.issue.is_empty() and world.boss_player.flow_finished,"新节点无需修改执行器即可运行自定义出口")
    check(int(Engine.get_meta("behavior15_cancelled"))==1 and bool(Engine.get_meta("behavior15_closed")),"清理一次且清理前关闭上下文")
    world.boss_player.runner.cancel();world.boss_player.runner.cancel()
    check(int(Engine.get_meta("behavior15_cancelled"))==1,"重复取消不会重复清理已完成程序");world.free()
    var wrong=STGBehaviorProgramDefinition.new();wrong.id="wrong";wrong.title="wrong";wrong.implementation=load("res://stg/programs/straight.gd")
    check(not wrong.validate({},"behavior").is_empty(),"招式或目录外脚本不能冒充行为节点")
    var library=Fixture.project();library.bosses[0].phases[0].behavior_flow=D.flow([node]);library.bosses[0].phases[0].loop=false
    var path="user://custom_behavior15_%d/library.tres"%Time.get_ticks_usec()
    check(Assets.save_library(library,path).is_empty(),"自定义程序节点通过正式资产事务保存")
    var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
    check(reopened!=null and reopened.validate().is_empty(),"自定义节点保存重开仍满足契约")
    var export_path="user://custom_behavior15_%d.tscn"%Time.get_ticks_usec()
    var host={"session":{"project":library},"collection":"bosses","selected_id":"enemy"}
    check(preload("res://addons/stg_maker/ui/commands.gd").export_prefab(host,export_path).is_empty(),"自定义节点使用正式预制体导出")
    var packed=load(export_path);var prefab=packed.instantiate();root.add_child(prefab)
    prefab.simulation.step()
    check(prefab.simulation.issue.is_empty(),"自定义节点预制体仍走统一执行器")
    prefab.free()
    Engine.remove_meta("behavior15_cancelled");Engine.remove_meta("behavior15_closed")
    for cleanup_path in [probe_path,declaration_path,probe_path+".uid"]:
        if FileAccess.file_exists(cleanup_path):DirAccess.remove_absolute(cleanup_path)

func animated_scene() -> PackedScene:
    var visual=Node2D.new();visual.name="EnemyVisual"
    var body=Node2D.new();body.name="Body";visual.add_child(body);body.owner=visual
    var player=AnimationPlayer.new();player.name="AnimationPlayer";visual.add_child(player);player.owner=visual
    var library=AnimationLibrary.new()
    for key in ["windup","active","recovery"]:
        var clip=Animation.new();clip.length=1.0
        var track=clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(track,NodePath("Body:rotation"))
        clip.track_insert_key(track,0,0.0);clip.track_insert_key(track,1,1.0)
        library.add_animation(key,clip)
    player.add_animation_library("",library)
    var packed=PackedScene.new();packed.pack(visual);visual.free();return packed
func animated_world(nodes:Array):
    var project=Fixture.project();project.bosses[0].visual_scene=animated_scene()
    return make_world(nodes,project)
func _test_animation_and_cancel():
    var node=D.flow_node("wait",{"execution_duration":.3,"windup":.2,"recovery":.2,"windup_animation":"windup","active_animation":"active","recovery_animation":"recovery"})
    var world=animated_world([node]);advance(world,.1)
    var player=world.boss_presentation.animation_player
    check(absf(player.current_animation_position-.5)<.05,"前摇动画按自定义时间缩放到同一模拟时钟")
    advance(world,.15)
    check(player.current_animation=="active" and absf(player.current_animation_position-(.05/.3))<.04,"执行动画按固定段循环对齐且只推进一次")
    advance(world,.3)
    check(player.current_animation=="recovery" and absf(player.current_animation_position-.25)<.06,"后摇动画按时长对齐")
    advance(world,.2)
    check(int(world.behavior_control.animation)==0 and world.boss_player.flow_finished,"完成后释放身体动画控制权");world.free()
    var parallel=D.flow_node("parallel",{"animation_branch":0,"execution_duration":.2,"windup":.1,"recovery":.1,"windup_animation":"windup","recovery_animation":"recovery"})
    parallel.children.assign([D.flow([D.flow_node("wait",{"execution_duration":.2,"active_animation":"active"})]),D.flow([D.flow_node("wait",{"execution_duration":.2,"active_animation":"recovery"})])])
    world=animated_world([parallel]);advance(world,.15)
    player=world.boss_presentation.animation_player
    check(world.issue.is_empty() and player.current_animation=="active" and absf(player.current_animation_position-(.05/.2))<.05,"指定分支控制动画，其他分支不抢占或重复推进")
    advance(world,.3);check(world.boss_player.flow_finished and int(world.behavior_control.animation)==0,"嵌套并行与父后摇正确交接动画");world.free()
    parallel.program_parameters.animation_branch=-1
    var project=Fixture.project();project.bosses[0].visual_scene=animated_scene();project.bosses[0].phases[0].behavior_flow=D.flow([parallel])
    check(Array(project.validate()).any(func(issue):return issue.contains("多个分支配置动画")),"未指定动画分支时启动前拒绝冲突")
    var called=D.flow([D.flow_node("wait",{"windup_animation":"missing","windup":.1})]);called.id="called_animation"
    project=Fixture.project();project.bosses[0].visual_scene=animated_scene();project.behaviors.append(called)
    project.bosses[0].phases[0].behavior_flow=D.flow([D.flow_node("call",{"behavior_id":called.id})])
    check("；".join(project.validate()).contains("动画不存在：missing"),"被调用子流程的动画在敌人表现场景中校验")
    for stage in ["windup","active","recovery"]:
        node=D.flow_node("dash",{"target":Vector2(-100,0),"execution_duration":.1,"windup":.1,"recovery":.3})
        world=make_world([node]);advance(world,{"windup":.05,"active":.15,"recovery":.25}[stage])
        check(world.boss_player.runner.node_run.stage==stage,"取消夹具处于"+stage)
        var runner=world.boss_player.runner;runner.cancel();runner.cancel()
        check(runner.cancelled and int(world.behavior_control.movement)==0 and int(world.behavior_control.animation)==0,"任意阶段强制取消均跳过后摇并释放控制权")
        world.free()
    var dash=D.flow_node("dash",{"target":Vector2(-500,0),"execution_duration":5.0,"recovery":10.0})
    project=Fixture.project();project.bosses[0].phases[0].behavior_flow=D.flow([dash]);project.bosses[0].phases[0].loop=false
    var next=D.phase();next.enter_hp=50.0;project.bosses[0].phases.append(next)
    world=STGSimulation.new();root.add_child(world);world.reset(project,"bosses","enemy");advance(world,.05)
    var previous=world.boss_player.runner
    world.damage_boss(60);world.step()
    check(previous.cancelled and world.boss_player.phase_index==1,"血量阶段切换立即取消旧节点")
    world.free()
    world=make_world([dash]);advance(world,.05);previous=world.boss_player.runner
    world.damage_boss(100);world.step()
    check(previous.cancelled and world.boss_player.finished and int(world.behavior_control.movement)==0,"死亡立即取消位移且不等待后摇");world.free()

func _test_invalid_metadata_and_interrupt():
    var project=Fixture.project()
    var node=D.flow_node("parallel",{"animation_branch":"invalid"})
    node.children.append(D.flow());project.bosses[0].phases[0].behavior_flow=D.flow([node])
    check(not project.validate().is_empty(),"错误类型的结构参数被校验拒绝，不抛运行异常")
    node=D.flow_node("random",{"branches":1000000000});project.bosses[0].phases[0].behavior_flow=D.flow([node])
    check(not project.validate().is_empty() and node.outputs().size()<=130,"无效分支数量被拒绝且不会分配无界端口")
    node=D.flow_node();node.behavior_preset.parameter_options.execution_duration=42
    check(not node.behavior_preset.validate().is_empty(),"无效参数包装草稿可安全校验")
    node=D.flow_node("dash",{"execution_duration":2.0,"recovery":10.0,"interrupt_on_hit":true})
    var world=make_world([node]);advance(world,.02)
    var executing=world.boss_player.runner.node_run
    world.boss_hit_serial+=1;world.step()
    check(executing.finished and executing.failed and executing.output_id=="failure" and int(world.behavior_control.movement)==0,"受击中断由公共宿主立即执行，跳过后摇并走失败出口")
    world.free()
    var runner_source=FileAccess.get_file_as_string("res://stg/runtime/boss/flow_runner.gd")
    check(not runner_source.contains("node.kind") and not runner_source.contains("ActionRunner") and not runner_source.contains("builtin"),"通用执行器没有节点类型分支或内置快捷入口")
    for path in ["action_runner","attack_player","movement_player","target_resolver"]:
        check(not FileAccess.file_exists("res://stg/runtime/boss/"+path+".gd"),"旧节点执行代码已移除："+path)

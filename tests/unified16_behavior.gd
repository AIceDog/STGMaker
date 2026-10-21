extends SceneTree
const D=preload("res://stg/definitions/definition_factory.gd")
const Fixture=preload("res://tests/unified14_fixture.gd")
const Timing=preload("res://stg/definitions/behavior_timing.gd")
const Scenes=preload("res://tests/behavior_visual_fixture.gd")
var checks=0
var failures=0
var probe_path:String
var program:STGBehaviorProgramDefinition
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
    checks+=1
    if not ok:failures+=1;push_error(message)
func advance(world,seconds:float):
    var left=seconds
    while left>0.0000001:
        var dt=minf(STGSimulation.STEP,left);world.step(dt);left-=dt
func world_for(flow:STGBehaviorFlow,p:STGProject=null,visual:bool=false):
    if p==null:p=Fixture.project()
    p.bosses[0].phases[0].behavior_flow=flow;p.bosses[0].phases[0].loop=false
    if visual:
        p.bosses[0].visual_scene=Scenes.animated_scene()
    var world=STGSimulation.new();root.add_child(world);world.reset(p,"bosses","enemy")
    check(world.issue.is_empty(),"夹具启动："+world.issue)
    return world
func probe(mode:String,duration:float=.2):
    var node=STGFlowNode.new();node.id=D.uid("probe");node.behavior_preset=D.behavior_preset(program)
    node.program_parameters={"execution_duration":duration,"probe_mode":mode};return node
func run():
    probe_path="res://stg/behaviors/timing_probe_%d.gd"%Time.get_ticks_usec()
    var file=FileAccess.open(probe_path,FileAccess.WRITE)
    file.store_string('@tool\n@static_unload\nextends STGBehaviorProgram\nvar held\nvar mode:String\nfunc start(ctx:STGBehaviorContext,p:Dictionary):\n held=ctx;mode=p.probe_mode\n Engine.set_meta("v16_starts",int(Engine.get_meta("v16_starts",0))+1)\n Engine.set_meta("v16_duration",ctx.execution_duration())\n if mode=="early":ctx.complete()\n elif mode=="dynamic":\n  var handle=ctx.start_branch(0)\n  Engine.set_meta("v16_handle",handle)\nfunc tick(ctx:STGBehaviorContext,_dt:float):\n Engine.set_meta("v16_progress",ctx.execution_progress())\n Engine.set_meta("v16_remaining",ctx.execution_remaining())\nfunc cancel(reason:String):\n Engine.set_meta("v16_cancels",int(Engine.get_meta("v16_cancels",0))+1)\n Engine.set_meta("v16_reason",reason)\n Engine.set_meta("v16_closed",not held.active() and not held.set_position(Vector2(999,999)))\n held=null\n')
    file.close()
    program=STGBehaviorProgramDefinition.new();program.id="probe.fixed";program.title="定长探针";program.implementation=load(probe_path)
    program.capabilities=["children"]
    program.fields.append({"name":"probe_mode","label":"探针方式","type":"string","default":"early"})
    check(program.validate(program.default_parameters(),"behavior").is_empty(),"自定义契约仍走相同声明")
    timing_tests();animation_tests();audio_tests();budget_tests();attack_tests();replay_tests()
    for key in ["v16_starts","v16_cancels","v16_duration","v16_progress","v16_remaining","v16_reason","v16_closed","v16_handle"]:
        Engine.remove_meta(key)
    program=null
    for path in [probe_path,probe_path+".uid"]:
        if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
    print("UNIFIED16 BEHAVIOR RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func reset_probe():
    Engine.set_meta("v16_starts",0);Engine.set_meta("v16_cancels",0)
func timing_tests():
    reset_probe();var node=probe("early");node.program_parameters.windup=.05;node.program_parameters.recovery=.05
    var world=world_for(D.flow([node]));advance(world,.04)
    check(Engine.get_meta("v16_starts")==0,"前摇结束前不启动")
    advance(world,.02);var run=world.boss_player.runner.node_run
    check(Engine.get_meta("v16_starts")==1 and Engine.get_meta("v16_closed") and run.stage=="active","提前完成关闭上下文，表现继续")
    advance(world,.18)
    check(run.stage=="active" and Engine.get_meta("v16_starts")==1,"定长区间不会重复执行程序")
    advance(world,.02);check(run.stage=="recovery","执行到时进入后摇")
    advance(world,.04);check(world.boss_player.flow_finished,"精确总时长 .3 秒返回")
    check(Engine.get_meta("v16_cancels")==1,"提前完成清理至多一次")
    world.free()
    reset_probe();node=probe("pending",.03);node.program_parameters.recovery=.02
    world=world_for(D.flow([node]));advance(world,.03);run=world.boss_player.runner.node_run
    check(run.stage=="recovery" and run.failed and run.output_id=="failure","执行超时先清理再进入失败后摇")
    check(Engine.get_meta("v16_reason")=="expired" and Engine.get_meta("v16_closed"),"超时关闭上下文且原因明确")
    check(is_equal_approx(float(Engine.get_meta("v16_progress")),1) and is_zero_approx(float(Engine.get_meta("v16_remaining"))),"执行进度与剩余预算查询")
    advance(world,.02);check(world.boss_player.runner.failed and world.issue.is_empty(),"超时失败沿正常失败出口返回")
    world.boss_player.runner.cancel();world.boss_player.runner.cancel()
    check(Engine.get_meta("v16_cancels")==1,"超时后重复取消无重复清理");world.free()
    for mode in ["early","pending"]:
        node=probe(mode,0);world=world_for(D.flow([node]));world.step()
        check(world.boss_player.flow_finished and world.boss_player.runner.failed==(mode=="pending"),"零时长完成与超时："+mode);world.free()
    node=probe("pending",.5);world=world_for(D.flow([node]));advance(world,.01)
    var context=world.boss_player.runner.node_run.context
    world.boss_player.runner.cancel();check(not context.active() and not context.set_position(Vector2(999,0)),"取消后命令被拒绝");world.free()
func animation_tests():
    for item in [[5.0,2,1.2],[7.0,2,6.0/7.0],[1.0,1,3.0]]:
        var plan=Timing.animation_plan(3,item[0],"active")
        check(plan.cycles==item[1] and is_equal_approx(plan.rate,item[2]),"执行循环次数和倍率："+str(item[0]))
    check(Timing.animation_plan(3,5,"active","fit_cycles",3).rate==1.8,"手动指定三次")
    check(Timing.animation_plan(3,5,"active","once_hold").rate==1,"一次模式保留原速")
    check(Timing.animation_plan(3,1,"active","once_hold").rate==3,"一次模式不足时加速")
    check(Timing.animation_plan(3,0,"windup").cycles==0,"零时长跳过动画")
    var scene=Scenes.animated_scene()
    var original=scene.instantiate();var shared=original.get_node("AnimationPlayer").get_animation("active");shared.loop_mode=Animation.LOOP_LINEAR
    var player=preload("res://stg/runtime/boss/presentation_player.gd").new();root.add_child(player);player.configure(scene)
    player.enter_stage("active",2,"active","fit_cycles",2);player.tick(1.25)
    check(is_equal_approx(player.animation_player.current_animation_position,.25),"循环以累计模拟秒精确采样")
    player.tick(.75);check(is_equal_approx(player.visual.get_node("Body").rotation,1),"循环阶段完整末帧")
    check(shared.loop_mode==Animation.LOOP_LINEAR,"运行不修改共享动画循环设置")
    player.enter_stage("recovery",2,"recovery");player.tick(.5)
    check(is_equal_approx(player.animation_player.current_animation_position,.25),"前后摇适配完整一次")
    player.enter_stage("active",2,"active","once_hold");player.tick(1.5)
    check(is_equal_approx(player.visual.get_node("Body").rotation,1),"一次播放后保持末帧")
    player.configure(scene)
    check(player.get_child_count()==1,"重复配置只保留一个敌人表现场景")
    player.configure(null)
    check(player.get_child_count()==0 and player.animation_player==null,"移除表现场景同时释放动画实例")
    player.free();original.free()
func sound(length:float=1) -> AudioStreamWAV:
    var stream=AudioStreamWAV.new();stream.mix_rate=8000;stream.format=AudioStreamWAV.FORMAT_8_BITS
    var data=PackedByteArray();data.resize(int(8000*length));data.fill(128);stream.data=data;return stream
func audio_tests():
    var stream=sound(2)
    var node=D.flow_node("wait",{"execution_duration":.5,"windup":.25,"recovery":.25,"windup_animation":"windup","active_animation":"active","recovery_animation":"recovery","windup_sound":stream,"active_sound":stream,"recovery_sound":stream,"active_volume_db":-9.0})
    var world=world_for(D.flow([node]),null,true);advance(world,.125)
    var run=world.boss_player.runner.node_run;var old=run.stage_sound
    check(old!=null and is_equal_approx(old.audio.pitch_scale,4),"前摇音频跟随动画4倍速")
    check(is_equal_approx(old.remaining,1.5),"音频寿命只按真实阶段推进一次")
    advance(world,.125);run=world.boss_player.runner.node_run
    check(not old.alive if is_instance_valid(old) else true,"阶段切换停止旧声音")
    check(run.stage=="active" and is_equal_approx(run.stage_sound.audio.pitch_scale,2) and is_equal_approx(run.stage_sound.audio.volume_db,-9),"执行声音倍率与独立音量")
    world.set_presentation_clock(false,2)
    check(run.stage_sound.audio.stream_paused and is_equal_approx(run.stage_sound.audio.pitch_scale,4),"暂停与全局2倍速叠加")
    world.muted=true;world.set_presentation_clock(true,.5)
    check(run.stage_sound.audio.stream_paused and is_equal_approx(run.stage_sound.audio.pitch_scale,1),"静音与全局减速")
    world.muted=false;world.set_presentation_clock(true,1)
    advance(world,.1);check(not run.stage_sound.audio.stream_paused,"取消静音恢复同一实例")
    var voice=run.stage_sound;world.boss_player.runner.cancel();check(not voice.alive and not voice.audio.playing,"强制取消立即停止声音");world.free()
    node=D.flow_node("wait",{"execution_duration":.2,"active_sound":sound(.03),"active_sound_loop":false})
    world=world_for(D.flow([node]));advance(world,.04)
    run=world.boss_player.runner.node_run;check(not is_instance_valid(run.stage_sound) or not run.stage_sound.alive,"一次音频按自身长度结束，阶段继续");world.free()
    node.program_parameters.active_sound_loop=true
    world=world_for(D.flow([node]));advance(world,.1);voice=world.boss_player.runner.node_run.stage_sound
    check(is_instance_valid(voice) and voice.alive,"循环音频持续到阶段末尾")
    advance(world,.1);check(not is_instance_valid(voice) or not voice.alive,"循环音频在阶段结束停止");world.free()
    var parallel=D.flow_node("parallel",{"execution_duration":.2,"animation_branch":0})
    parallel.children.assign([D.flow([D.flow_node("wait",{"execution_duration":.2,"active_animation":"active","active_sound":stream})]),D.flow([D.flow_node("wait",{"execution_duration":.2,"active_animation":"recovery","active_sound":stream})])])
    world=world_for(D.flow([parallel]),null,true);advance(world,.01)
    var voices=world.effects.filter(func(effect):return is_instance_valid(effect.node) and effect.node.stream!=null and effect.node.alive)
    check(voices.size()==2 and voices[0].node.owner_id!=voices[1].node.owner_id,"并行声音按节点实例隔离")
    check(world.boss_presentation.animation_player.current_animation=="active","并行身体动画仍归指定分支")
    world.boss_player.runner.cancel();check(voices.all(func(effect):return not effect.node.alive),"并行取消统一回收全部声音");world.free()
func budget_tests():
    var a=D.flow_node("wait",{"execution_duration":.013,"windup":.01,"recovery":.02})
    var b=D.flow_node("wait",{"execution_duration":.017})
    var sequence=D.flow([a,b]);var p=Fixture.project()
    check(is_equal_approx(Timing.flow_duration(sequence,p),.06),"顺序预算累加三段")
    var condition=D.flow_node("condition");var c=D.flow([condition,a,b]);condition.connections={"yes":a.id,"no":b.id};a.connections.clear();b.connections.clear()
    check(is_equal_approx(Timing.flow_duration(c,p),.043),"条件预算取最长路径")
    var parallel=D.flow_node("parallel",{"execution_duration":.043})
    parallel.children.assign([D.flow([a]),D.flow([b])])
    check(is_equal_approx(Timing.required_execution(parallel,D.flow([parallel]),p),.043),"并行预算取最长分支")
    var random=D.flow_node("random",{"execution_duration":.06});var flow=D.flow([random,a,b])
    a.connections={"completed":STGFlowNode.FAILURE};b.connections={"completed":STGFlowNode.SUCCESS};random.connections={"choice_0":a.id,"choice_1":b.id}
    check(is_equal_approx(Timing.required_execution(random,flow,p),.06),"随机候选最坏预算求和且不重复计继续出口")
    p.bosses[0].phases[0].behavior_flow=flow
    random.program_parameters.execution_duration=.059
    check("；".join(p.validate()).contains("至少需要 0.060000"),"静态预算不足报告所需最短时长")
    random.program_parameters.execution_duration=.06
    var world=world_for(flow,p);world.step(.06)
    check(world.boss_player.flow_finished and world.issue.is_empty() and not world.boss_player.runner.failed,"非整步候选恰好预算同帧成功")
    check(is_equal_approx(world.boss_player.runner.elapsed,.06),"延期结算不会重复累计父流程时间")
    world.free()
    var zero_random=D.flow_node("random",{"execution_duration":0.0})
    var zero_a=D.flow_node("wait",{"execution_duration":0.0});var zero_b=D.flow_node("wait",{"execution_duration":0.0})
    var zero_flow=D.flow([zero_random,zero_a,zero_b]);zero_random.connections={"choice_0":zero_a.id,"choice_1":zero_b.id}
    zero_a.connections={"completed":STGFlowNode.FAILURE};zero_b.connections={"completed":STGFlowNode.SUCCESS}
    world=world_for(zero_flow);world.step()
    check(world.boss_player.flow_finished and not world.boss_player.runner.failed,"零预算随机候选先回退结算，不误报父超时")
    world.free()
    var inner=D.flow_node("parallel",{"execution_duration":.06});inner.children.assign([flow])
    var outer=D.flow_node("parallel",{"execution_duration":.08});outer.children.assign([D.flow([inner,D.flow_node("wait",{"execution_duration":.02})])])
    world=world_for(D.flow([outer]));world.step(.08)
    check(world.boss_player.flow_finished and not world.boss_player.runner.failed,"嵌套并行完整预算精确边界");world.free()
    var short_inner=D.flow_node("parallel",{"windup":.02,"execution_duration":.01})
    short_inner.children.assign([D.flow([D.flow_node("wait",{"execution_duration":.043})])])
    var short_outer=D.flow_node("parallel",{"execution_duration":.01});short_outer.children.assign([D.flow([short_inner])])
    check(is_equal_approx(Timing.required_execution(short_outer,D.flow([short_outer]),p),.063),"不足预算的嵌套子树仍向上传播正确最短时长")
    var cycle=D.flow([D.flow_node("call",{"behavior_id":"cycle","execution_duration":1.0})]);cycle.id="cycle"
    p.behaviors.append(cycle)
    check(not is_finite(Timing.flow_duration(cycle,p)),"预算分析拒绝引用循环")
    p.behaviors.erase(cycle)
    var called=D.flow([D.flow_node("wait",{"windup":.01,"execution_duration":.02,"recovery":.01})]);called.id="budget_called"
    p=Fixture.project();p.behaviors.append(called)
    var call=D.flow_node("call",{"behavior_id":called.id,"execution_duration":.04})
    check(is_equal_approx(Timing.required_execution(call,D.flow([call]),p),.04),"引用子流程完整三段预算")
    world=world_for(D.flow([call]),p);world.step(.04)
    check(world.boss_player.flow_finished and not world.boss_player.runner.failed,"子流程先结算再判断父到时");world.free()
    var dynamic=probe("dynamic",.01);dynamic.behavior_preset.program=program.duplicate();dynamic.behavior_preset.program.branch_mode="children"
    dynamic.children.assign([called])
    world=world_for(D.flow([dynamic]));world.step()
    check(Engine.get_meta("v16_handle")==0 and world.issue.contains("预算不足"),"自定义动态子任务启动检查剩余预算");world.free()
func attack_tests():
    for mode in ["immediate","emission","cleared"]:
        var p=Fixture.project();p.find("barrages","fan").program_parameters={"rounds":1,"count":1,"duration":.1}
        var node=D.flow_node("attack",{"barrage_id":"fan","execution_duration":.1,"wait_mode":mode,"recovery":.02})
        var world=world_for(D.flow([node]),p);advance(world,.12)
        check(world.boss_player.flow_finished and not world.boss_player.runner.failed,"招式完成方式共用定长区间："+mode);world.free()
    var p=Fixture.project();p.find("barrages","fan").program_parameters={"rounds":10,"interval":.1,"count":1,"duration":1.0}
    var node=D.flow_node("attack",{"barrage_id":"fan","execution_duration":.03,"wait_mode":"emission"})
    var world=world_for(D.flow([node]),p);advance(world,.03)
    check(world.boss_player.runner.failed and world.actors.size()==1,"超时停止未来发射，保留已发攻击")
    advance(world,.3);check(world.actors.size()==1,"超时后不再产生新弹");world.free()
func replay_tests():
    var snapshots=[]
    for speed in [.5,1.0,2.0]:
        var node=D.flow_node("orbit",{"execution_duration":.3,"target_mode":"player","target":Vector2.ZERO})
        node.id="repeat"
        var world=world_for(D.flow([node]));world.set_presentation_clock(true,speed)
        advance(world,.15);world.set_presentation_clock(false,speed)
        var before=world.boss;check(world.boss==before,"暂停不推进逻辑")
        world.set_presentation_clock(true,speed);advance(world,.15)
        snapshots.append([world.boss,world.rng.state,world.boss_player.runner.history.duplicate()])
        world.free()
    check(snapshots[0]==snapshots[1] and snapshots[1]==snapshots[2],"相同固定步长在暂停、倍速与重播下保持一致")

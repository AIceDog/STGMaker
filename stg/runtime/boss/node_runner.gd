@tool
extends RefCounted
## 所有节点统一定长执行。程序结果与表现时钟分离，提前完成不重复运行。
const Session=preload("res://stg/runtime/extensions/extension_session.gd")
const Adapter=preload("res://stg/runtime/boss/behavior_adapter.gd")
const Timing=preload("res://stg/definitions/behavior_timing.gd")
var session=Session.new()
var adapter
var node:STGFlowNode
var behavior
var parameters:Dictionary
var context:STGBehaviorContext
var stage:String="windup"
var stage_elapsed:float=0
var finished:bool=false
var failed:bool=false
var output_id:String="completed"
var remaining:float=0
var deadline_pending:bool=false
var animation_plan:Dictionary={}
var stage_sound
var _animation_owned:bool=false
var _movement_owned:bool=false
var _hit_serial:int=0
var _restore_visible:bool=true
var _restore_invulnerable:bool=false
func start(value:STGFlowNode,data,flow:STGBehaviorFlow,tasks:Array) -> void:
    node=value;behavior=data
    if node.behavior_preset==null:_error("节点缺少行为预设与程序声明");return
    var issues=node.behavior_preset.validate(node.program_parameters)
    if not issues.is_empty():_error("；".join(issues));return
    parameters=node.parameters();_hit_serial=behavior.world.boss_hit_serial
    adapter=Adapter.new();adapter.configure(node,behavior,flow,tasks)
    adapter.execution_duration=float(parameters.execution_duration)
    _restore_visible=behavior.world.boss_visible;_restore_invulnerable=behavior.world.boss_invulnerable
    behavior.active_node_id=node.id;behavior.action_running=true
    _enter("windup")
func tick(dt:float) -> bool:
    remaining=dt
    if finished:return true
    if adapter==null:return false
    if deadline_pending:return false
    if parameters.get("interrupt_on_hit",false) and behavior.world.boss_hit_serial!=_hit_serial:
        cancel("interrupted");remaining=0;return true
    for transition in 128:
        if stage in ["windup","recovery"]:
            var duration:float=parameters[stage]
            var consumed=minf(remaining,maxf(0,duration-stage_elapsed))
            stage_elapsed+=consumed;remaining-=consumed;_animate(consumed)
            if stage_elapsed+0.000001<duration:return false
            if stage=="recovery":_finish();return true
            if not _begin_active():return true
        if stage=="active":
            var duration:float=parameters.execution_duration
            adapter.advance_tasks(0)
            if adapter.has_pending():return false
            var consumed=adapter.next_boundary(minf(remaining,maxf(0,duration-stage_elapsed)))
            adapter.step_budget=consumed
            adapter.advance_tasks(consumed)
            stage_elapsed+=consumed;remaining-=consumed
            adapter.execution_elapsed=stage_elapsed
            if not session.finished and consumed>0:session.tick(consumed)
            _animate(consumed)
            if session.finished:_release_movement()
            if stage_elapsed+0.000001<duration:
                if remaining>0.000001 and not adapter.has_pending():continue
                return false
            if not session.finished or adapter.has_pending():
                deadline_pending=true;return false
            _resolve_active()
            if finished:return true
    return finished
func _begin_active() -> bool:
    if "movement" in node.behavior_preset.program.capabilities:
        var control:Dictionary=behavior.world.behavior_control
        if int(control.movement)!=0:_error("同一敌人存在并行位移争用");return false
        control.movement=get_instance_id();_movement_owned=true
    _enter("active")
    if finished:return false
    context=STGBehaviorContext.new();context._execution_duration=float(parameters.execution_duration)
    context._dispatch=adapter.command;context._query=adapter.query
    adapter.movement_token=get_instance_id() if _movement_owned else 0
    adapter.step_budget=minf(remaining,float(parameters.execution_duration))
    if not session.begin(node.behavior_preset.program,parameters,"behavior",context):_error(session.issue);return false
    return true
func settle() -> void:
    if finished or adapter==null:return
    # 零时长候选也先完成，再让父程序选择下一个候选；不重复推进模拟秒。
    for attempt in 128:
        var before=adapter.task_stamp()
        adapter.settle_tasks()
        if not session.finished:session.settle_behavior()
        adapter.advance_tasks(0)
        if before==adapter.task_stamp():break
        if attempt==127:_error("节点单步子任务结算超过128次");return
    if not deadline_pending:
        var left=remaining
        tick(left)
        return
    deadline_pending=false
    if not session.finished:
        session.cancel("expired",true);adapter.cancel(false)
        failed=true;output_id="failure"
    _resolve_active()
    tick(remaining)
func _resolve_active() -> void:
    if context!=null and session.finished and not failed:
        failed=session.failed;output_id="failure" if failed else context.output_id
    var ids=node.ports().map(func(port):return port.id)
    if output_id not in ids:_error("节点返回未声明出口："+output_id);return
    _release_movement();_enter("recovery")
func _duration() -> float:return float(parameters.execution_duration if stage=="active" else parameters[stage])
func _enter(value:String) -> void:
    _stop_sound();stage=value;stage_elapsed=0
    behavior.action_state={"windup":"前摇","active":"执行","recovery":"后摇"}[value]
    var duration=_duration()
    var name:String=parameters.get(value+"_animation","")
    var length:float=behavior.world.boss_presentation.clip_length(name)
    animation_plan=Timing.animation_plan(length,duration,value,str(parameters.active_animation_mode),int(parameters.active_cycles))
    var allowed=behavior.animation_allowed and not name.is_empty() and duration>0 and not (value=="active" and not node.children.is_empty())
    if allowed:
        var control:Dictionary=behavior.world.behavior_control
        if int(control.animation) not in [0,get_instance_id()]:_error("同一敌人存在身体动画争用");return
        control.animation=get_instance_id();_animation_owned=true
        behavior.world.boss_presentation.enter_stage(name,duration,value,str(parameters.active_animation_mode),int(parameters.active_cycles))
    else:_release_animation(false)
    var sound=parameters.get(value+"_sound")
    if sound!=null and duration>0:
        stage_sound=behavior.world.create_program_presentation({"stream":sound,"position":behavior.world.boss,"looped":bool(parameters.get(value+"_sound_loop",false)),"manual_clock":true,"speed_scale":float(animation_plan.rate),"volume_db":float(parameters.get(value+"_volume_db",0))},behavior.world.allocate_owner())
func _stop_sound() -> void:
    if is_instance_valid(stage_sound):stage_sound.stop()
    stage_sound=null
func _animate(dt:float) -> void:
    if is_instance_valid(stage_sound):stage_sound.tick(dt)
    if _animation_owned and int(behavior.world.behavior_control.animation)==get_instance_id():behavior.world.boss_presentation.tick(dt)
func _release_movement() -> void:
    if not _movement_owned:return
    if int(behavior.world.behavior_control.movement)==get_instance_id():behavior.world.behavior_control.movement=0
    behavior.world.boss_visible=_restore_visible;behavior.world.boss_invulnerable=_restore_invulnerable;_movement_owned=false
func _release_animation(reset:bool=true) -> void:
    if not _animation_owned:return
    if int(behavior.world.behavior_control.animation)==get_instance_id():
        behavior.world.behavior_control.animation=0
        if reset:behavior.world.boss_presentation.reset()
        else:behavior.world.boss_presentation.pause_pose()
    _animation_owned=false
func _finish() -> void:
    if finished:return
    finished=true;_stop_sound();_release_movement();_release_animation()
    behavior.world.action_completed_at[node.id]=behavior.world.time
    behavior.world.boss_action_event.emit(node.id,"completed" if not failed else "failed")
    behavior.action_running=false;behavior.active_node_id=""
func _error(message:String) -> void:
    failed=true;output_id="failure";behavior.world.issue=node.title+"："+message
    session.cancel("failed",true)
    if adapter!=null:adapter.cancel()
    _finish()
func cancel(reason:String="stopped",clear_attacks:bool=true) -> void:
    if finished:return
    session.cancel(reason)
    if adapter!=null:adapter.cancel(clear_attacks)
    _stop_sound();_release_movement();_release_animation()
    finished=true;failed=true;output_id="failure";deadline_pending=false
    behavior.action_running=false;behavior.active_node_id=""
    behavior.world.boss_action_event.emit(node.id,"cancelled")
func rebase(displacement:Vector2) -> void:
    if session.implementation!=null:session.implementation.rebase(displacement)

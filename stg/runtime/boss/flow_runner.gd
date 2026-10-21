@tool
extends RefCounted
## 通用图执行器：不识别任何具体节点类型，所有算法均由声明程序执行。
enum Status { RUNNING, SUCCESS, FAILURE }
const NodeRunner=preload("res://stg/runtime/boss/node_runner.gd")
var flow:STGBehaviorFlow
var context
var current_id:String=""
var node_run
var history:Dictionary={}
var elapsed:float=0
var cancelled:bool=false
var failed:bool=false
var _finished:bool=false
var _spawned_plans:Array=[]
var managed:bool=false
var first_step_duration:float=-1
var follow_enemy:bool=false
var owner_id:int:
    get:return context.owner_id if context!=null else 0
var origin:Vector2:
    get:return context.origin if context!=null else Vector2.ZERO
    set(value):
        if context!=null:context.origin=value
func start(definition:STGBehaviorFlow,data) -> void:
    flow=definition;context=data;current_id=flow.entry_id
    node_run=null;history.clear();_spawned_plans.clear()
    elapsed=0;cancelled=false;failed=false;_finished=false
func reset() -> void:
    var target=flow.loop_entry_id
    start(flow,context)
    if not target.is_empty():current_id=target
func states() -> Dictionary:return history
func returned() -> bool:return _finished or cancelled
func tick(dt:float) -> int:
    if cancelled:return Status.FAILURE
    if _finished:return Status.FAILURE if failed else Status.SUCCESS
    if first_step_duration>=0:
        dt=minf(dt,first_step_duration);first_step_duration=-1
    if follow_enemy:context.origin=context.world.boss
    var budget=dt
    for transition in 128:
        if STGFlowNode.is_terminal(current_id):
            _finished=true;failed=current_id==STGFlowNode.FAILURE
            return Status.FAILURE if failed else Status.SUCCESS
        var node=flow.find(current_id)
        if node==null:
            context.world.issue="行为连接目标不存在："+current_id
            failed=true;_finished=true;return Status.FAILURE
        if node_run==null:
            history[node.id]=Status.RUNNING
            node_run=NodeRunner.new()
            node_run.start(node,context,flow,_spawned_plans)
        var done:bool=node_run.tick(budget)
        elapsed+=maxf(0,budget-node_run.remaining)
        if not done:return Status.RUNNING
        budget=node_run.remaining
        history[node.id]=Status.FAILURE if node_run.failed else Status.SUCCESS
        var output:String=node_run.output_id
        var error:bool=node_run.failed and not context.world.issue.is_empty()
        current_id=node.target(output)
        node_run=null
        if error:
            failed=true;_finished=true;return Status.FAILURE
        if output=="failure" and current_id.is_empty():current_id=STGFlowNode.FAILURE
    context.world.issue="行为流程单步超过128次切换，请检查无等待循环"
    failed=true;_finished=true;return Status.FAILURE
func time_to_boundary() -> float:
    if returned():return INF
    if node_run==null:return 0.0
    var left=maxf(0,node_run._duration()-node_run.stage_elapsed)
    return node_run.adapter.next_boundary(left) if node_run.stage=="active" else left
func pending_boundary() -> bool:
    return node_run!=null and (node_run.deadline_pending or (node_run.adapter!=null and node_run.adapter.has_pending()))
func settle() -> void:
    if node_run==null or cancelled:return
    var before:float=node_run.remaining
    node_run.settle()
    elapsed+=maxf(0,before-node_run.remaining)
    if node_run.finished:
        var left:float=node_run.remaining
        tick(left)
func emission_finished() -> bool:
    if cancelled:return true
    if not _finished:return false
    for task in _spawned_plans:
        if not task.plan.emission_finished():return false
    return true
func is_finished(world) -> bool:
    if not emission_finished() or world.count_owned(owner_id,false)>0:return false
    for task in _spawned_plans:
        if not task.plan.is_finished(world):return false
    return true
func cancel(clear_attacks:bool=true) -> void:
    if cancelled:return
    cancelled=true
    if node_run!=null:node_run.cancel("stopped",clear_attacks)
    for task in _spawned_plans:
        if task.structural:task.plan.cancel(clear_attacks)
        else:task.plan.cancel()
        if clear_attacks:context.world.stop_owner(task.plan.owner_id)
    node_run=null
    if context!=null:context.action_running=false;context.active_node_id=""
func rebase(displacement:Vector2) -> void:
    if node_run!=null:node_run.rebase(displacement)

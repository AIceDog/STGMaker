@tool
extends RefCounted
## 上下文的受控实现：只提供通用命令、任务句柄与权限，不识别节点种类。
var node:STGFlowNode
var behavior
var flow:STGBehaviorFlow
var tasks:Array
var owned:Array=[]
var movement_token:int=0
const Timing=preload("res://stg/definitions/behavior_timing.gd")
var step_budget:float=0
var execution_duration:float=0
var execution_elapsed:float=0
func next_boundary(maximum:float) -> float:
    var result=maximum
    for task in owned:
        if task.structural and not task.plan.returned():result=minf(result,task.plan.time_to_boundary())
    return result
func advance_tasks(dt:float) -> void:
    for task in owned.duplicate():
        if task.structural:task.plan.tick(dt)
func task_stamp() -> Array:
    var result:Array=[]
    for task in owned:
        if task.structural:
            var plan=task.plan
            result.append([plan.current_id,plan.returned(),plan.failed,plan.cancelled,plan.node_run.stage if plan.node_run!=null else ""])
    return result
func settle_tasks() -> void:
    for task in owned.duplicate():
        if task.structural:task.plan.settle()
func has_pending() -> bool:
    for task in owned:
        if task.structural and task.plan.pending_boundary():return true
    return false
func _fits(definition:STGBehaviorFlow) -> bool:
    var required=Timing.flow_duration(definition,behavior.world.project)
    var available=maxf(0,execution_duration-execution_elapsed)
    if not is_finite(required) or required>available+Timing.EPSILON:
        behavior.world.issue=node.title+"：子任务预算不足，至少需要 %.6f 秒，剩余 %.6f 秒"%[required,available]
        return false
    return true
func configure(value:STGFlowNode,data,definition:STGBehaviorFlow,shared:Array) -> void:
    node=value;behavior=data;flow=definition;tasks=shared
func _capability(name:String) -> bool:return name in node.behavior_preset.program.capabilities
func command(key:String,data:Dictionary):
    var world=behavior.world
    match key:
        "error":
            if world.issue.is_empty():world.issue=node.title+"："+str(data.message)
            return false
        "position":
            if not _capability("movement") or movement_token==0 or int(world.behavior_control.movement)!=movement_token:
                world.issue="行为没有位移控制权";return false
            if not data.value is Vector2 or not data.value.is_finite() or data.value.length()>1000000:
                world.issue="行为提交非有限或越界坐标";return false
            world.boss=data.value;return true
        "visible","invulnerable":
            if not _capability("movement") or movement_token==0:return false
            if key=="visible":world.boss_visible=bool(data.value)
            else:world.boss_invulnerable=bool(data.value)
            return true
        "contact":
            if not _capability("movement") or movement_token==0:return false
            if not data.previous.is_finite() or not is_finite(float(data.radius)) or not is_finite(float(data.damage)) or data.radius<=0 or data.damage<0:
                world.issue="行为提交无效本体判伤参数";return false
            var hit=world.player.distance_to(Geometry2D.get_closest_point_to_segment(world.player,data.previous,world.boss))<data.radius+world.player_radius
            if hit:world.register_hit(data.damage)
            return hit
        "attack":
            if not _capability("attack"):return 0
            var options:Dictionary=data.options
            var at:Vector2=world.boss
            if options.get("origin_mode")=="player":at=world.player
            elif options.get("origin_mode")=="world":at=Vector2.ZERO
            at+=options.get("offset",Vector2.ZERO)
            var plan=world.play_barrage(str(data.id),at,0,float(options.get("heading",0)))
            if plan==null:return 0
            plan.follow_enemy=bool(options.get("follow",false)) and options.get("origin_mode","enemy")=="enemy"
            plan.follow_offset=options.get("offset",Vector2.ZERO)
            plan.first_step_duration=step_budget
            return _track(plan,false)
        "behavior":
            if not _capability("attack"):return 0
            var child_flow=world.project.find("behaviors",str(data.id))
            if child_flow==null or not _fits(child_flow):return 0
            var plan=world.play_behavior(str(data.id),behavior.origin_position(),0,behavior.heading,behavior.depth+1)
            if plan==null:return 0
            plan.context.animation_allowed=behavior.animation_allowed
            plan.follow_enemy=bool(data.follow)
            plan.managed=true
            return _track(plan,true)
        "branch","output":
            if not _capability("children"):return 0
            var definition:STGBehaviorFlow
            if key=="branch":
                var index:int=data.index
                if index<0 or index>=node.children.size():return 0
                definition=node.children[index]
            else:
                definition=flow.duplicate(false)
                definition.entry_id=node.target(str(data.port))
            return _spawn(definition,behavior.animation_allowed and bool(data.get("animate",true)))
        "cancel_task":
            var task=_task(int(data.handle))
            if task.is_empty():return false
            if task.structural:task.plan.cancel(bool(data.clear))
            else:task.plan.cancel()
            if data.clear:world.stop_owner(task.plan.owner_id)
            return true
    return null
func _spawn(definition:STGBehaviorFlow,animate:bool) -> int:
    if not _fits(definition):return 0
    if behavior.depth>=32 or behavior.world.behaviors.size()>=256:
        behavior.world.issue="行为超过32层或256个并发任务";return 0
    var child=load("res://stg/runtime/boss/flow_runner.gd").new()
    var data=behavior.child()
    data.owner_id=behavior.world.allocate_owner();data.animation_allowed=animate
    child.start(definition,data);child.managed=true
    behavior.world.behaviors.append(child)
    return _track(child,true)
func _track(plan,structural:bool) -> int:
    var task={"plan":plan,"structural":structural}
    tasks.append(task);owned.append(task)
    behavior.owned_attacks.append(plan.owner_id)
    return owned.size()
func _task(handle:int) -> Dictionary:return owned[handle-1] if handle>0 and handle<=owned.size() else {}
func query(key:String,data):
    var world=behavior.world
    match key:
        "player":return world.player
        "position":return world.boss
        "environment_offset":return world.environment_offset
        "player_velocity":return world.player_velocity
        "hp":return world.hp
        "time":return world.time
        "recent_hit":return world.time-world.boss_last_hit_at
        "cooldown":return world.time-world.action_completed_at.get(str(data),-1000000.0)
        "random":return world.rng.randf_range(data.x,data.y)
        "random_int":return world.rng.randi_range(data.x,data.y)
        "branch_count":return node.children.size()
        "branch_animation":
            if int(data)<0 or int(data)>=node.children.size():return false
            return _has_animation(node.children[int(data)],{})
        "task":
            var task=_task(int(data.handle))
            if task.is_empty():return "failure"
            var plan=task.plan
            if plan.failed or plan.cancelled:return "failure"
            var mode:String=data.mode
            var done:bool
            if mode=="returned" and plan.has_method("returned"):done=plan.returned()
            elif mode=="cleared":done=plan.is_finished(world)
            else:done=plan.emission_finished()
            return "success" if done else "running"
    return null
func _has_animation(value:Resource,visited:Dictionary) -> bool:
    if value==null or visited.has(value.get_instance_id()):return false
    visited[value.get_instance_id()]=true
    if value is STGBehaviorFlow:
        for child in value.nodes:
            var p=child.parameters()
            for key in ["windup_animation","active_animation","recovery_animation"]:
                if not str(p.get(key,"")).is_empty():return true
            for branch in child.children:
                if _has_animation(branch,visited):return true
            if child.behavior_preset!=null and child.behavior_preset.program!=null:
                for reference in child.behavior_preset.program.references(p):
                    if reference.collection=="behaviors" and _has_animation(behavior.world.project.find("behaviors",reference.id),visited):return true
    return false
func cancel(clear_attacks:bool=true) -> void:
    for task in owned:
        if task.structural:task.plan.cancel(clear_attacks)
        else:task.plan.cancel()
        if clear_attacks:behavior.world.stop_owner(task.plan.owner_id)

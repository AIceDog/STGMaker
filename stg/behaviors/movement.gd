@tool
extends STGBehaviorProgram
## 位移算法全部经行为上下文提交；配置单位为设计坐标、秒、度。
var p: Dictionary
var origin: Vector2
var target: Vector2
var direction: Vector2
var velocity: Vector2
var radius: float
var angle: float
var hit: bool = false
func _target(ctx: STGBehaviorContext) -> Vector2:
    var value: Vector2 = p.get("target", Vector2.ZERO)
    if p.get("target_mode","relative") == "player":
        value += ctx.player_position()
        if p.get("aiming","snapshot") == "predict": value += ctx.player_velocity()*p.get("prediction",0.3)
    elif p.get("target_mode","relative") == "relative": value += origin
    else: value += ctx.environment_offset() # 固定目标保留关卡出生与卷轴坐标约定。
    return value
func start(ctx: STGBehaviorContext, parameters: Dictionary) -> void:
    p = parameters
    origin = ctx.enemy_position(); target = _target(ctx)
    direction = (target-origin).normalized()
    if p.get("speed",0.0)>0 and p.mode in ["line","dash"]: target=origin+direction*p.speed*p.execution_duration
    radius=origin.distance_to(target); angle=(origin-target).angle()
    velocity=p.get("initial_velocity",Vector2.ZERO)
    if p.get("velocity_mode","fixed")=="direction": velocity=direction*velocity.length()
    elif p.get("velocity_mode","fixed")=="horizontal": velocity.x=absf(velocity.x)*(-1 if target.x<origin.x else 1)
    if p.mode=="teleport":
        if ctx.set_position(target): ctx.complete()
        return
    if p.execution_duration<=0:ctx.complete();return
    if p.mode=="burrow":
        ctx.set_visibility(not p.get("hide_while_buried",true));ctx.set_invulnerable(p.get("invulnerable_while_buried",true))
func tick(ctx: STGBehaviorContext, dt: float) -> void:
    var duration: float=p.execution_duration
    if duration<=0:ctx.complete();return
    var t=minf(ctx.elapsed(),duration)
    var ratio=clampf(t/duration,0,1)
    var previous=ctx.enemy_position()
    var at:Vector2
    match p.mode:
        "orbit":
            var center=_target(ctx) if p.get("orbit_follow_center",true) and p.target_mode=="player" else target
            var progress:float=p.orbit_progress_curve.sample(ratio) if p.get("orbit_progress_curve")!=null else ratio
            at=center+Vector2.from_angle(angle+TAU*p.orbit_turns*ratio)*lerpf(radius,p.orbit_end_radius,progress)
        "ballistic": at=origin+velocity*t+Vector2(0,p.gravity*t*t/2)
        "curve": at=origin+p.path.sample_baked(p.path.get_baked_length()*ratio,true)-p.path.get_point_position(0)
        _:
            if p.get("aiming","snapshot")=="track" and p.get("target_mode")=="player":
                var desired=_target(ctx)-previous
                if desired.length_squared()>0.000001: direction=direction.rotated(clampf(direction.angle_to(desired),-deg_to_rad(p.turn_speed)*dt,deg_to_rad(p.turn_speed)*dt))
                var step=minf(dt,maxf(0,duration-(ctx.elapsed()-dt)))
                at=previous+direction*(p.speed if p.speed>0 else origin.distance_to(target)/duration)*step
            else: at=origin.lerp(target,ratio)
    if not ctx.set_position(at): return
    if p.get("body_attack",false) and p.mode!="burrow" and not hit:
        hit=ctx.contact_damage(previous,p.body_radius,p.body_damage)
    if ctx.elapsed()+0.000001>=duration: ctx.complete("completed",maxf(0,ctx.elapsed()-duration))
func rebase(displacement:Vector2) -> void:
    origin+=displacement;target+=displacement
func validate_parameters(parameters:Dictionary) -> PackedStringArray:
    if parameters.get("mode")=="curve" and (parameters.get("path")==null or parameters.path.get_point_count()<2 or parameters.path.get_baked_length()<=0):
        return PackedStringArray(["曲线路径需要至少两个不同的点"])
    return []

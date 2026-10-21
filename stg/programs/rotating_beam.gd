@tool
extends STGAttackProgram
var handle: STGAttackHandle
var parameters: Dictionary
func start(ctx: STGAttackContext, p: Dictionary) -> void:
    parameters = p
    handle = ctx.create_beam(ctx.origin(),ctx.origin()+Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle))*p.length,p.width,p.warning+p.duration,STGAttackEntityOptions.from_parameters(p))
    ctx.set_active(handle,false)
func tick(ctx: STGAttackContext, _dt: float) -> void:
    # 内部 Stage：预警 → 扫射。它不是敌人的抬手或收招。
    var active_time = maxf(0,ctx.elapsed()-parameters.warning)
    ctx.set_active(handle,ctx.elapsed()>=parameters.warning)
    var angle = ctx.heading()+deg_to_rad(parameters.angle+parameters.angular_speed*active_time)
    ctx.set_points(handle,PackedVector2Array([ctx.origin(),ctx.origin()+Vector2.from_angle(angle)*parameters.length]))
    if ctx.elapsed()+0.000001>=parameters.warning+parameters.duration: ctx.finish()

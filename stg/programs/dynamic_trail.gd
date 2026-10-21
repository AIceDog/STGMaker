@tool
extends STGAttackProgram
var handle: STGAttackHandle
var parameters: Dictionary
func start(ctx: STGAttackContext,p: Dictionary) -> void:
    parameters = p
    handle = ctx.create_trail(ctx.origin(),p.width,p.duration,p.segment_life,STGAttackEntityOptions.from_parameters(p))
func tick(ctx: STGAttackContext,_dt: float) -> void:
    var t = ctx.elapsed()
    ctx.set_transform(handle,ctx.origin()+Vector2(-parameters.speed*t,sin(t*TAU*parameters.frequency)*parameters.amplitude))
    if t+0.000001>=parameters.duration: ctx.finish()

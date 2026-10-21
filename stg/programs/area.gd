@tool
extends STGAttackProgram
var handle:STGAttackHandle
var p:Dictionary
func start(ctx:STGAttackContext,params:Dictionary) -> void:
 p=params
 var at=ctx.target_position() if p.anchor=="target" else ctx.origin()
 handle=ctx.create_area(at+p.offset,p.warning+p.duration,STGAttackEntityOptions.from_parameters(p));ctx.set_active(handle,p.warning<=0)
func tick(ctx:STGAttackContext,_dt:float) -> void:
 ctx.set_active(handle,ctx.elapsed()>=p.warning)
 if ctx.elapsed()+0.000001>=p.warning+p.duration:ctx.finish()

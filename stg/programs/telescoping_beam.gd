@tool
extends STGAttackProgram
var parameters:Dictionary
var handle:STGAttackHandle
var anchor:Vector2
var direction:Vector2
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p;anchor=ctx.initial_origin();direction=Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle))
 handle=ctx.create_beam(anchor,anchor+direction*p.length,p.width,p.warning+p.extend_time+p.hold_time+p.retract_time,STGAttackEntityOptions.from_parameters(p));ctx.set_active(handle,false)
func tick(ctx:STGAttackContext,_dt:float) -> void:
 var p=parameters;var t=ctx.elapsed()-p.warning;var length=p.length
 if t>=0:
  if t<p.extend_time:length=p.length*t/p.extend_time
  elif t>p.extend_time+p.hold_time:length=p.length*(1.0-clampf((t-p.extend_time-p.hold_time)/p.retract_time,0,1))
 ctx.set_points(handle,PackedVector2Array([anchor,anchor+direction*maxf(.01,length)]))
 ctx.set_active(handle,t>=0 and length>.01)
 if t+.000001>=p.extend_time+p.hold_time+p.retract_time:ctx.finish()

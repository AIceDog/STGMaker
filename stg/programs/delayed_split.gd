@tool
extends STGAttackProgram
## 核心先移动再停留；分裂后由正式实体继续直飞，取消不生成后继。
var parameters:Dictionary
var core:STGAttackHandle
var anchor:Vector2
var direction:Vector2
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p;anchor=ctx.initial_origin();direction=Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle))
 core=ctx.spawn_body(anchor,Vector2.ZERO,p.travel_time+p.pause_time+.05,null,STGAttackEntityOptions.from_parameters(p))
 ctx.set_active(core,false)
func tick(ctx:STGAttackContext,_dt:float) -> void:
 if not ctx.valid(core):ctx.finish();return
 var p=parameters;var at=anchor+direction*p.travel_speed*minf(ctx.elapsed(),p.travel_time)
 ctx.set_transform(core,at,direction.angle())
 if ctx.elapsed()+.000001<p.travel_time+p.pause_time:return
 ctx.destroy(core)
 for i in int(p.count):
  var angle=direction.angle()+TAU*i/p.count
  ctx.spawn_body(at,Vector2.from_angle(angle)*p.child_speed,p.child_life,null,STGAttackEntityOptions.from_parameters(p))
 ctx.finish()

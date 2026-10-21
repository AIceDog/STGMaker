@tool
extends STGAttackProgram
var parameters:Dictionary
var handles:Array[STGAttackHandle]=[]
var anchor:Vector2
var target:Vector2
var last_pulse:int=-1
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p;anchor=ctx.initial_origin();target=ctx.target_position()
 if target.distance_squared_to(anchor)<1:target=anchor+Vector2.LEFT*100
 var seconds=p.warning+p.pulses*p.active_time+(p.pulses-1)*p.gap
 for i in int(p.branches)+1:
  var handle=ctx.create_polyline(PackedVector2Array([anchor,target]),p.width*(1.0 if i==0 else .65),seconds,STGAttackEntityOptions.from_parameters(p))
  handles.append(handle);ctx.set_active(handle,false)
 geometry(ctx)
func geometry(ctx:STGAttackContext) -> void:
 var p=parameters;var delta=target-anchor;var normal=delta.normalized().orthogonal();var points=PackedVector2Array()
 for i in int(p.points):
  var fraction=float(i)/(p.points-1)
  points.append(anchor+delta*fraction+normal*(0.0 if i==0 or i==p.points-1 else ctx.random_range(-p.jitter,p.jitter)))
 ctx.set_points(handles[0],points)
 for i in int(p.branches):
  var start=points[clampi(roundi(float(i+1)*points.size()/(p.branches+1)),1,points.size()-2)]
  var side=-1 if i%2 else 1
  var end=start+delta.normalized().rotated(side*deg_to_rad(p.branch_angle))*delta.length()*p.branch_length
  ctx.set_points(handles[i+1],PackedVector2Array([start,(start+end)*.5+normal*ctx.random_range(-p.jitter,p.jitter),end]))
func tick(ctx:STGAttackContext,_dt:float) -> void:
 var p=parameters;var t=ctx.elapsed()-p.warning;var period=p.active_time+p.gap
 var pulse=maxi(0,floori(t/period));var active=t>=0 and pulse<p.pulses and fposmod(t,period)<p.active_time
 if active and pulse!=last_pulse:geometry(ctx);last_pulse=pulse
 for handle in handles:ctx.set_active(handle,active)
 if t+.000001>=p.pulses*p.active_time+(p.pulses-1)*p.gap:ctx.finish()
func cancel(_reason:String) -> void:handles.clear()

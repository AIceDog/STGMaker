@tool
extends "res://stg/programs/tracked_bodies.gd"
var anchor:Vector2
var direction:Vector2
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p;anchor=ctx.initial_origin();direction=Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle))
 body(ctx,anchor,direction,p.out_time+p.return_time)
func tick(ctx:STGAttackContext,_dt:float) -> void:
 var t=ctx.elapsed();var entry=bodies[0]
 if ctx.valid(entry.handle):
  var distance=parameters.speed*minf(t,parameters.out_time)
  if t>parameters.out_time:distance=parameters.speed*parameters.out_time*(1.0-clampf((t-parameters.out_time)/parameters.return_time,0,1))
  place(ctx,entry,anchor+direction*distance,direction.angle()+deg_to_rad(parameters.spin)*t)
 settle(ctx,parameters.out_time+parameters.return_time)

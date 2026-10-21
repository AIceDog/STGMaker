@tool
extends "res://stg/programs/tracked_bodies.gd"
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p
 for i in int(p.count):
  var spread=0.0 if p.count==1 else (float(i)/(p.count-1)-.5)*p.spread
  var direction=Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle+spread))
  body(ctx,ctx.initial_origin(),direction,p.travel_time+p.pause_time+p.flight_time)
func tick(ctx:STGAttackContext,_dt:float) -> void:
 var p=parameters;var t=ctx.elapsed();var launch=p.travel_time+p.pause_time
 for entry in bodies:
  if not ctx.valid(entry.handle):continue
  var at=entry.origin+entry.direction*p.travel_speed*minf(t,p.travel_time)
  var facing=entry.direction
  if t>=launch:
   if not entry.has("aim"):
    var delta=ctx.target_position()-at
    entry.aim=delta.normalized() if delta.length_squared()>.000001 else entry.direction
   facing=entry.aim;at+=facing*p.flight_speed*(t-launch)
  place(ctx,entry,at,facing.angle())
 settle(ctx,launch+p.flight_time)

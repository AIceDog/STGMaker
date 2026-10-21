@tool
extends "res://stg/programs/tracked_bodies.gd"
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p;var direction=Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle));var normal=direction.orthogonal()
 for i in int(p.count):
  var entry=body(ctx,ctx.initial_origin()+normal*p.spacing*(i-(p.count-1)*.5),direction,p.duration)
  entry.phase=deg_to_rad(p.phase_step)*i
func tick(ctx:STGAttackContext,_dt:float) -> void:
 var p=parameters;var t=ctx.elapsed();var angular=TAU*p.frequency
 for entry in bodies:
  if not ctx.valid(entry.handle):continue
  var normal=entry.direction.orthogonal();var phase=t*angular+entry.phase
  var at=entry.origin+entry.direction*p.speed*t+normal*p.amplitude*(sin(phase)-sin(entry.phase))
  var tangent=entry.direction*p.speed+normal*p.amplitude*angular*cos(phase)
  place(ctx,entry,at,tangent.angle())
 settle(ctx,p.duration)

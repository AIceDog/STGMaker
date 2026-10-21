@tool
extends "res://stg/programs/tracked_bodies.gd"
const Space=preload("res://stg/definitions/combat_space.gd")
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p
 for i in int(p.count):
  var spread=0.0 if p.count==1 else (float(i)/(p.count-1)-.5)*p.spread
  var direction=Vector2.from_angle(ctx.heading()+deg_to_rad(p.angle+spread))
  var entry=body(ctx,ctx.initial_origin(),direction,p.duration);entry.velocity=direction*p.speed;entry.bounces=0
func tick(ctx:STGAttackContext,dt:float) -> void:
 var bounds=Space.BOUNDS.grow(-parameters.margin)
 for entry in bodies:
  if not ctx.valid(entry.handle):continue
  var at=entry.position+entry.velocity*dt
  for axis in 2:
   if at[axis]<bounds.position[axis]:at[axis]=2*bounds.position[axis]-at[axis];entry.velocity[axis]*=-1;entry.bounces+=1
   elif at[axis]>bounds.end[axis]:at[axis]=2*bounds.end[axis]-at[axis];entry.velocity[axis]*=-1;entry.bounces+=1
  if entry.bounces>parameters.bounces:ctx.destroy(entry.handle);continue
  place(ctx,entry,at,entry.velocity.angle())
 settle(ctx,parameters.duration)

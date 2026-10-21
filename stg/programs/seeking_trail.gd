@tool
extends STGAttackProgram
var parameters:Dictionary
var handle:STGAttackHandle
var location:Vector2
var direction:Vector2
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p;location=ctx.initial_origin();direction=(ctx.target_position()-location).normalized()
 if direction==Vector2.ZERO:direction=Vector2.LEFT
 handle=ctx.create_trail(location,p.width,p.duration,p.segment_life,STGAttackEntityOptions.from_parameters(p))
func tick(ctx:STGAttackContext,dt:float) -> void:
 var delta=ctx.target_position()-location
 if delta.length_squared()>.000001:direction=direction.rotated(clampf(direction.angle_to(delta),-deg_to_rad(parameters.turn_rate)*dt,deg_to_rad(parameters.turn_rate)*dt))
 location+=direction*parameters.speed*dt;ctx.set_transform(handle,location,direction.angle())
 if ctx.elapsed()+.000001>=parameters.duration:ctx.finish()

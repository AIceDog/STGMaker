@tool
extends STGAttackEntityProgram
var speed: float
var turn_rate: float
func start(_ctx: STGAttackEntityContext, p: Dictionary) -> void:
	speed = p.speed; turn_rate = deg_to_rad(p.turn_rate)
func tick(ctx: STGAttackEntityContext, dt: float) -> void:
	var desired = ctx.target_position() - ctx.position()
	if desired.length_squared() < 0.0001: return
	var current = ctx.velocity().angle()
	var difference = wrapf(desired.angle()-current, -PI, PI)
	ctx.set_velocity(Vector2.from_angle(current+clampf(difference,-turn_rate*dt,turn_rate*dt))*speed)

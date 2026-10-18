@tool
extends STGPlayerExtension
var remaining: float = 0
var interval: float = 0.18
func start(_context: STGPlayerContext, parameters: Dictionary) -> void:
	interval = float(parameters.get("interval", 0.18))
func tick(context: STGPlayerContext, dt: float) -> void:
	remaining = maxf(0, remaining - dt)
	if context.firing and remaining <= 0:
		for angle in [-0.12, 0.0, 0.12]: context.shoot(Vector2.from_angle(angle))
		remaining = interval

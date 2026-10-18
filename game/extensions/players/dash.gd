@tool
extends STGPlayerExtension
var remaining: float = 0
var was_pressed: bool = false
var distance: float = 75
var cooldown: float = 0.8
func start(_context: STGPlayerContext, parameters: Dictionary) -> void:
	distance = float(parameters.get("distance", 75))
	cooldown = float(parameters.get("cooldown", 0.8))
func tick(context: STGPlayerContext, dt: float) -> void:
	remaining = maxf(0, remaining - dt)
	if context.using_ability and not was_pressed and remaining <= 0:
		var direction = context.movement_input.normalized()
		context.move((Vector2.RIGHT if direction.is_zero_approx() else direction) * distance)
		remaining = cooldown
	was_pressed = context.using_ability

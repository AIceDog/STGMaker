@tool
extends STGMotionExtension
## 使用解析位移，固定步长和不同帧率下结果一致；速度倍率由发射步骤统一提供。
var origin: Vector2
var direction: Vector2
var initial_speed: float
var acceleration: float
var speed_multiplier: float

func start(context: STGMotionContext, parameters: Dictionary) -> void:
	origin = context.origin()
	direction = Vector2.from_angle(context.heading())
	initial_speed = float(parameters.initial_speed)
	acceleration = float(parameters.acceleration)
	speed_multiplier = context.speed_scale()

func tick(context: STGMotionContext, _dt: float) -> void:
	var elapsed = context.elapsed()
	context.set_position(origin + direction * (initial_speed * elapsed + 0.5 * acceleration * elapsed * elapsed) * speed_multiplier)

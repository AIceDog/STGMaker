@tool
extends STGEmissionExtension
const RingMath = preload("ring_math.gd")
## 一轮分批生成一圈弹丸，展示跨帧发射与每轮独立状态。
var emitted: int = 0
var count: int = 12
var spacing: float = 0.04
var radius: float = 20

func start(context: STGEmissionContext, parameters: Dictionary) -> void:
	count = int(parameters.get("count", 12))
	spacing = float(parameters.get("spacing", 0.04))
	radius = float(parameters.get("radius", 20))
	_emit_due(context)

func tick(context: STGEmissionContext, _dt: float) -> void:
	_emit_due(context)

func _emit_due(context: STGEmissionContext) -> void:
	while emitted < count and context.elapsed() + 0.000001 >= emitted * spacing:
		var angle = context.heading() + RingMath.angle(emitted, count) + context.round_index * 0.2
		context.emit(context.origin() + Vector2.from_angle(angle) * radius, angle)
		emitted += 1
	if emitted >= count: context.finish()

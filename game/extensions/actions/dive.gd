@tool
extends STGActionExtension
## 特殊动作通过公开上下文移动和调用招式，不访问 Simulation、节点或流程运行器。
var start_position: Vector2
var destination: Vector2
var duration: float = 0.8
var skill: String = ""

func start(context: STGActionContext, parameters: Dictionary) -> void:
	start_position = context.position()
	destination = start_position + Vector2(-120, parameters.get("vertical", 80.0))
	duration = float(parameters.get("duration", 0.8))
	skill = str(parameters.get("skill", ""))
	if not skill.is_empty(): context.play_barrage(skill, start_position)

func tick(context: STGActionContext, _dt: float) -> void:
	var progress = minf(1, context.elapsed() / duration)
	context.set_position(start_position.lerp(destination, smoothstep(0, 1, progress)))
	if progress >= 1: context.finish()

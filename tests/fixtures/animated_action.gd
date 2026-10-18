@tool
extends STGActionExtension
## 独立脚本夹具与技术策划模块使用同样的载入方式。
var cancellations: Array[String] = []
func start(context: STGActionContext, _parameters: Dictionary) -> void:
	context.play_animation("probe")
func tick(context: STGActionContext, _dt: float) -> void:
	if context.elapsed() >= 0.2: context.finish()
func cancel(reason: String) -> void:
	cancellations.append(reason)

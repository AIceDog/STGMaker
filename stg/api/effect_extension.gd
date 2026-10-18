@tool
class_name STGEffectExtension
extends STGExtension
## 命中效果同步执行；需要跨帧的招式通过 play_barrage 请求运行器调度。
func apply(_context: STGEffectContext, _parameters: Dictionary) -> void:
	pass

func start(context: STGEffectContext, parameters: Dictionary) -> void:
	apply(context, parameters)
	context.finish()

func tick(_context: STGEffectContext, _dt: float) -> void:
	pass

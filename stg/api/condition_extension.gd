@tool
class_name STGConditionExtension
extends STGExtension
## 条件是同步只读查询；运行器进入节点时调用一次 evaluate。
func evaluate(_context: STGConditionContext, _parameters: Dictionary) -> bool:
	return false

func start(context: STGConditionContext, parameters: Dictionary) -> void:
	context.resolve(evaluate(context, parameters))

func tick(_context: STGConditionContext, _dt: float) -> void:
	pass

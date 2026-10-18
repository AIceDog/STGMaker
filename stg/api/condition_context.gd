@tool
class_name STGConditionContext
extends STGExtensionContext
## 条件上下文没有生成、移动、伤害接口。
var result: bool = false

func resolve(value: bool) -> void:
	if not active(): return
	result = value
	finish()

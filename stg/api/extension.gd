@tool
class_name STGExtension
extends RefCounted
## SDK v1 公共基类。每次执行创建一个对象；共享声明中禁止保存计时器和目标。
## 各能力子类声明对应的 start/tick 上下文；cancel 在一次执行中最多调用一次。
func cancel(_reason: String) -> void:
	pass

func validate_parameters(_parameters: Dictionary) -> PackedStringArray:
	return []

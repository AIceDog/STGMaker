@tool
class_name STGPlayerExtension
extends STGExtension
## controller / weapon / ability 三个独立实例，按此顺序更新；暂停不 tick，离开战斗取消。
func start(_context: STGPlayerContext, _parameters: Dictionary) -> void:
	pass

func tick(_context: STGPlayerContext, _dt: float) -> void:
	pass

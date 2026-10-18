@tool
class_name STGMotionExtension
extends STGExtension
## SDK v1：继承此类实现自定义子弹运动。每次进入阶段都创建一个新对象。
## parameters 是该实例的深拷贝；资源里的参数不会被运行状态污染。
func start(_context: STGMotionContext, _parameters: Dictionary) -> void:
	pass

func tick(_context: STGMotionContext, _dt: float) -> void:
	pass



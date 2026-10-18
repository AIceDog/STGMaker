@tool
class_name STGActionExtension
extends STGExtension
## 一个角色动作一个实例。通过上下文移动、发招；完成或失败时调用 finish(success)。
func start(_context: STGActionContext, _parameters: Dictionary) -> void:
	pass

func tick(_context: STGActionContext, _dt: float) -> void:
	pass

## 宿主发生卷轴位移时同步实现内部缓存；已发子弹由各自实例保持坐标。
func rebase(_displacement: Vector2) -> void:
	pass

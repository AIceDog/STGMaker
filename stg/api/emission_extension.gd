@tool
class_name STGEmissionExtension
extends STGExtension
## 一轮发射一个实例；start 可立即发射，tick 可延迟/分批发射，完成后调用 context.finish()。
func start(_context: STGEmissionContext, _parameters: Dictionary) -> void:
	pass

func tick(_context: STGEmissionContext, _dt: float) -> void:
	pass

@tool
class_name STGAttackProgram
extends STGExtension
## 每次释放一个实例。内部阶段由代码组织；配置声明不保存运行状态。
func start(_context: STGAttackContext, _parameters: Dictionary) -> void: pass
func tick(_context: STGAttackContext, _dt: float) -> void: pass

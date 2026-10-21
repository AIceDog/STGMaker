@tool
class_name STGAttackEntityProgram
extends STGExtension
## 每个实体独立执行的程序；上下文仅允许修改自身。
func start(_context: STGAttackEntityContext, _parameters: Dictionary) -> void: pass
func tick(_context: STGAttackEntityContext, _dt: float) -> void: pass

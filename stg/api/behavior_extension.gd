@tool
class_name STGBehaviorProgram
extends STGExtension
## 所有行为程序唯一契约；瞬时节点可在 start 中完成。参数不得保存运行状态。
func start(_context: STGBehaviorContext, _parameters: Dictionary) -> void: pass
func tick(_context: STGBehaviorContext, _dt: float) -> void: pass
## tick 的 dt=0 仅结算任务结果，不推进时间；所有程序使用同一入口处理精确预算边界。
func settle(context:STGBehaviorContext) -> void:tick(context,0.0)
func rebase(_displacement: Vector2) -> void: pass

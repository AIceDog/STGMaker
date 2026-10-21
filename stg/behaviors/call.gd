@tool
extends STGBehaviorProgram
var handle: int
var mode: String
func start(ctx: STGBehaviorContext, p: Dictionary) -> void:
    mode = p.wait_mode
    handle = ctx.call_behavior(p.behavior_id, p.follow_enemy)
    if handle == 0: ctx.fail("无法启动引用的行为子流程")
    elif mode == "immediate": ctx.complete()
func tick(ctx: STGBehaviorContext, _dt: float) -> void:
    var state = ctx.task_state(handle, mode)
    if state == "success": ctx.complete()
    elif state == "failure": ctx.fail("行为子流程执行失败")


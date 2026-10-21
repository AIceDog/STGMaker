@tool
extends STGBehaviorProgram
var handle: int
var mode: String
func start(ctx: STGBehaviorContext, p: Dictionary) -> void:
    mode = p.wait_mode
    handle = ctx.call_attack(p.barrage_id, {"follow":p.follow_enemy,"origin_mode":p.origin_mode,"offset":p.offset,"heading":deg_to_rad(p.heading)})
    if handle == 0: ctx.fail("无法启动引用的招式")
    elif mode == "immediate": ctx.complete()
func tick(ctx: STGBehaviorContext, _dt: float) -> void:
    var state = ctx.task_state(handle, mode)
    if state == "success": ctx.complete()
    elif state == "failure": ctx.fail("招式执行失败")


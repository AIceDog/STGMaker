@tool
extends STGBehaviorProgram
var order: Array[int] = []
var cursor: int = 0
var handle: int = 0
func start(ctx: STGBehaviorContext, p: Dictionary) -> void:
    for i in int(p.branches): order.append(i)
    for i in range(order.size()-1, 0, -1):
        var other = ctx.random_integer(0,i)
        var saved = order[i]; order[i] = order[other]; order[other] = saved
    _next(ctx)
func _next(ctx: STGBehaviorContext) -> void:
    if cursor >= order.size(): ctx.complete("failure"); return
    handle = ctx.start_output("choice_%d" % order[cursor])
    if handle == 0: ctx.fail("随机分支启动失败")
func tick(ctx: STGBehaviorContext, _dt: float) -> void:
    var state = ctx.task_state(handle)
    if state == "success": ctx.complete()
    elif state == "failure":
        cursor += 1
        _next(ctx)


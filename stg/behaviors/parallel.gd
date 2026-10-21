@tool
extends STGBehaviorProgram
var handles: Array[int] = []
func start(ctx: STGBehaviorContext, p: Dictionary) -> void:
    var count = ctx.branch_count()
    if count == 0: ctx.fail("并行节点至少需要一个分支"); return
    var owner: int = p.animation_branch
    if owner >= count: ctx.fail("动画控制分支不存在"); return
    if owner < 0:
        for i in count:
            if ctx.branch_has_animation(i):
                if owner >= 0: ctx.fail("多个并行分支配置身体动画，请指定动画控制分支"); return
                owner = i
    for i in count:
        var task = ctx.start_branch(i, i == owner)
        if task == 0: ctx.fail("并行分支启动失败"); return
        handles.append(task)
func tick(ctx: STGBehaviorContext, _dt: float) -> void:
    var done = true
    var success = true
    for handle in handles:
        var state = ctx.task_state(handle)
        done = done and state != "running"
        success = success and state != "failure"
    if done: ctx.complete("completed" if success else "failure")


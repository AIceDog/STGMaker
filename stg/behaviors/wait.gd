@tool
extends STGBehaviorProgram
## 等待由公共定长宿主计时，不再保存另一份等待秒数。
func start(ctx:STGBehaviorContext,_p:Dictionary) -> void:ctx.complete()

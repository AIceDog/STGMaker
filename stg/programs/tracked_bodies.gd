@tool
extends STGAttackProgram
## 手动运动程序共用的句柄记录；世界坐标/秒，所有状态仅属于本次释放。
var parameters:Dictionary
var bodies:Array[Dictionary]=[]
func body(ctx:STGAttackContext,at:Vector2,direction:Vector2,seconds:float) -> Dictionary:
 var entry={"handle":ctx.spawn_body(at,Vector2.ZERO,seconds,null,STGAttackEntityOptions.from_parameters(parameters)),"origin":at,"position":at,"direction":direction}
 bodies.append(entry);return entry
func place(ctx:STGAttackContext,entry:Dictionary,at:Vector2,angle:float) -> void:
 entry.position=at
 ctx.set_transform(entry.handle,at,angle)
func settle(ctx:STGAttackContext,seconds:float) -> void:
 if ctx.elapsed()+.000001>=seconds or bodies.all(func(entry):return not ctx.valid(entry.handle)):ctx.finish()
func cancel(_reason:String) -> void:bodies.clear()

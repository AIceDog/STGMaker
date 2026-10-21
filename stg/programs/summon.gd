@tool
extends STGAttackProgram
var p:Dictionary
var emitted:int=0
func start(ctx:STGAttackContext,params:Dictionary) -> void:p=params;_emit(ctx)
func tick(ctx:STGAttackContext,_dt:float) -> void:_emit(ctx)
func _emit(ctx:STGAttackContext) -> void:
 while emitted<int(p.count) and emitted*p.interval<=ctx.elapsed()+0.000001 and ctx.active():
  ctx.spawn_enemy(ctx.origin()+p.offset,p.duration,p.entry_velocity,p.entry_duration);emitted+=1
 if emitted==int(p.count):ctx.finish()

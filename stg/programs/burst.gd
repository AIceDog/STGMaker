@tool
extends STGAttackProgram
## 基础齐射/分组调度辅助。参数由每个具体程序声明，事件按实际时刻排序。
var parameters:Dictionary
var events:Array=[]
var index:int=0
func start(ctx:STGAttackContext,p:Dictionary) -> void:
 parameters=p
 for round_index in int(p.rounds):
  for shot in int(p.count):
   var batch=0 if p.group_size==0 else shot/int(p.group_size)
   events.append({"time":round_index*p.interval+batch*p.group_interval,"shot":shot,"serial":round_index*int(p.count)+shot})
 events.sort_custom(func(a,b):return a.time<b.time if a.time!=b.time else a.serial<b.serial)
 _emit_due(ctx)
func tick(ctx:STGAttackContext,_dt:float) -> void:_emit_due(ctx)
func _emit_due(ctx:STGAttackContext) -> void:
 while index<events.size() and events[index].time<=ctx.elapsed()+0.000001 and ctx.active():
  var event=events[index];var angle=shot_angle(ctx,event)
  ctx.spawn_body(shot_origin(ctx,event),Vector2.from_angle(angle)*parameters.speed,parameters.duration,null,STGAttackEntityOptions.from_parameters(parameters))
  index+=1
 if index==events.size():ctx.finish()
func shot_angle(ctx:STGAttackContext,_event:Dictionary) -> float:return ctx.heading()+deg_to_rad(parameters.angle)
func shot_origin(ctx:STGAttackContext,_event:Dictionary) -> Vector2:return ctx.origin()
func validate_parameters(p:Dictionary) -> PackedStringArray:
 return PackedStringArray(["单次发射计划最多4096颗"]) if p.get("count",1)*p.get("rounds",1)>4096 else PackedStringArray()

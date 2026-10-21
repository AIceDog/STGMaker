@tool
extends STGAttackProgram
const ENTITY = preload("res://stg/programs/homing_entity.tres")
func start(ctx: STGAttackContext, p: Dictionary) -> void:
    for i in int(p.count):
        var fraction = 0.0 if p.count==1 else float(i)/(p.count-1)-0.5
        var angle = (ctx.target_position()-ctx.origin()).angle()+deg_to_rad(fraction*p.spread)
        var binding = STGExtensionBinding.create(ENTITY)
        binding.parameters = {"speed":p.speed,"turn_rate":p.turn_rate}
        ctx.spawn_body(ctx.origin(),Vector2.from_angle(angle)*p.speed,p.duration,binding,STGAttackEntityOptions.from_parameters(p))
    ctx.finish()
func tick(_ctx: STGAttackContext, _dt: float) -> void: pass

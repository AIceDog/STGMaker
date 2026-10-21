@tool
extends STGAttackProgram
var duration: float
func start(ctx: STGAttackContext, p: Dictionary) -> void:
    duration = p.duration
    var a = ctx.origin()
    var b = ctx.target_position()
    var normal = (b-a).normalized().orthogonal()
    var points = PackedVector2Array()
    for i in int(p.points):
        var point = a.lerp(b,float(i)/(p.points-1))
        if i>0 and i<p.points-1: point += normal*ctx.random_range(-p.jitter,p.jitter)
        points.append(point)
    ctx.create_polyline(points,p.width,duration,STGAttackEntityOptions.from_parameters(p))
func tick(ctx: STGAttackContext, _dt: float) -> void:
    if ctx.elapsed()+0.000001>=duration: ctx.finish()

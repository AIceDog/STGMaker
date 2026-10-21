@tool
extends STGBulletTrailActor
## 复用正式拖尾采样、段寿命、贴图与碰撞；发射点由受控程序更新。
var driver_position: Vector2
var velocity: Vector2
var lifetime: float = 1
var damaging: bool = true
func program_position() -> Vector2: return driver_position
func program_set_transform(at: Vector2, _angle: float) -> void: driver_position = at
func program_set_width(value: float) -> void:
    var ratio = definition.collision.size.y / maxf(0.001, definition.visual.geometry.size.y)
    definition.visual.geometry.size.y = value
    definition.collision.size.y = value * ratio
    collision = Collision.for_geometry(definition.collision)
func tick(world, dt: float) -> void:
    if not alive or static_preview: return
    if first_step_duration >= 0: dt = minf(dt, first_step_duration); first_step_duration = -1
    age += dt
    driver_position += velocity * dt
    if not driver_position.is_finite() or driver_position.length()>1000000:
        world.issue="程序拖尾坐标超出安全范围"; stop(); return
    recording = age < lifetime
    if recording: _sample(driver_position)
    if damaging: _tick_segments(world)
    else:
        for i in range(segments.size()-1,-1,-1):
            if age-segments[i].born >= segment_life: segments.remove_at(i)
    if not recording and segments.is_empty(): _expire(world)
    queue_redraw()

func _expire(world) -> void:
    world.present_program_event(lifecycle,"expire",last_emitter,rotation,true,owner_id)
    _emit_successor(world,lifecycle.on_expire_barrage_id,lifecycle.on_expire_behavior_id,last_emitter)
    if definition.visual.expire_clip!=null:world.present_material_expire(self)
    stop()

@tool
extends STGBulletActor
## 程序只提交几何；这个正式实体负责运动扫掠、命中、表现与有限寿命。
var velocity: Vector2
var pending_position: Vector2
var has_pending: bool = false
var points = PackedVector2Array()
var width: float = 16
var lifetime: float = 1
var damaging: bool = true
var entity_session
var ribbon: Line2D
func program_position() -> Vector2: return pending_position if has_pending else position
func program_set_transform(at: Vector2, angle: float) -> void:
    if capability in ["Beam2D", "Polyline2D"]:
        var pivot = program_position()
        for i in points.size(): points[i] = at + (points[i]-pivot).rotated(angle-rotation)
    pending_position = at; has_pending = true; rotation = angle
func program_set_width(value: float) -> void: width = value
func tick(world, dt: float) -> void:
    if not alive or static_preview: return
    if first_step_duration >= 0: dt = minf(dt, first_step_duration); first_step_duration = -1
    previous = position
    age += dt
    if entity_session != null:
        entity_session.tick(dt)
        if entity_session.failed: world.issue = "实体程序执行失败"; stop(); return
    if not alive or static_preview: return
    if has_pending: position = pending_position; has_pending = false
    else:
        position += velocity * dt
        if capability in ["Beam2D", "Polyline2D"]:
            for i in points.size(): points[i] += position-previous
    if not position.is_finite() or position.length()>1000000:
        world.issue="程序实体坐标超出安全范围"; stop(); return
    var can_hit = age >= next_hit_at if lifecycle.hit_mode == "repeat" else not hit_once and (lifecycle.hit_mode == "persistent" or not activation_checked)
    if damaging:
        activation_checked = true
        if can_hit and _program_hits(world.player, world.player_radius):
            hit_once = true; next_hit_at = age + lifecycle.hit_interval
            preload("res://stg/runtime/extensions/hit_effects.gd").apply(self, world, _contact_damage(world.player))
            world.present_program_event(lifecycle,"hit",position,rotation,true,owner_id)
            if definition.visual.hit_clip != null or definition.hit_particles != null: world.present_material_hit(self)
            _emit_successor(world, lifecycle.on_hit_barrage_id, lifecycle.on_hit_behavior_id)
            if capability == "Body2D" and lifecycle.hit_mode != "repeat": stop()
    if alive and (age + 0.000001 >= lifetime or _crossed_exit()): _expire(world)
    queue_redraw()
func _program_hits(at: Vector2, radius: float) -> bool:
    if capability in ["Body2D", "Area2D"]: return collision.hits(self, at, radius)
    var hit_width = width * definition.collision.size.y / maxf(0.001, definition.visual.geometry.size.y)
    for i in range(1, points.size()):
        var a = points[i-1] + definition.collision.offset.rotated(rotation)
        var b = points[i] + definition.collision.offset.rotated(rotation)
        if at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)) <= radius + hit_width/2: return true
    return false
func _draw() -> void:
    if capability in ["Body2D", "Area2D"]:
        super._draw(); return
    if points.size() < 2: return
    if ribbon == null:
        ribbon = Line2D.new(); ribbon.antialiased = true; ribbon.texture_mode = Line2D.LINE_TEXTURE_STRETCH
        add_child(ribbon)
    var local = PackedVector2Array()
    for point in points: local.append((point-position).rotated(-rotation) + definition.visual.geometry.offset)
    ribbon.points = local
    ribbon.width = width
    var color = definition.visual.color
    if not damaging: color.a *= 0.25
    ribbon.default_color = color
    ribbon.texture = current_texture() if definition.visual.mode == "texture" else null
    if show_collision:
        var debug_points = PackedVector2Array()
        for point in points: debug_points.append((point-position).rotated(-rotation)+definition.collision.offset)
        draw_polyline(debug_points, Color(1,0.2,0.5,0.3), width*definition.collision.size.y/maxf(0.001,definition.visual.geometry.size.y), true)
func stop() -> void:
    if is_instance_valid(run_presentation):run_presentation.stop()
    if entity_session != null: entity_session.cancel("stopped")
    super.stop()
func _exit_tree() -> void:
    if entity_session != null: entity_session.cancel("removed")
    super._exit_tree()

func _expire(world) -> void:
    world.present_program_event(lifecycle,"expire",position,rotation,true,owner_id)
    _emit_successor(world,lifecycle.on_expire_barrage_id,lifecycle.on_expire_behavior_id)
    if definition.visual.expire_clip != null: world.present_material_expire(self)
    stop()

func opacity() -> float:return 1.0 if damaging else .25

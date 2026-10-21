@tool
extends RefCounted
## 尾迹在战斗坐标中绘制；宽度/颜色/贴图属于素材，时钟和淡出属于招式实例。
static func draw(actor) -> void:
    var config: STGBulletDefinition = actor.definition
    var visual = config.visual
    var geometry = visual.geometry
    for i in actor.segments.size():
        var part = actor.segments[i]
        var age: float = actor.age - part.born
        var alpha: float = actor.segment_opacity(age)
        var width = geometry.size.y * 1.0
        if width <= 0 or alpha <= 0: continue
        var color = visual.color
        color.a *= alpha
        var endpoints = geometry.trail_endpoints(part.a, part.b)
        var a = endpoints[0]
        var b = endpoints[1]
        var direction = b - a
        var normal = direction.normalized().orthogonal() * width / 2
        var start_normal = normal
        var end_normal = normal
        var previous = actor.segments[i - 1] if i > 0 else null
        var next = actor.segments[i + 1] if i + 1 < actor.segments.size() else null
        var connected_before = previous != null and geometry.trail_endpoints(previous.a, previous.b)[1].is_equal_approx(a)
        var connected_after = next != null and b.is_equal_approx(geometry.trail_endpoints(next.a, next.b)[0])
        if connected_before: start_normal = _join(actor, previous, part)
        if connected_after: end_normal = _join(actor, part, next)
        var polygon = PackedVector2Array([a + start_normal, b + end_normal, b - end_normal, a - start_normal])
        if visual.mode == "geometry" and geometry.kind != "rectangle":
            _geometry_segment(actor, part, geometry, width, color)
        elif visual.mode == "geometry" or actor.current_texture()==null:
            _strip(actor, polygon, color)
            if not connected_before: _cap(actor, a, -direction.normalized(), width / 2, color)
            if not connected_after: _cap(actor, b, direction.normalized(), width / 2, color)
        else:
            var u = part.distance / maxf(1, actor.current_texture().get_width())
            var end_u = u + direction.length() / maxf(1, actor.current_texture().get_width())
            _strip(actor, polygon, color, PackedVector2Array([Vector2(u, 0), Vector2(end_u, 0), Vector2(end_u, 1), Vector2(u, 1)]), actor.current_texture())
        if actor.show_collision and actor.is_active(age):
            var collision_ends = config.collision.trail_endpoints(part.a, part.b)
            actor.draw_line(collision_ends[0], collision_ends[1], Color(1, 0.25, 0.5, 0.35), actor.collision_radius(age) * 2, true)

static func _geometry_segment(actor, part: Dictionary, geometry: STGBulletGeometry, width: float, color: Color) -> void:
    var placement = Transform2D((part.b - part.a).angle(), (part.a + part.b) / 2) * geometry.local_transform()
    actor.draw_set_transform_matrix(placement)
    var outline = geometry.outline()
    for i in outline.size(): outline[i] *= Vector2(part.a.distance_to(part.b), width / geometry.size.y)
    if geometry.kind == "ring":
        for i in outline.size():
            var a = outline[i]
            var b = outline[(i + 1) % outline.size()]
            actor.draw_colored_polygon(PackedVector2Array([a, b, b * geometry.inner_ratio, a * geometry.inner_ratio]), color)
    elif not Geometry2D.triangulate_polygon(outline).is_empty(): actor.draw_colored_polygon(outline, color)
    actor.draw_set_transform(Vector2.ZERO)

static func _strip(actor, points: PackedVector2Array, color: Color, uv: PackedVector2Array = PackedVector2Array(), texture: Texture2D = null) -> void:
    # 急转弯的四边形允许交叉，显式分成三角形避免自动三角化失败。
    for indices in [[0, 1, 2], [0, 2, 3]]:
        var triangle = PackedVector2Array([points[indices[0]], points[indices[1]], points[indices[2]]])
        if absf((triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])) < 0.000001: continue
        if texture == null: actor.draw_colored_polygon(triangle, color)
        else: actor.draw_polygon(triangle, PackedColorArray([color]), PackedVector2Array([uv[indices[0]], uv[indices[1]], uv[indices[2]]]), texture)

static func _join(actor, before: Dictionary, after: Dictionary) -> Vector2:
    var geometry = actor.definition.visual.geometry
    var before_ends = geometry.trail_endpoints(before.a, before.b)
    var after_ends = geometry.trail_endpoints(after.a, after.b)
    var a = (before_ends[1] - before_ends[0]).normalized().orthogonal()
    var b = (after_ends[1] - after_ends[0]).normalized().orthogonal()
    var bisector = (a + b).normalized()
    if bisector.length_squared() < 0.000001: return b * _width(actor, after) / 2
    return bisector * (_width(actor, before) + _width(actor, after)) / 4 / maxf(0.5, bisector.dot(b))

static func _width(actor, part: Dictionary) -> float:
    return actor.definition.visual.geometry.size.y * 1.0

static func _cap(actor, center: Vector2, outward: Vector2, radius: float, color: Color) -> void:
    var points = PackedVector2Array([center])
    for i in 13: points.append(center + Vector2.from_angle(outward.angle() - PI / 2 + PI * i / 12) * radius)
    actor.draw_colored_polygon(points, color)

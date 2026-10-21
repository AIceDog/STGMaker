@tool
extends RefCounted
## 同一份局部几何用于绘制和判定；凹多边形分解成凸分片，圆环拆成无填芯的环带。
## 缓存只属于实例；连续扫掠使用 Godot Shape2D，运动朝向与素材局部变换分开。
var shapes: Array[Shape2D] = []
var transforms: Array[Transform2D] = []

static func build(material: STGBulletDefinition):
	var geometry = material.collision
	return for_geometry(geometry)

static func for_geometry(geometry: STGBulletGeometry):
	var result = new()
	var local = geometry.local_transform()
	if geometry.kind == "ring":
		var outside = geometry.outline()
		for i in outside.size():
			var a = outside[i]
			var b = outside[(i + 1) % outside.size()]
			result.polygon(PackedVector2Array([a, b, b * geometry.inner_ratio, a * geometry.inner_ratio]), local)
	elif (geometry.kind == "circle" or geometry.kind == "sector" and is_equal_approx(geometry.sector_angle, 360)) and is_equal_approx(geometry.size.x, geometry.size.y):
		var shape = CircleShape2D.new()
		shape.radius = geometry.size.x / 2
		result.add(shape, local)
	elif geometry.kind == "rectangle":
		var shape = RectangleShape2D.new()
		shape.size = geometry.size
		result.add(shape, local)
	else:
		var outline = geometry.outline()
		if not Geometry2D.triangulate_polygon(outline).is_empty():
			for piece in Geometry2D.decompose_polygon_in_convex(outline): result.polygon(piece, local)
	return result

func add(shape: Shape2D, transform: Transform2D) -> void:
	shapes.append(shape)
	transforms.append(transform)

func polygon(points: PackedVector2Array, transform: Transform2D) -> void:
	var shape = ConvexPolygonShape2D.new()
	shape.points = points
	add(shape, transform)

func segment(a: Vector2, b: Vector2, width: float, local: Transform2D = Transform2D.IDENTITY) -> void:
	var shape = CapsuleShape2D.new()
	shape.radius = width / 2
	shape.height = a.distance_to(b) + width
	add(shape, local * Transform2D((b - a).angle() - PI / 2, (a + b) / 2))

func hits(actor, point: Vector2, radius: float) -> bool:
	var scale_factor: float = actor.collision_scale
	if scale_factor <= 0.00001: return false
	var placement = Transform2D(actor.rotation, Vector2.ONE * scale_factor, 0, actor.previous)
	return hits_at(placement, actor.position - actor.previous, point, radius)

func hits_at(placement: Transform2D, motion: Vector2, point: Vector2, radius: float) -> bool:
	var target = CircleShape2D.new()
	target.radius = radius
	for i in shapes.size():
		if shapes[i].collide_with_motion(placement * transforms[i], motion, target, Transform2D(0, point), Vector2.ZERO): return true
	return false

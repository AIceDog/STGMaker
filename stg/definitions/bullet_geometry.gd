@tool
class_name STGBulletGeometry
extends Resource
## 弹体局部几何。size 是宽高；旋转和偏移只改变外形/判定，不改变弹体朝向与运动。
## 自由多边形的点保存为相对 size 的坐标，允许凹形；碰撞分解成凸分片，保留凹口。
@export_enum("circle", "diamond", "rectangle", "triangle", "polygon", "ring", "sector") var kind: String = "circle"
@export var size: Vector2 = Vector2(20, 20)
@export var rotation_degrees: float = 0
@export var offset: Vector2 = Vector2.ZERO
@export var along_beam: bool = false # 激光矩形可沿路径延伸；关闭时仍是独立的居中矩形。
@export_range(3, 64, 1) var sides: int = 5
@export_enum("regular", "custom") var polygon_mode: String = "regular"
@export var points: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0), Vector2(-0.25, -0.4330127), Vector2(-0.25, 0.4330127)])
@export_range(0, 0.999, 0.001) var inner_ratio: float = 0.5
@export_range(1, 360, 0.1) var sector_angle: float = 90

func local_transform() -> Transform2D:
	return Transform2D(deg_to_rad(rotation_degrees), offset)

func trail_endpoints(a: Vector2, b: Vector2) -> PackedVector2Array:
	# 尾迹沿每段切线解释局部变换；X 尺寸是段长倍率，Y 尺寸是路径宽度。
	var placement = Transform2D((b - a).angle(), (a + b) / 2) * local_transform()
	var half = Vector2(a.distance_to(b) * size.x / 2, 0)
	return PackedVector2Array([placement * -half, placement * half])

func outline(resolution: int = 96) -> PackedVector2Array:
	var result = PackedVector2Array()
	match kind:
		"rectangle": result = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
		"diamond": result = PackedVector2Array([Vector2(0, -0.5), Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-0.5, 0)])
		"triangle": result = _regular(3)
		"polygon": result = points.duplicate() if polygon_mode == "custom" else _regular(sides)
		"sector":
			if is_equal_approx(sector_angle, 360): result = _regular(resolution)
			else:
				result.append(Vector2.ZERO)
				var count = maxi(2, ceili(resolution * sector_angle / 360))
				for i in count + 1: result.append(Vector2.from_angle(deg_to_rad(sector_angle) * (float(i) / count - 0.5)) * 0.5)
		_:
			result = _regular(resolution)
	for i in result.size(): result[i] *= size
	return result

func _regular(count: int) -> PackedVector2Array:
	var result = PackedVector2Array()
	for i in maxi(3, count): result.append(Vector2.from_angle(TAU * i / maxi(3, count)) * 0.5)
	return result

func validate() -> PackedStringArray:
	var issues = PackedStringArray()
	if not kind in ["circle", "diamond", "rectangle", "triangle", "polygon", "ring", "sector"]: issues.append("未知几何形状。")
	if not size.is_finite() or size.x <= 0 or size.y <= 0: issues.append("几何宽高必须是有限正数。")
	if not offset.is_finite() or not is_finite(rotation_degrees): issues.append("几何偏移与旋转必须是有限值。")
	if along_beam and kind != "rectangle": issues.append("只有矩形几何可以沿激光路径延伸。")
	if sides < 3 or sides > 64: issues.append("正多边形边数必须在 3 到 64 之间。")
	if polygon_mode not in ["regular", "custom"]: issues.append("未知多边形编辑模式。")
	if kind == "polygon" and polygon_mode == "custom":
		var finite = true
		for point in points: finite = finite and point.is_finite()
		if not finite or points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty(): issues.append("自由多边形需要至少三个不相交顶点。")
	if not is_finite(inner_ratio) or inner_ratio < 0 or inner_ratio >= 1: issues.append("圆环内径比例必须在 0 到 1 之间。")
	if not is_finite(sector_angle) or sector_angle <= 0 or sector_angle > 360: issues.append("扇形角度必须大于 0 且不超过 360。")
	return issues

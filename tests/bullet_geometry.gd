extends SceneTree
## 几何契约的行为测试：开口/凹口、独立局部变换、扫掠和序列化，均调用正式碰撞实现。
const Collision = preload("res://stg/runtime/attacks/bullet_collision.gd")
var checks = 0
var failures = 0

class ProbeActor extends Node2D:
	var collision_scale: float = 1
	var previous: Vector2 = Vector2.ZERO

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func hit(geometry: STGBulletGeometry, point: Vector2, radius: float = 0.1, angle: float = 0) -> bool:
	var material = STGBulletDefinition.new()
	material.collision = geometry
	var actor = ProbeActor.new()
	actor.rotation = angle
	var result = Collision.build(material).hits(actor, point, radius)
	actor.free()

	return result

func run() -> void:
	var geometry = STGBulletGeometry.new()
	geometry.kind = "triangle"
	check(geometry.outline().size() == 3, "三角形是明确独立的三顶点类型")
	geometry.kind = "polygon"
	check(geometry.outline().size() == 5, "多边形默认生成正五边形")
	geometry.sides = 8
	check(geometry.outline().size() == 8, "边数控制正多边形轮廓")
	geometry.polygon_mode = "custom"
	geometry.size = Vector2.ONE
	geometry.points = PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 1), Vector2(1, 1), Vector2(1, 4), Vector2(0, 4)])
	check(geometry.validate().is_empty(), "自由凹多边形合法")
	check(hit(geometry, Vector2(0.5, 3)), "凹多边形实体部分产生碰撞")
	check(not hit(geometry, Vector2(3, 3)), "凹多边形凹口不能被凸包填平")
	geometry = STGBulletGeometry.new()
	geometry.kind = "ring"
	check(not hit(geometry, Vector2.ZERO, 1), "圆环中孔不产生碰撞")
	check(hit(geometry, Vector2(7, 0)), "圆环环带产生碰撞")
	check(not hit(geometry, Vector2(12, 0)), "圆环外侧不产生碰撞")
	geometry.inner_ratio = 0
	check(hit(geometry, Vector2.ZERO), "圆环内径为零时退化为实心，不留下无效空洞")
	geometry.kind = "sector"
	geometry.sector_angle = 90
	check(hit(geometry, Vector2(5, 0)), "扇形有效区域产生碰撞")
	check(not hit(geometry, Vector2(-5, 0)), "扇形背部开口不产生碰撞")
	check(not hit(geometry, Vector2(0, 5)), "扇形径向边外不产生碰撞")
	geometry.sector_angle = 360
	check(hit(geometry, Vector2(-5, 0)) and hit(geometry, Vector2.ZERO), "完整扇形正确覆盖整个圆形区域")
	geometry.kind = "rectangle"
	geometry.size = Vector2(10, 2)
	geometry.offset = Vector2(20, 0)
	geometry.rotation_degrees = 90
	check(hit(geometry, Vector2(20, 4)), "局部旋转和偏移共同作用于碰撞")
	check(not hit(geometry, Vector2(24, 0)), "旋转后的窄边不扩大判定")
	check(hit(geometry, Vector2(-4, 20), 0.1, PI / 2), "弹体朝向继续独立作用于局部变换")
	var material = STGBulletDefinition.new()
	var actor = ProbeActor.new()
	actor.previous = Vector2(-50, 0)
	actor.position = Vector2(50, 0)
	check(Collision.build(material).hits(actor, Vector2.ZERO, 1), "高速平移保留连续扫掠判定")
	actor.free()
	material.form = "laser"
	material.collision.kind = "rectangle"
	material.collision.size = Vector2(100, 10)
	actor = ProbeActor.new()
	check(Collision.build(material).hits(actor, Vector2.ZERO, 0.1), "独立激光矩形仍以弹体原点为中心")
	check(not Collision.build(material).hits(actor, Vector2(90, 0), 0.1), "独立矩形不会隐式延伸成路径激光")
	material.collision.offset = Vector2(50, 0)
	check(Collision.build(material).hits(actor, Vector2(90, 0), 0.1), "局部偏移可显式调整直线激光起点")
	check(not Collision.build(material).hits(actor, Vector2(-40, 0), 0.1), "局部偏移后的激光仍使用同一几何判定")
	actor.free()
	material.form = "moving"
	var original_angle = geometry.rotation_degrees
	var ends = geometry.trail_endpoints(Vector2(0, 0), Vector2(10, 0))
	check(ends[0].is_equal_approx(Vector2(25, -50)) and ends[1].is_equal_approx(Vector2(25, 50)), "尾迹局部变换应用于段中心")
	check(geometry.rotation_degrees == original_angle, "实例计算不写共享几何资源")
	material.visual.geometry.kind = "triangle"
	material.visual.geometry.size = Vector2(30, 40)
	material.visual.geometry.offset = Vector2(3, 7)
	material.visual.geometry.rotation_degrees = 32
	material.visual.color = Color(0.2, 0.4, 0.6, 0.8)
	material.collision = geometry
	check(ResourceSaver.save(material, "user://bullet_geometry_roundtrip.tres") == OK, "新静态素材可独立保存")
	var loaded = ResourceLoader.load("user://bullet_geometry_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as STGBulletDefinition
	check(loaded != null and loaded.visual.geometry.kind == "triangle" and loaded.visual.geometry.size == Vector2(30, 40), "重开素材保留形状与大小")
	check(loaded.visual.geometry.offset == Vector2(3, 7) and loaded.visual.geometry.rotation_degrees == 32, "重开素材保留局部变换")
	check(loaded.visual.color.is_equal_approx(material.visual.color), "重开素材保留染色与透明度")
	check(loaded.collision != loaded.visual.geometry and loaded.collision.offset == Vector2(20, 0), "碰撞和外观独立序列化")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bullet_geometry_roundtrip.tres"))
	material.visual.mode = "geometry"
	material.visual.texture = ImageTexture.new()
	check(not material.visual.validate().is_empty(), "几何外形拒绝贴图引用")
	material.visual.mode = "texture"
	material.visual.texture = null
	check(not material.visual.validate().is_empty(), "贴图外形要求明确图片引用")
	print("BULLET GEOMETRY RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

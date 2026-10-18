@tool
class_name STGBulletDefinition
extends Resource
## 可复用的静态子弹素材：外观、碰撞、节点结构和路径采样。
## 发射、运动、伤害、声音与命中/结束事件属于招式，实例状态只保存在运行器。
@export var id: String = ""
@export var title: String = "新子弹素材"
@export_multiline var description: String = ""
@export_enum("moving", "laser", "area", "trail") var form: String = "moving"
@export var scene: PackedScene
@export var visual_scene: PackedScene # 可选 Node2D 表现：动画、粒子；不承担发射或碰撞。
@export var visual_animation: String = "" # 空字符串使用场景各 AnimationPlayer 的自动播放设置。
@export var show_base_visual: bool = true # 允许场景替代基础几何或贴图，也可只叠加粒子。
@export var spawn_particles: PackedScene
@export var run_particles: PackedScene
@export var hit_particles: PackedScene
@export var particle_duration: float = 2.0
@export var visual: STGBulletVisual = STGBulletVisual.new()
@export var collision: STGBulletGeometry = STGBulletGeometry.new()
@export var beam_path: Curve2D
@export var beam_path_size: Vector2 = Vector2(260, 24) # 曲线点的设计尺寸；调整独立外观/判定尺寸时保持同一条路径。
@export var trail_spacing: float = 4
@export var trail_offset: float = 20
@export var trail_break_distance: float = 100

func beam_points(geometry: STGBulletGeometry) -> PackedVector2Array:
	if beam_path == null: return PackedVector2Array([Vector2.ZERO, Vector2(geometry.size.x, 0)])
	var result = beam_path.get_baked_points()
	for i in result.size(): result[i] *= geometry.size / beam_path_size
	return result

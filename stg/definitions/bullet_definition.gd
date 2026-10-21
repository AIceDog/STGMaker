@tool
class_name STGBulletDefinition
extends Resource
## 可复用的静态子弹素材：外观、碰撞、节点结构和路径采样。
## 发射、运动、伤害、声音与命中/结束事件属于招式，实例状态只保存在运行器。
@export var id: String = ""
@export var title: String = "新子弹素材"
@export_multiline var description: String = ""
@export_enum("moving", "laser", "area", "trail") var form: String = "moving"
@export var spawn_particles: PackedScene
@export var run_particles: PackedScene
@export var hit_particles: PackedScene
@export var visual: STGBulletVisual = STGBulletVisual.new()
@export var collision: STGBulletGeometry = STGBulletGeometry.new()
@export var trail_spacing: float = 4
@export var trail_offset: float = 20
@export var trail_break_distance: float = 100

func supported_capabilities() -> PackedStringArray:
	return PackedStringArray({"moving":["Body2D"], "laser":["Beam2D", "Polyline2D"], "trail":["Trail2D"], "area":["Area2D"]}.get(form, []))

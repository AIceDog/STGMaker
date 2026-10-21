@tool
class_name STGBulletVisual
extends Resource
const Frames = preload("res://stg/definitions/texture_frames.gd")
## 几何和贴图是互斥的外形来源；颜色对两种来源都生效。
@export_enum("geometry", "texture") var mode: String = "geometry"
@export var geometry: STGBulletGeometry = STGBulletGeometry.new()
@export var texture: Texture2D
@export var spawn_clip: SpriteFrames
@export var run_clip: SpriteFrames
@export var hit_clip: SpriteFrames
@export var expire_clip: SpriteFrames
@export var color: Color = Color("55dfbc")

func validate() -> PackedStringArray:
	var issues = PackedStringArray()
	if mode not in ["geometry", "texture"]: issues.append("未知外形来源。")
	if geometry == null: issues.append("缺少外形几何。")
	else: issues.append_array(geometry.validate())
	if mode == "texture" and texture == null and run_clip == null: issues.append("贴图外形需要选择静态图片或运行中动画。")
	if texture != null and run_clip != null: issues.append("运行中外观只能选择静态图片或动画中的一种。")
	if mode == "geometry" and texture != null: issues.append("几何外形不能引用贴图。")
	for clip in [spawn_clip, run_clip, hit_clip, expire_clip]:
		if clip == null: continue
		if mode != "texture": issues.append("几何外形不能引用贴图动画。")
		issues.append_array(Frames.validate(clip))
	if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a): issues.append("外形颜色必须是有限值。")
	return issues

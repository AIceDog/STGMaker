@tool
class_name STGBackgroundLayer
extends Resource
## 背景层只跟随关卡卷轴；不依赖敌人位置。贴图为空时使用几何占位表现。
@export var title: String = "背景层"
@export var texture: Texture2D
@export var scroll_ratio: float = 0.25
@export var tint: Color = Color.WHITE

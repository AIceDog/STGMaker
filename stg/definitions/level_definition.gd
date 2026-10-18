@tool
class_name STGLevelDefinition
extends Resource
## 完整关卡的制作数据；片段可复制、重排，编队从项目 waves 集合引用。
## 位置均为 960×540 设计坐标：屏幕中心 (0, 0)，+X 向右、+Y 向下；实际战斗进度不存入资源。
@export var id: String = ""
@export var title: String = "新关卡"
@export var background_color: Color = Color("101b30")
@export var background_layers: Array[STGBackgroundLayer] = []
@export var music: AudioStream
@export var player_spawn: Vector2 = Vector2(-320, 0)
@export var segments: Array[STGLevelSegment] = []

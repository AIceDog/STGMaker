@tool
class_name STGLevelEvent
extends Resource
## 阶段内的一次出场事件；at 是阶段开始后的秒数，前段等待不会改写该时间。
@export var id: String = ""
@export var title: String = "编队出场"
@export var at: float = 0
@export var wave_id: String = ""
@export var spawn_position: Vector2 = Vector2(450, -100) # 编队中心的战斗设计坐标，允许出生在屏幕外。

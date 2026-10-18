@tool
class_name STGLevelSegment
extends Resource
## 顺序关卡阶段：duration 是完整时间轴中的计划长度，实际结束由 exit_rule 决定。
@export var id: String = ""
@export var title: String = "新片段"
@export var duration: float = 8 # 秒；参与完整时间轴的计划排布，不是实际等待时间。
@export var scroll_speed: float = 80 # 设计单位 / 秒，非负；运行器统一向左推进。
@export var exit_rule: STGLevelExitRule
@export var events: Array[STGLevelEvent] = []

@tool
class_name STGBossAttack
extends Resource
## 攻击配置引用招式或行为子流程；位移与动画属于动作。
@export var enabled: bool = false
@export var barrage_id: String = ""
@export var behavior_id: String = ""
@export_enum("immediate", "emission", "cleared", "duration") var finish_event: String = "cleared"
@export_enum("boss", "player", "world") var origin_mode: String = "boss"
@export var origin_offset: Vector2 = Vector2.ZERO
@export var follow_boss: bool = true
@export var clear_on_end: bool = false

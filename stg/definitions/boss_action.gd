@tool
class_name STGBossAction
extends Resource
## 动作段组合攻击、移动与表现；时序只在这里定义一次。
## 前摇、执行时长、后摇与延迟均以秒计；执行器的当前时刻和触发标记不放进 Resource。
@export var extension: STGExtensionBinding # 自定义完整动作；duration 是执行上限。
@export var title: String = "等待"
@export var attack: STGBossAttack
@export var movement: STGBossMovement
@export var presentation: STGBossPresentation
@export var windup: float = 0.3
@export var duration: float = 0.5
@export var recovery: float = 0.3
@export_enum("active", "movement_end") var attack_start: String = "active"
@export var attack_delay: float = 0
@export_enum("windup", "active", "attack_start", "attack_end") var movement_start: String = "active"
@export var movement_delay: float = 0
@export_enum("attack", "movement", "both", "time") var end_when: String = "time"
@export var interrupt_on_hit: bool = false

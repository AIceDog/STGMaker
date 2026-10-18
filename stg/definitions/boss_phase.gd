@tool
class_name STGBossPhase
extends Resource
## Boss 血量阶段；与“子弹自身阶段”是不同层级。
@export var title: String = "普通阶段"
@export_range(0, 100) var enter_hp: float = 100.0
@export var loop: bool = true
# 同一 life 共用血条；进入更大的 life 时补满。顺序阶段只能由时间或清空血条进入。
@export var life: int = 0
@export_enum("hp", "sequence") var entry_mode: String = "hp"
@export_range(1, 100) var life_hp: float = 100.0
@export var entry_delay: float = 0.0
@export var entry_invulnerable: bool = false
@export var entry_barrage_id: String = "" # 转场等待期间可继续发射；不能附带 Boss 位移。
@export var entry_behavior_id: String = ""
@export var time_limit: float = 0.0
@export_enum("next", "life_start", "finish") var time_exit: String = "next"
@export_enum("auto", "next", "finish") var depleted_exit: String = "auto"
@export_range(1, 100) var depleted_refill: float = 100.0
@export var clear_on_enter: bool = false
@export var behavior_flow: STGBehaviorFlow

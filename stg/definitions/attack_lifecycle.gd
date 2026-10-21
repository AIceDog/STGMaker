@tool
class_name STGAttackLifecycle
extends Resource
## 每颗弹体读取的只读配置，年龄、命中记录和冷却始终属于运行实例。
@export var damage: float = 1.0
@export var damage_on_contact: bool = true
@export var damage_falloff_start: float = 1.0
@export var damage_falloff_scale: float = 1.0
@export_enum("persistent", "activation", "repeat") var hit_mode: String = "persistent"
@export var hit_interval: float = 0.7
@export var hit_effects: Array[STGExtensionBinding] = []
@export var on_hit_barrage_id: String = ""
@export var on_hit_behavior_id: String = ""
@export var on_expire_barrage_id: String = ""
@export var on_expire_behavior_id: String = ""
@export_enum("none", "ground", "bounds") var exit_mode: String = "none"
@export var ground_y: float = 220.0
@export var bounds_margin: float = 60.0
@export var spawn_sound: AudioStream
@export var hit_sound: AudioStream
@export var expire_sound: AudioStream
@export var spawn_effect: PackedScene
@export var hit_effect: PackedScene
@export var expire_effect: PackedScene
@export var effect_duration: float = 2.0

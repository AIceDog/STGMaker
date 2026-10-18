@tool
class_name STGFirePattern
extends Resource
## 单一招式的发射规则；时序、排列与方向均由同一个发射器执行。
@export var extension: STGExtensionBinding
@export var extension_duration: float = 5.0 # 每轮自定义发射的最长执行秒数。
@export var title: String = "发射"
@export var enemy_id: String = "" # 非空时改为召唤；召唤复用敌人自己的正式行为运行器。
@export var summon_life: float = 12.0 # 无生命值交互的预览回收上限，宿主可提前击败。
@export var at: float = 0.0
@export_enum("each_round", "call_start") var aim_lock: String = "each_round"
@export var safe_gap_radius: float = 0.0 # 出生点落入玩家所在轴的安全缺口时跳过，不改排列。
@export_enum("x", "y") var safe_gap_axis: String = "x"
@export_enum("origin", "boss", "player", "world") var anchor: String = "origin"
@export_enum("both", "x", "y") var anchor_axes: String = "both" # 仅取所选轴，其余轴使用世界原点；例如全屏落雷只锁定玩家 x。
@export var offset: Vector2 = Vector2.ZERO
@export_enum("point", "circle", "line", "path") var arrangement: String = "point"
@export var radius: float = 80.0
@export var line_length: float = 200.0
@export var path: Curve2D
@export_enum("fan", "parallel", "outward", "inward", "aim", "random") var direction: String = "fan"
@export var angle: float = 90.0 # 相对于调用朝向的角度，单位为度。
@export var aim_offset: float = 0.0 # 自机狙相对于目标方向的角度偏移。
@export var aim_target_offset: Vector2 = Vector2.ZERO # 瞄准玩家旁的相对位置；双头交叉射击可以各自越过玩家中心。
@export var aim_spread: bool = false # 开启后，以瞄准方向为中心按 spread 展开扇形。
@export var angle_jitter: float = 0.0
@export var speed_scale_min: float = 1.0
@export var speed_scale_max: float = 1.0
@export var spread: float = 90.0
@export_range(1, 256) var count: int = 9
@export_range(1, 64) var rounds: int = 1
@export var interval: float = 0.25
@export_range(0, 256) var group_size: int = 0 # 0 为齐射；正数为同一轮内每批的数量，末批保留余数。
@export var group_interval: float = 0.1 # 同一轮内相邻批次起点之间的秒数。
@export var rotation_per_round: float = 0.0
@export var rotation_per_projectile: float = 0.0 # 按完整轮内的弹体序号旋转，分组不重置序号。
@export_enum("position", "launch") var summon_mode: String = "position"
@export var summon_launch_speed: float = 200.0
@export var summon_launch_duration: float = 0.6 # 入场运动结束后才启动敌人自己的 AI。

@export_enum("cast", "round", "projectile") var sound_unit: String = "round"


@tool
class_name STGMotionStage
extends Resource
## 招式弹体飞行过程中的一次运动变化；实例独立维护当前步骤与时钟。
## path 使用局部坐标，默认向前方向为 +Y；时间曲线横轴为本次运动进度 0–1。
## duration 为秒，speed 为设计单位 / 秒，turn_speed 和 orbit_speed 为度 / 秒；实例进度由运行器持有。
@export var title: String = "路径移动"
@export_enum("path", "aim", "track", "velocity", "sine", "ballistic", "orbit", "wait", "transform", "extension") var mode: String = "path"
# 扩展声明共享，参数随阶段保存；执行状态由子弹的 motion_session 独立持有。
@export var extension: STGExtensionBinding
@export_range(0.01, 60) var duration: float = 2.0
@export var path: Curve2D
@export var speed: float = 180.0
# velocity 保留发射器的扇形角度；sine 只摆动飞行方向，不重新瞄准玩家。
@export var sine_amplitude: float = 25.7831 # 度；相当于约 0.45 弧度。
@export var sine_frequency: float = 8.0 # 弧度 / 秒。
@export var sine_phase: float = 0.0 # 弧度；同一组弹可使用不同相位。
# ballistic 的重力与初速度使用世界坐标；进入阶段时只计算一次，不持续追踪。
@export var gravity: float = 520.0
@export var ballistic_aim: bool = true
@export var flight_time: float = 0.0 # 0 表示根据距离估算飞行时间。
@export var flight_speed: float = 300.0
@export var flight_min_time: float = 0.55
@export var flight_max_time: float = 1.5
@export var flight_min_distance: float = 120.0
@export_enum("distance", "horizontal") var flight_distance_mode: String = "distance"
@export var initial_velocity: Vector2 = Vector2(0, -430)
@export var velocity_x_player_factor: float = 0.0
@export var velocity_x_limit: float = 50.0
@export var turn_speed: float = 180.0
@export var preserve_heading: bool = false # 追踪弹保留扇形初始方向，再逐步转向。
@export var track_target_offset: Vector2 = Vector2.ZERO
@export var orbit_radius: float = 80.0
@export var orbit_speed: float = 90.0
@export_enum("boss", "player", "origin") var orbit_center: String = "boss"
@export var orbit_end_radius: float = -1.0 # -1 保持半径；否则线性扩圈 / 缩圈。
@export var angular_speed: float = 0.0 # 度 / 秒，作用于几何与碰撞，适用于旋转激光。
@export var track_until_distance: float = 0.0 # 0 持续追踪；靠近后永久锁定方向。
@export var transform_attack_id: String = ""
@export var progress_curve: Curve
@export var visual_scale_curve: Curve
@export var collision_scale_curve: Curve

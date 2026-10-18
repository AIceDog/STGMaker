@tool
class_name STGBossMovement
extends Resource
## 全部位移方式集中在移动模块；身体攻击、隐藏和无敌是独立配置。
## duration / prediction 使用秒，半径和目标使用设计单位，turn_speed 使用度 / 秒。
## target_mode 决定基准；路径相对动作起点，world 目标使用固定战斗设计坐标。
const MODES = ["none", "line", "curve", "dash", "teleport", "burrow", "orbit", "ballistic"]
const LABELS = ["不移动", "直线", "曲线路径", "冲刺", "瞬移", "遁地换位", "环绕 / 缩圈", "重力跳跃 / 俯冲"]
@export_enum("none", "line", "curve", "dash", "teleport", "burrow", "orbit", "ballistic") var mode: String = "none"
@export var duration: float = 0.5
@export var speed: float = 0.0 # 0 按目标与时长插值；正值按锁定方向走固定速度。
@export var path: Curve2D
@export_enum("relative", "player", "world") var target_mode: String = "relative" # 动作起点 / 玩家位置 / 固定战斗坐标。
@export var target: Vector2 = Vector2(100, 0) # 按 target_mode 解释的目标坐标。
@export_enum("snapshot", "track", "predict") var aiming: String = "snapshot"
@export_enum("windup", "active") var lock_at: String = "active"
@export var prediction: float = 0.3
@export var turn_speed: float = 180
@export var body_attack: bool = false
@export var body_radius: float = 20
@export var body_damage: float = 1
@export var hide_while_buried: bool = true
@export var invulnerable_while_buried: bool = true
@export var orbit_end_radius: float = 55 # 起始半径来自实际距离，较小的结束半径形成缩圈。
@export var orbit_turns: float = 1.5
@export var orbit_follow_center: bool = true # 仅在玩家圆心时生效；关闭则按 lock_at 锁定一次。
@export var orbit_progress_curve: Curve # 移动时间 0–1 → 起始半径到结束半径的进度 0–1。
# 设计坐标 +Y 向下。初速度只在执行开始时锁定；此后按解析式运动，不追踪玩家。
@export var initial_velocity: Vector2 = Vector2(-260, -700)
@export var gravity: float = 1500
@export_enum("fixed", "direction", "horizontal") var velocity_mode: String = "fixed"

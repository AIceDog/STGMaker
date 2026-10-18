@tool
class_name STGEntitySettings
extends Resource
## 敌人 / 障碍自身的关卡属性；编队只引用实体，不重复配置碰撞或移动规则。
## 仅保存规则；是否已进入屏幕、实际年龄、血量和离场原因由每个运行实例独立记录。
@export_enum("scroll", "independent") var movement_policy: String = "independent"
@export var scroll_factor: float = 1 # 无单位；仅 scroll 模式乘以关卡的卷轴位移。
@export_enum("left", "screen", "never") var exit_boundary: String = "never"
@export var exit_margin: float = 60 # 设计单位；在屏幕边界与身体半径之外再扩展回收范围。
@export var require_screen_entry: bool = true # 先实际进入 / 扫过屏幕，再允许按边界回收。
@export var lifetime: float = 0 # 从生成开始计秒，0 表示不按时间离场。
@export var persist_across_segments: bool = false
@export var body_radius: float = 20 # 设计单位；实体接触碰撞半径。
@export var destructible: bool = true
@export var contact_damage: float = 1

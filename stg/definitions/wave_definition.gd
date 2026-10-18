@tool
class_name STGWaveDefinition
extends Resource
## 可复用编队：一个实体模板、数量、间隔和排列。出生位置和时间由关卡事件提供。
## kind=obstacle 时不执行 AI；仍复用生命、接触判定、出场与离场接口。
@export var id: String = ""
@export var title: String = "新编队"
@export_enum("enemy", "obstacle") var kind: String = "enemy"
@export var enemy_id: String = ""
@export var obstacle_id: String = ""
@export_range(1, 32) var count: int = 3
@export var interval: float = 0.4 # 秒；相邻成员的生成间隔，0 表示同时生成。
@export var spacing: Vector2 = Vector2(0, 65) # 设计单位；相邻成员的位置差，排列围绕事件出生点居中。
@export var counts_for_clear: bool = true # 仅清场条件使用；“全部击败”始终包含本阶段全部敌人。

func offset(index: int) -> Vector2:
	return spacing * (index - (count - 1) / 2.0)

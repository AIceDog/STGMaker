@tool
class_name STGMotionContext
extends STGExtensionContext
## 运动扩展只提交位置与朝向；阶段时间、碰撞、伤害及回收仍由子弹运行器负责。
## 上下文与实现对象都是每颗子弹独立创建，不能存入共享定义资源。
var _actor

func origin() -> Vector2:
	return _actor.stage_origin if active() and _actor != null else Vector2.ZERO

func position() -> Vector2:
	return _actor.position if active() and _actor != null else Vector2.ZERO

func set_position(value: Vector2) -> void:
	if active() and _actor != null and value.is_finite(): _actor.position = value

func heading() -> float:
	return _actor.rotation if active() and _actor != null else 0.0

func set_heading(value: float) -> void:
	if active() and _actor != null and is_finite(value): _actor.rotation = value

func target_position() -> Vector2:
	return player_position()

func speed_scale() -> float:
	return _actor.speed_scale if active() and _actor != null else 1.0

func _close() -> void:
	super._close()
	_actor = null

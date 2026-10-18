@tool
class_name STGExtensionContext
extends RefCounted
## 公共只读查询和完成协议。下划线字段供框架适配器使用，扩展只调用公开方法。
## 战斗位置为设计坐标，角度为弧度，时间为秒；随机数来自本次战斗的固定种子。
var _world
var _elapsed: float = 0
var _active: bool = true
var _finished: bool = false
var _failed: bool = false

func _init(world = null) -> void:
	_world = world

func elapsed() -> float: return _elapsed
func active() -> bool: return _active
func is_finished() -> bool: return _finished
func player_position() -> Vector2: return _world.player if _active and _world != null else Vector2.ZERO
func enemy_position() -> Vector2: return _world.boss if _active and _world != null else Vector2.ZERO
func enemy_health() -> float: return _world.hp if _active and _world != null else 0.0
func time_seconds() -> float: return _world.time if _active and _world != null else 0.0
func action_elapsed(identifier: String) -> float:
	return _world.time - _world.action_completed_at.get(identifier, -1000000.0) if _active and _world != null else 0.0
func seconds_since_hit() -> float:
	return _world.time - _world.boss_last_hit_at if _active and _world != null else 0.0
func random_range(minimum: float, maximum: float) -> float:
	return _world.rng.randf_range(minimum, maximum) if _active and _world != null else minimum
func random_integer(minimum: int, maximum: int) -> int:
	return _world.rng.randi_range(minimum, maximum) if _active and _world != null else minimum

func finish(success: bool = true) -> void:
	if _active:
		_finished = true
		_failed = not success
		_active = false # 完成回调内也不能继续提交操作，第一次完成结果保持不变。

func _close() -> void:
	_active = false
	_world = null

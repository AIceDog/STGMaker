@tool
class_name STGAttackEntityContext
extends STGExtensionContext
## 单实体权限，不提供创建其他实体或任意句柄更新接口。
var _dispatch: Callable
var _query: Callable
var _random = RandomNumberGenerator.new()
var _handle: STGAttackHandle
func random_range(minimum: float, maximum: float) -> float: return _random.randf_range(minimum,maximum) if _active else minimum
func random_integer(minimum: int, maximum: int) -> int: return _random.randi_range(minimum,maximum) if _active else minimum
func time_seconds() -> float: return _query.call("time",null) if _active else 0.0
func position() -> Vector2: return _query.call("position", _handle) if _active else Vector2.ZERO
func velocity() -> Vector2: return _query.call("velocity", _handle) if _active else Vector2.ZERO
func target_position() -> Vector2: return _query.call("target", null) if _active else Vector2.ZERO
func player_position() -> Vector2: return target_position()
func set_position(value: Vector2) -> void:
	if _active: _dispatch.call("transform", {"handle":_handle,"position":value,"rotation":0.0})
func set_velocity(value: Vector2) -> void:
	if _active: _dispatch.call("velocity", {"handle":_handle,"velocity":value})
func destroy() -> void:
	if _active: _dispatch.call("destroy", {"handle":_handle})
func _close() -> void:
	super._close()
	_dispatch = Callable()
	_query = Callable()

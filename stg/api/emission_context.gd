@tool
class_name STGEmissionContext
extends STGCommandContext
## 发射能力读取当前招式的弹体配置，素材与配置始终分别传给运行实例。
var round_index: int = 0
# 能力上下文只读取宿主传入的配置，不反向静态依赖含扩展声明的资产类型。
var _pattern
var _projectile
var _cast
var _skill_id: String = ""
var _locked_player: Vector2
var _step_duration: float = -1.0

func count() -> int: return _pattern.count if _active else 0
func target_position() -> Vector2: return _locked_player if _active and _pattern.aim_lock == "call_start" else player_position()

func emit(at: Vector2, angle: float, speed_multiplier: float = 1) -> void:
	if not _active or _world == null or not at.is_finite() or not is_finite(angle) or not is_finite(speed_multiplier) or speed_multiplier <= 0: return
	if not _pattern.enemy_id.is_empty():
		_world.emit_pattern_summon(_pattern, _projectile.lifecycle, at, angle, _owner_id, _step_duration)
		return
	_world.emit_pattern_projectile(_projectile, at, angle, _owner_id, _cast, _skill_id, speed_multiplier, _step_duration)

func _close() -> void:
	super._close()
	_pattern = null
	_projectile = null
	_cast = null

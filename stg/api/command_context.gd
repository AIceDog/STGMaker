@tool
class_name STGCommandContext
extends STGExtensionContext
## 通过请求操作战斗；归属由框架分配，不能把运行器对象保存进资源。
var _owner_id: int = 0
var _origin: Vector2 = Vector2.ZERO
var _heading: float = 0

func origin() -> Vector2: return _origin
func heading() -> float: return _heading

func emit_projectile(identifier: String, at: Vector2, angle: float) -> void:
	if _active and _world != null and at.is_finite() and is_finite(angle): _world.emit_projectile(identifier, at, angle, _owner_id)

func play_barrage(identifier: String, at: Vector2, angle: float = 0) -> void:
	if _active and _world != null and at.is_finite() and is_finite(angle): _world.play_barrage(identifier, at, _owner_id, angle)

func play_behavior(identifier: String, at: Vector2, angle: float = 0) -> void:
	if _active and _world != null and at.is_finite() and is_finite(angle): _world.play_behavior(identifier, at, _owner_id, angle)

func summon(identifier: String, at: Vector2, lifetime: float = 12) -> void:
	if _active and _world != null and at.is_finite() and is_finite(lifetime) and lifetime > 0: _world.spawn_summon(identifier, at, _owner_id, lifetime)

func damage_player(amount: float) -> void:
	if _active and is_finite(amount) and amount > 0: _world.register_hit(amount)

func damage_enemy(percent: float) -> void:
	if _active and is_finite(percent) and percent > 0: _world.damage_boss(percent)


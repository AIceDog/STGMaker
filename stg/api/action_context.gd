@tool
class_name STGActionContext
extends STGCommandContext
var _behavior

func position() -> Vector2: return enemy_position()
func set_position(value: Vector2) -> void:
	if _active and value.is_finite(): _world.boss = value
func move(displacement: Vector2) -> void:
	set_position(position() + displacement)
func set_invulnerable(value: bool) -> void:
	if _active: _world.boss_invulnerable = value
func play_animation(name: String) -> void:
	if _active: _world.boss_presentation.enter(name, 0, false)

func _close() -> void:
	super._close()
	_behavior = null

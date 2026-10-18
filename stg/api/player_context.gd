@tool
class_name STGPlayerContext
extends STGExtensionContext
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
var slot: String = "controller"
var movement_input: Vector2
var firing: bool = false
var using_ability: bool = false
var _player_definition
var _game

func position() -> Vector2: return player_position()
func health() -> int: return _game.health if active() and _game != null else 0
func set_position(value: Vector2) -> void:
	if not active() or not value.is_finite(): return
	var margin = maxf(12, _player_definition.hit_radius)
	var bounds = CombatSpace.BOUNDS.grow(-margin)
	_world.player = value.clamp(bounds.position, bounds.end)
func move(displacement: Vector2) -> void:
	set_position(position() + displacement)
func fire() -> void:
	if active(): _world.shoot_player()
func shoot(direction: Vector2 = Vector2.RIGHT, speed: float = 720, damage_percent: float = 25, lifetime: float = 1.5) -> void:
	if active(): _world.player_shots.emit_shot(position(), direction, speed, damage_percent, lifetime)
func _close() -> void:
	super._close()
	_player_definition = null
	_game = null

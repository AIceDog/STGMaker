@tool
extends STGActionExtension
## 内置组合动作实现。与脚本动作共享宿主，只编排攻击、移动及前后摇。
const Movement = preload("res://stg/runtime/boss/movement_player.gd")
const Attack = preload("res://stg/runtime/boss/attack_player.gd")
enum Stage { WINDUP, ACTIVE, RECOVERY }
var _definition: STGBossAction
var _behavior
var _movement
var _attack
var _stage: int = Stage.WINDUP
var _clock: float = 0
var _movement_started: bool = false
var _attack_ended: bool = false
var _attack_ended_at: float = 0
var _failed: bool = false
var _components_stopped: bool = false

func _init(definition: STGBossAction) -> void:
	_definition = definition

func start(context: STGActionContext, _parameters: Dictionary) -> void:
	_behavior = context._behavior
	_movement = Movement.new()
	_movement.prepare(_behavior.world, _definition.movement)
	_attack = Attack.new()
	_enter(Stage.WINDUP)
	_schedule()

func tick(context: STGActionContext, dt: float) -> void:
	_clock += dt
	match _stage:
		Stage.WINDUP:
			_schedule()
			_movement.tick(_behavior.world, dt, false)
			if _clock + 0.000001 >= _definition.windup:
				_enter(Stage.ACTIVE)
				_schedule()
		Stage.ACTIVE:
			_schedule()
			_movement.tick(_behavior.world, dt)
			_attack.tick(_behavior, dt)
			if _attack.started and not _attack_ended and _attack.is_completed(_behavior.world, _definition.duration):
				_attack_ended = true
				_attack_ended_at = _attack.elapsed
				_event("attack_ended")
			_schedule()
			_failed = _attack.failed
			if _failed or _active_complete():
				_stop_components()
				_enter(Stage.RECOVERY)
		Stage.RECOVERY:
			if _clock + 0.000001 >= _definition.recovery: context.finish(not _failed)

func _schedule() -> void:
	var attack_ready = _stage == Stage.ACTIVE and _clock + 0.000001 >= _definition.attack_delay
	if _definition.attack_start == "movement_end": attack_ready = attack_ready and _movement.completed
	if _definition.attack.enabled and not _attack.started and attack_ready:
		_attack.start(_behavior, _definition.attack)
		_event("attack_started")
	var move_ready = false
	match _definition.movement_start:
		"windup": move_ready = _stage == Stage.WINDUP and _clock >= _definition.movement_delay
		"active": move_ready = _stage == Stage.ACTIVE and _clock >= _definition.movement_delay
		"attack_start": move_ready = _stage == Stage.ACTIVE and _attack.started and _attack.elapsed >= _definition.movement_delay
		"attack_end": move_ready = _stage == Stage.ACTIVE and _attack_ended and _attack.elapsed >= _definition.movement_delay + _attack_ended_at
	if not _movement_started and move_ready:
		_movement_started = true
		_movement.start(_behavior.world)
		_event("movement_started")

func _active_complete() -> bool:
	var attack_done: bool = not _definition.attack.enabled or _attack_ended
	match _definition.end_when:
		"attack": return attack_done
		"movement": return _movement.completed
		"both": return attack_done and _movement.completed
	return _clock + 0.000001 >= _definition.duration

func _enter(stage: int) -> void:
	_stage = stage
	_clock = 0
	var key: String = ["windup", "active", "recovery"][stage]
	var seconds: float = _definition.get(key if stage != Stage.ACTIVE else "duration")
	_behavior.action_state = ["前摇", "执行", "后摇"][stage]
	_behavior.world.boss_presentation.enter(_definition.presentation.get(key + "_animation"), seconds, stage != Stage.ACTIVE)
	_event(key)

func _event(event: String) -> void:
	_behavior.world.boss_action_event.emit(_behavior.active_node_id, event)

func _stop_components() -> void:
	if _components_stopped: return
	_components_stopped = true
	_movement.cancel(_behavior.world)
	_attack.cancel(_behavior)

func rebase(displacement: Vector2) -> void:
	if _movement != null: _movement.rebase(displacement)

func cancel(_reason: String) -> void:
	if _behavior == null: return
	_stop_components()
	_behavior = null

@tool
extends RefCounted
## 动作宿主：生命周期、表现时钟与公共事件只在此处理；实现只负责动作算法。
const Session = preload("res://stg/runtime/extensions/extension_session.gd")
const Composite = preload("res://stg/runtime/modules/composite_action.gd")
var session = Session.new()
var definition: STGBossAction
var failed: bool:
	get: return session.failed
var _elapsed: float = 0
var _hit_serial: int = 0
var _owner: int = 0
var _invulnerable: bool = false
var _closed: bool = true

func start(behavior, action: STGBossAction) -> void:
	definition = action
	_elapsed = 0
	_closed = false
	_hit_serial = behavior.world.boss_hit_serial
	_invulnerable = behavior.world.boss_invulnerable
	_owner = behavior.world.allocate_owner() if action.extension != null else 0
	if _owner > 0: behavior.owned_attacks.append(_owner)
	var data = STGActionContext.new(behavior.world)
	data._behavior = behavior
	data._owner_id = _owner
	data._origin = behavior.world.boss
	behavior.action_running = true
	var binding = action.extension
	if binding != null: behavior.action_state = "自定义动作"
	if not session.begin(binding.definition if binding != null else null, binding.parameters if binding != null else {}, "action", data, Composite.new(action) if binding == null else null):
		behavior.world.issue = session.issue

func tick(behavior, dt: float) -> bool:
	if _closed: return true
	if definition.interrupt_on_hit and behavior.world.boss_hit_serial != _hit_serial:
		session.cancel("interrupted", true)
		_close(behavior, false)
		return true
	var step = dt
	if definition.extension != null:
		step = minf(dt, maxf(0, definition.duration - _elapsed))
	_elapsed += step
	behavior.world.boss_presentation.tick(step)
	session.tick(step)
	if definition.extension != null and not session.finished and _elapsed + 0.000001 >= definition.duration:
		session.cancel("expired")
	if session.finished: _close(behavior, true)
	return _closed

func rebase(displacement: Vector2) -> void:
	var implementation: STGActionExtension = session.implementation
	if implementation != null: implementation.rebase(displacement)

func cancel(behavior) -> void:
	if _closed: return
	session.cancel("stopped")
	_close(behavior, false)

func _close(behavior, completed: bool) -> void:
	if _closed: return
	_closed = true
	if completed:
		behavior.world.action_completed_at[behavior.active_node_id] = behavior.world.time
	elif _owner > 0:
		behavior.world.stop_owner(_owner)
	behavior.world.boss_invulnerable = _invulnerable
	behavior.world.boss_presentation.reset()
	behavior.action_running = false
	behavior.world.boss_action_event.emit(behavior.active_node_id, "completed" if completed else "cancelled")

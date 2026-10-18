@tool
extends RefCounted
## 一份招式的一套发射计划；组合、延迟和并行由行为流程负责。
const AbilitySession = preload("res://stg/runtime/extensions/extension_session.gd")
const BuiltinEmission = preload("res://stg/runtime/modules/emission.gd")
const Geometry = preload("res://stg/definitions/fire_geometry.gd")
var emission_sessions: Array[Dictionary] = []
var prefab: STGBarrageSkill
var owner_id: int
var origin: Vector2
var heading: float = 0.0
var elapsed: float = 0.0
var fired_rounds: int = 0
var cancelled: bool = false
var failed: bool = false
var locked_player: Vector2 = Vector2.ZERO
var first_step_duration: float = -1.0 # 流程在一帧中途释放时，只推进剩余的精确时长。
var active_step_duration: float = -1.0
var trail_recording: bool = false

func start(definition: STGBarrageSkill, at: Vector2, instance_owner: int, initial_heading: float = 0.0, initial_player: Vector2 = Vector2.ZERO) -> void:
	cancel("replaced")
	prefab = definition
	origin = at
	owner_id = instance_owner
	heading = initial_heading
	locked_player = initial_player
	fired_rounds = 0
	elapsed = 0
	cancelled = false
	failed = false

func tick(world, dt: float) -> void:
	if cancelled: return
	if first_step_duration >= 0:
		dt = minf(dt, first_step_duration)
		first_step_duration = -1
		active_step_duration = dt
	elapsed += dt
	var pattern = prefab.fire_pattern
	while not cancelled and fired_rounds < pattern.rounds and elapsed + 0.000001 >= pattern.at + fired_rounds * pattern.interval:
		_emit(world, fired_rounds, minf(dt, maxf(0, elapsed - pattern.at - fired_rounds * pattern.interval)))
		fired_rounds += 1
	for entry in emission_sessions.duplicate():
		var step = minf(dt, maxf(0, entry.limit - entry.age))
		if entry.first_step >= 0:
			step = minf(step, entry.first_step)
			entry.first_step = -1.0
		entry.age += step
		entry.session.tick(step)
		if entry.session.failed:
			failed = true
			cancel("failed")
			return
		if entry.age + 0.000001 >= entry.limit: entry.session.cancel("expired")
		if entry.session.finished: emission_sessions.erase(entry)
	active_step_duration = -1

func _emit(world, round_index: int, remaining_step: float) -> void:
	var pattern = prefab.fire_pattern
	var data = STGEmissionContext.new(world)
	data._origin = origin
	data._heading = heading
	data._owner_id = owner_id
	data.round_index = round_index
	data._pattern = pattern
	data._projectile = prefab.projectile
	data._cast = self
	data._locked_player = locked_player
	data._skill_id = prefab.id
	if pattern.extension == null and pattern.group_size > 0: data._step_duration = remaining_step
	if pattern.enemy_id.is_empty() and (pattern.sound_unit == "round" or pattern.sound_unit == "cast" and round_index == 0):
		world.present_lifecycle(prefab.projectile.lifecycle.spawn_sound, null, origin, heading)
	var session = AbilitySession.new()
	var binding = pattern.extension
	if not session.begin(binding.definition if binding != null else null, binding.parameters if binding != null else {}, "emission", data, BuiltinEmission.new() if binding == null else null):
		world.issue = session.issue
		failed = true
		cancel("invalid")
	elif session.failed:
		failed = true
		cancel("failed")
	elif not session.finished:
		var grouped = pattern.extension == null and pattern.group_size > 0
		var limit = maxf(pattern.extension_duration, ceilf(float(pattern.count) / maxi(1, pattern.group_size)) * pattern.group_interval + 1.0) if grouped else pattern.extension_duration
		emission_sessions.append({"session": session, "age": 0.0, "limit": limit, "first_step": remaining_step if grouped else -1.0})

func cancel(reason: String = "stopped") -> void:
	cancelled = true
	for entry in emission_sessions: entry.session.cancel(reason)
	emission_sessions.clear()

static func spawn_point(pattern: STGFirePattern, index: int) -> Vector2:
	return Geometry.spawn_point(pattern, index)

func emission_finished() -> bool:
	if cancelled: return true
	if trail_recording and elapsed + 0.000001 < prefab.trail_duration: return false
	return fired_rounds >= prefab.fire_pattern.rounds and emission_sessions.is_empty()

func is_finished(world) -> bool:
	return emission_finished() and world.count_owned(owner_id, false) == 0


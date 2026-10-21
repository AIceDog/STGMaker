@tool
class_name STGAttackContext
extends STGExtensionContext
## 战斗世界坐标、弧度、秒。命令通过受控适配器，不传递 Simulation 引用。
var _dispatch: Callable
var _query: Callable
var _initial_origin: Vector2
var _origin: Vector2
var _heading: float
var _random = RandomNumberGenerator.new()
func origin() -> Vector2: return _origin
func initial_origin() -> Vector2: return _initial_origin
func owner_id() -> int: return _query.call("owner_id",null) if _active else 0
func damage() -> float: return _query.call("damage",null) if _active else 0.0
func seconds_since_hit() -> float: return _query.call("seconds_since_hit",null) if _active else 0.0
func action_elapsed(identifier: String) -> float: return _query.call("action_elapsed",identifier) if _active else 0.0
func heading() -> float: return _heading
func target_position() -> Vector2: return _query.call("target", null) if _active else Vector2.ZERO
func player_position() -> Vector2: return target_position()
func enemy_position() -> Vector2: return _query.call("owner_position", null) if _active else Vector2.ZERO
func enemy_health() -> float: return _query.call("health", null) if _active else 0.0
func time_seconds() -> float: return _query.call("time", null) if _active else 0.0
func random_range(minimum: float, maximum: float) -> float: return _random.randf_range(minimum, maximum) if _active else minimum
func random_integer(minimum: int, maximum: int) -> int: return _random.randi_range(minimum, maximum) if _active else minimum
func _send(command: String, data: Dictionary): return _dispatch.call(command, data) if _active and _dispatch.is_valid() else null
func spawn_body(at: Vector2, velocity: Vector2, seconds: float, entity_program: STGExtensionBinding = null, options:STGAttackEntityOptions=null) -> STGAttackHandle:
    return _send("create", {"capability":"Body2D", "position":at, "velocity":velocity, "lifetime":seconds, "entity_program":entity_program,"options":options})
func create_beam(a: Vector2, b: Vector2, width: float, seconds: float, options:STGAttackEntityOptions=null) -> STGAttackHandle:
    return _send("create", {"capability":"Beam2D", "position":a, "points":PackedVector2Array([a,b]), "width":width, "lifetime":seconds,"options":options})
func create_polyline(points: PackedVector2Array, width: float, seconds: float, options:STGAttackEntityOptions=null) -> STGAttackHandle:
    return _send("create", {"capability":"Polyline2D", "points":points, "width":width, "lifetime":seconds,"options":options})
func create_trail(at: Vector2, width: float, seconds: float, segment_seconds: float, options:STGAttackEntityOptions=null) -> STGAttackHandle:
    return _send("create", {"capability":"Trail2D", "position":at, "width":width, "lifetime":seconds, "segment_seconds":segment_seconds,"options":options})
func create_area(at: Vector2, seconds: float, options:STGAttackEntityOptions=null) -> STGAttackHandle:
    return _send("create", {"capability":"Area2D", "position":at, "lifetime":seconds,"options":options})
func set_transform(handle: STGAttackHandle, at: Vector2, angle: float = 0) -> bool:
    return _send("transform", {"handle":handle,"position":at,"rotation":angle}) == true
func set_velocity(handle: STGAttackHandle, velocity: Vector2) -> bool:
    return _send("velocity", {"handle":handle,"velocity":velocity}) == true
func set_points(handle: STGAttackHandle, points: PackedVector2Array) -> bool:
    return _send("points", {"handle":handle,"points":points}) == true
func set_width(handle: STGAttackHandle, width: float) -> bool:
    return _send("width", {"handle":handle,"width":width}) == true
func set_active(handle: STGAttackHandle, enabled: bool) -> bool:
    return _send("active", {"handle":handle,"enabled":enabled}) == true
func destroy(handle: STGAttackHandle) -> bool: return _send("destroy", {"handle":handle}) == true
func valid(handle: STGAttackHandle) -> bool: return _query.call("valid", handle) if _active else false
func spawn_enemy(at:Vector2,seconds:float,entry_velocity:Vector2=Vector2.ZERO,entry_duration:float=0) -> STGAttackHandle:
 return _send("enemy",{"position":at,"lifetime":seconds,"velocity":entry_velocity,"entry_duration":entry_duration})
func set_visual(handle:STGAttackHandle,options:STGAttackEntityOptions) -> bool:return _send("visual",{"handle":handle,"options":options})==true
func play_sound(stream:AudioStream,at:Vector2,looped:bool=false,follow:STGAttackHandle=null) -> STGAttackHandle:
 return _send("sound",{"stream":stream,"position":at,"looped":looped,"follow":follow})
func play_effect(scene:PackedScene,at:Vector2,seconds:float=2,follow:STGAttackHandle=null) -> STGAttackHandle:
 return _send("effect",{"scene":scene,"position":at,"lifetime":seconds,"follow":follow})
func stop_presentation(handle:STGAttackHandle) -> bool:return _send("stop_presentation",{"handle":handle})==true
func _close() -> void:
    super._close()
    _dispatch = Callable()
    _query = Callable()

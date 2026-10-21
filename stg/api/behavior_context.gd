@tool
class_name STGBehaviorContext
extends STGExtensionContext
## 秒、战斗设计坐标、弧度；仅通过适配器查询和提交命令，不暴露运行器。
var _dispatch: Callable
var _query: Callable
var output_id: String = "completed"
var remaining_seconds: float = 0
var _execution_duration:float=0
func execution_duration() -> float:return _execution_duration
func execution_remaining() -> float:return maxf(0,_execution_duration-elapsed()) if active() else 0.0
func execution_progress() -> float:return clampf(elapsed()/_execution_duration,0,1) if _execution_duration>0 else 1.0
func complete(port: String = "completed", remaining: float = 0) -> void:
    if not active(): return
    output_id = port
    remaining_seconds = maxf(0, remaining)
    finish()
func fail(message: String) -> void:
    if not active(): return
    _send("error", {"message": message})
    output_id = "failure"
    finish(false)
func _send(key: String, data: Dictionary = {}):
    return _dispatch.call(key, data) if active() and _dispatch.is_valid() else null
func _read(key: String, data = null):
    return _query.call(key, data) if active() and _query.is_valid() else null
func player_position() -> Vector2: return _read("player") if active() else Vector2.ZERO
func enemy_position() -> Vector2: return _read("position") if active() else Vector2.ZERO
func environment_offset() -> Vector2: return _read("environment_offset") if active() else Vector2.ZERO
func player_velocity() -> Vector2: return _read("player_velocity") if active() else Vector2.ZERO
func enemy_health() -> float: return float(_read("hp")) if active() else 0.0
func time_seconds() -> float: return float(_read("time")) if active() else 0.0
func seconds_since_hit() -> float: return float(_read("recent_hit")) if active() else 0.0
func action_elapsed(id: String) -> float: return float(_read("cooldown", id)) if active() else 0.0
func random_range(a: float, b: float) -> float: return float(_read("random", Vector2(a,b))) if active() else a
func random_integer(a: int, b: int) -> int: return int(_read("random_int", Vector2i(a,b))) if active() else a
func set_position(at: Vector2) -> bool: return _send("position", {"value": at}) == true
func set_visibility(visible: bool) -> void: _send("visible", {"value": visible})
func set_invulnerable(value: bool) -> void: _send("invulnerable", {"value": value})
func contact_damage(previous: Vector2, radius: float, damage: float) -> bool:
    return _send("contact", {"previous": previous, "radius": radius, "damage": damage}) == true
func call_attack(id: String, options: Dictionary = {}) -> int:
    var result = _send("attack", {"id": id, "options": options})
    return int(result) if result != null else 0
func call_behavior(id: String, follow: bool = false) -> int:
    var result = _send("behavior", {"id": id, "follow": follow})
    return int(result) if result != null else 0
func branch_count() -> int: return int(_read("branch_count")) if active() else 0
func branch_has_animation(index: int) -> bool: return _read("branch_animation", index) == true
func start_branch(index: int, animate: bool = true) -> int:
    var result = _send("branch", {"index": index, "animate": animate})
    return int(result) if result != null else 0
func start_output(port: String) -> int:
    var result = _send("output", {"port": port})
    return int(result) if result != null else 0
func task_state(handle: int, mode: String = "returned") -> String:
    var result = _read("task", {"handle": handle, "mode": mode})
    return str(result) if result != null else "failure"
func cancel_task(handle: int, clear_attacks: bool = false) -> void:
    _send("cancel_task", {"handle": handle, "clear": clear_attacks})
func _close() -> void:
    super._close()
    _dispatch = Callable()
    _query = Callable()

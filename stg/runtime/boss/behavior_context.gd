@tool
extends RefCounted
## 一次阶段/子流程上下文。控制权保存在战斗实例，分支共享而不同敌人隔离。
var world
var active_node_id: String = ""
var action_running: bool = false
var action_state: String = ""
var owned_attacks: Array[int] = []
var origin: Vector2 = Vector2.ZERO
var fixed_origin: bool = false
var heading: float = 0.0
var owner_id: int = 0
var depth: int = 0
var animation_allowed: bool = true
func child() -> RefCounted:
    var result = get_script().new()
    result.world=world;result.origin=origin;result.fixed_origin=fixed_origin
    result.heading=heading;result.owner_id=owner_id;result.depth=depth+1
    result.animation_allowed=animation_allowed
    return result
func origin_position() -> Vector2: return origin if fixed_origin else world.boss
func has_attacks() -> bool:
    var remaining: Array[int]=[]
    for owner in owned_attacks:
        var alive=world.count_owned(owner)>0
        for barrage in world.barrages:
            if barrage.owner_id==owner and not barrage.is_finished(world):alive=true
        for behavior in world.behaviors:
            if behavior.owner_id==owner and not behavior.emission_finished():alive=true
        if alive:remaining.append(owner)
    owned_attacks=remaining
    return not remaining.is_empty()

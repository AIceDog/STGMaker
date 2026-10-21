@tool
extends Node2D
## 关卡实体接口 setup/tick/damage/resolve/is_drained。敌人调用正式 STGSimulation，障碍不开 AI。
signal resolved(instance_id: int, reason: String)
const Entities = preload("res://stg/definitions/entity_definitions.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
var instance_id: int
var group_id: String
var event_id: String = ""
var definition: STGWaveDefinition
var settings: STGEntitySettings
var visual_definition: Resource
var entered_screen: bool = false
var simulation: STGSimulation
var location: Vector2 # 战斗坐标；实体 Node2D 根节点保持原点，不拖动其已有攻击。
var age: float = 0 # 实体尚未死亡 / 离场时的存活秒数。
var hp: float = 100
var resolved_reason: String = ""
var contact_hit: bool = false

## 自定义初始化：at 是战斗坐标，阶段 / 事件身份供目标判定使用；障碍不创建 AI。
func setup(project: STGProject, wave: STGWaveDefinition, at: Vector2, id: int, segment_id: String, source_event: String = "") -> void:
    definition = wave
    instance_id = id
    group_id = segment_id
    event_id = source_event
    visual_definition = Entities.resolve(project, wave)
    settings = visual_definition.entity_settings
    location = at
    entered_screen = CombatSpace.BOUNDS.grow(settings.body_radius).has_point(location)
    if wave.kind == "enemy":
        simulation = STGSimulation.new()
        add_child(simulation)
        simulation.reset(project, "bosses", wave.enemy_id)
        simulation.editor_markers = false
        simulation.move_boss_frame(at - simulation.boss)

func tick(world, dt: float) -> void:
    if is_resolved():
        _tick_remaining_attacks(world, dt)
        return
    age += dt
    var previous = location
    var displacement: Vector2 = world.scroll.displacement * settings.scroll_factor if settings.movement_policy == "scroll" else Vector2.ZERO
    _update_location(world, dt, displacement)
    _check_contact_hit(world, previous)
    # 大步长测试中实体可能一次跨过整屏；扫过屏幕同样算实际入场。
    entered_screen = entered_screen or _crossed_screen(previous, location)
    if not is_resolved() and _outside_exit():
        resolve("escaped")
    if not is_resolved() and settings.lifetime > 0 and age >= settings.lifetime:
        resolve("timeout")
    queue_redraw()

func _tick_remaining_attacks(world, dt: float) -> void:
    # 离场后仍更新攻击；此时不再增加实体寿命，也不执行移动 / 接触判定。
    if simulation != null and not is_drained():
        _sync_combat_inputs(world)
        simulation.step(dt)

func _update_location(world, dt: float, displacement: Vector2) -> void:
    if simulation != null:
        _sync_combat_inputs(world)
        simulation.move_boss_frame(displacement)
        simulation.step(dt)
        location = simulation.boss
        hp = simulation.hp
        if hp <= 0:
            resolve("died")
        if not simulation.issue.is_empty():
            world.issue = simulation.issue
    else:
        location += displacement

func _check_contact_hit(world, previous: Vector2) -> void:
    if is_resolved() or contact_hit:
        return
    # Godot 内置几何查询：整段位移参与接触判定，避免高速移动穿过玩家。
    var closest = Geometry2D.get_closest_point_to_segment(world.player, previous, location)
    if world.player.distance_to(closest) <= settings.body_radius + world.player_radius:
        if simulation == null or simulation.boss_visible:
            contact_hit = true
            world.register_hit(settings.contact_damage)

func _crossed_screen(from: Vector2, to: Vector2) -> bool:
    var bounds = CombatSpace.BOUNDS.grow(settings.body_radius)
    if bounds.has_point(from) or bounds.has_point(to):
        return true
    var top_left = bounds.position
    var bottom_right = bounds.end
    var top_right = Vector2(bottom_right.x, top_left.y)
    var bottom_left = Vector2(top_left.x, bottom_right.y)
    for edge in [[top_left, top_right], [top_right, bottom_right], [bottom_right, bottom_left], [bottom_left, top_left]]:
        if Geometry2D.segment_intersects_segment(from, to, edge[0], edge[1]) != null:
            return true
    return false

func _outside_exit() -> bool:
    # 屏幕外出生不能立即回收；require_screen_entry 是实体定义的显式保护。
    if settings.require_screen_entry and not entered_screen:
        return false
    var bounds = CombatSpace.BOUNDS.grow(settings.body_radius + settings.exit_margin)
    match settings.exit_boundary:
        "left":
            return location.x < bounds.position.x
        "screen":
            return not bounds.has_point(location)
    return false

func _sync_combat_inputs(world) -> void:
    simulation.player = world.player
    simulation.player_radius = world.player_radius
    simulation.muted = world.muted
    simulation.show_collision = world.show_collision

## 自定义扣血：percent 为最大生命值百分比；真实死亡统一经 resolve 上报一次。
func damage(percent: float) -> void:
    if is_resolved() or not settings.destructible:
        return
    if simulation != null:
        # 地下无敌等现有规则仍由敌人运行器决定；没有第二套扣血 / 阶段切换逻辑。
        simulation.damage_boss(percent)
        hp = simulation.hp
    else:
        hp = maxf(0, hp - percent)
    if hp <= 0:
        resolve("died")

## 自定义生命周期入口：先保存结果再发信号；死亡与离场采用各自既有的攻击收尾规则。
func resolve(reason: String) -> void:
    if is_resolved():
        return
    resolved_reason = reason
    if simulation != null:
        if reason == "died":
            # 零步长触发敌人自身的死亡分支，立即取消行为并清攻击，不推进任何时钟。
            simulation.hp = 0
            simulation.step(0)
        else:
            _stop_enemy_behavior()
    resolved.emit(instance_id, reason)
    queue_redraw()

func _stop_enemy_behavior() -> void:
    # 越界、超时或阶段结束只取消未来发射，已发攻击留在原战斗坐标继续运行。
    if simulation.boss_player != null:
        simulation.boss_player.runner.cancel()
    simulation.boss_player = null
    simulation.boss_visible = false
    if simulation.boss_presentation != null:
        simulation.boss_presentation.hide()
    for barrage in simulation.barrages:
        barrage.cancel("stopped")
    simulation.queue_redraw()

## 自定义查询：实体本身已死亡 / 离场，不表示它的旧攻击已经耗尽。
func is_resolved() -> bool:
    return not resolved_reason.is_empty()

## 自定义查询：返回 true 后关卡可以释放根节点；其余状态仍需保留攻击容器。
func is_drained() -> bool:
    # 死亡招式可能先播放跳跃，再在落地时生成爆炸；此时暂时没有子弹也不能提前释放。
    return is_resolved() and (simulation == null or (simulation.actors.is_empty() and simulation.barrages.is_empty() and simulation.behaviors.is_empty() and simulation.effects.is_empty() and simulation.summons.is_empty() and (simulation.boss_player == null or simulation.boss_player.finished)))

func _draw() -> void: # Godot 回调
    if is_resolved():
        return
    if simulation == null:
        if visual_definition.texture != null:
            draw_texture_rect(visual_definition.texture, Rect2(location - Vector2.ONE * settings.body_radius, Vector2.ONE * settings.body_radius * 2), false, visual_definition.color)
        else:
            var points = PackedVector2Array()
            for i in 7:
                points.append(location + Vector2.from_angle(i * TAU / 7) * settings.body_radius * (1 if i % 2 == 0 else 0.85))
            draw_colored_polygon(points, visual_definition.color)
            draw_polyline(points + PackedVector2Array([points[0]]), Color("ead1a3"), 1, true)
    if settings.destructible:
        var left = location + Vector2(-18, -settings.body_radius - 10)
        draw_line(left, left + Vector2(36, 0), Color("343b4b"), 3)
        draw_line(left, left + Vector2(36 * hp / 100, 0), Color("6fe0a4"), 3)

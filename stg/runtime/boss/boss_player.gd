@tool
extends RefCounted
## 阶段接口 start/tick/status。阶段切换与死亡均立即中断旧节点。
const Context = preload("res://stg/runtime/boss/behavior_context.gd")
const Runner = preload("res://stg/runtime/boss/flow_runner.gd")
const Defaults = preload("res://stg/definitions/definition_factory.gd")
var definition: STGBossDefinition
var phase_index: int = 0
var pending_phase: int = -1
var finished: bool = false
var flow_finished: bool = false
var context
var runner
var death_started: bool = false
var death_flow_finished: bool = false
var phase_elapsed: float = 0.0
var entry_remaining: float = 0.0

## 自定义初始化：使用敌人定义的出生位置，并进入首个血量阶段。
func start(world, prefab: STGBossDefinition) -> void:
    definition = prefab
    death_started = false
    death_flow_finished = false
    world.boss = prefab.start_position
    world.hp = phase().life_hp
    _enter_phase(world)

## 自定义查询：返回当前血量阶段配置；与关卡的出场阶段是两套独立概念。
func phase() -> STGBossPhase:
    return definition.phases[phase_index]

func _enter_phase(world) -> void:
    context = Context.new()
    context.world = world
    runner = Runner.new()
    runner.start(phase().behavior_flow, context)
    pending_phase = -1
    flow_finished = false
    finished = false
    world.boss_visible = true
    phase_elapsed = 0
    entry_remaining = phase().entry_delay
    world.boss_invulnerable = entry_remaining > 0 and phase().entry_invulnerable
    if not phase().entry_barrage_id.is_empty(): world.play_barrage(phase().entry_barrage_id, world.boss)
    if not phase().entry_behavior_id.is_empty(): world.play_behavior(phase().entry_behavior_id, world.boss)

## 自定义更新：死亡立即清理；降血量换阶段需等当前动作及所属攻击收尾。
func tick(world, dt: float) -> void:
    if world.hp <= 0:
        if not resolve_depletion(world):
            _tick_death(world, dt)
            return
    if entry_remaining > 0:
        entry_remaining = maxf(0, entry_remaining - dt)
        world.boss_invulnerable = entry_remaining > 0 and phase().entry_invulnerable
        return
    phase_elapsed += dt
    if _tick_timeout(world, dt): return
    _schedule_hp_transition(world.hp)
    if pending_phase >= 0:
        _switch_phase(world,pending_phase)
        return
    if finished:
        return
    if flow_finished:
        if not context.has_attacks():
            finished = true
        return
    var result: int = runner.tick(dt)
    if result != Runner.Status.RUNNING:
        context.has_attacks() # 丢弃已完成归属，循环阶段不会无限积累历史 ID。
        if phase().loop:
            runner.reset()
        else:
            flow_finished = true

## 时间结束立即切换；血量阈值与时间结束都中断旧节点后切换。
func _tick_timeout(world, dt: float) -> bool:
    if phase().time_limit <= 0 or phase_elapsed < phase().time_limit: return false
    var target = phase_index + 1
    if phase().time_exit == "life_start":
        target = phase_index
        while target > 0 and definition.phases[target - 1].life == phase().life: target -= 1
    if phase().time_exit == "finish" or target >= definition.phases.size():
        world.hp = 0
        _tick_death(world, dt)
    else:
        _switch_phase(world, target)
    return true

func _schedule_hp_transition(hp: float) -> void:
    # 顺序阶段不会被未来的 HP 阈值提前触发；只查询当前血条内的后续阶段。
    for index in range(phase_index + 1, definition.phases.size()):
        var candidate = definition.phases[index]
        if candidate.life != phase().life: break
        if candidate.entry_mode == "hp" and hp <= candidate.enter_hp: pending_phase = index

## 扣血当帧换血条，避免关卡调度把第一条血的归零误记为真实死亡。
func resolve_depletion(world) -> bool:
    if death_started or phase().depleted_exit == "finish": return false
    var target = phase_index + 1
    if phase().depleted_exit == "auto":
        while target < definition.phases.size() and definition.phases[target].life == phase().life:
            target += 1
    if target >= definition.phases.size(): return false
    world.hp = phase().depleted_refill
    _switch_phase(world, target)
    return true

func _switch_phase(world, target: int) -> void:
    var new_life = definition.phases[target].life != phase().life
    runner.cancel()
    if new_life or definition.phases[target].clear_on_enter: world.clear_attacks()
    phase_index = target
    if new_life: world.hp = phase().life_hp
    _enter_phase(world)

func _tick_death(world, dt: float) -> void:
    # 只在真实死亡的首帧取消正常流程。后续帧推进死亡动作，不能反复清掉刚生成的攻击。
    if not death_started:
        death_started = true
        runner.cancel()
        world.clear_attacks()
        world.boss_visible = false
        var node:STGFlowNode
        if not definition.on_death_behavior_id.is_empty():
            var required=preload("res://stg/definitions/behavior_timing.gd").flow_duration(world.project.find("behaviors",definition.on_death_behavior_id),world.project)
            node=Defaults.flow_node("call",{"behavior_id":definition.on_death_behavior_id,"execution_duration":required,"wait_mode":"returned"})
        elif not definition.on_death_skill_id.is_empty():
            node=Defaults.flow_node("attack",{"barrage_id":definition.on_death_skill_id,"wait_mode":"cleared"})
        else:
            finished=true
            return
        context=Context.new();context.world=world
        runner=Runner.new();runner.start(Defaults.flow([node]),context)
        finished = false
        world.boss_visible = false
    if finished:
        return
    if not death_flow_finished:
        death_flow_finished = runner.tick(dt) != Runner.Status.RUNNING
    if death_flow_finished and not context.has_attacks():
        finished = true
        world.boss_visible = false
    # 死亡演出允许移动和发射，但不会因移动取消而恢复可受伤。
    world.boss_invulnerable = true

## 自定义状态文本：供预览查看流程进度，不参与时钟或行为决策。
func status() -> String:
    if death_started:
        return "死亡攻击结束" if finished else "死亡攻击 / 演出"
    if entry_remaining > 0: return "%s · 转场 %.1f 秒" % [phase().title, entry_remaining]
    if pending_phase >= 0:
        return phase().title + " · 等待当前动作与阶段攻击收尾"
    if finished:
        return "Boss 行为结束"
    if flow_finished:
        return phase().title + " · 等待阶段攻击结束"
    var node = phase().behavior_flow.find(context.active_node_id)
    return phase().title + " · " + (node.title + " · " + context.action_state if node != null else "选择行为")


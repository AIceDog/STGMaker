@tool
class_name STGSimulation
extends Node2D
## 运行入口 reset/step/play_barrage。UI 和导出的预制体使用同一个运行器。
const BossPlayer = preload("res://stg/runtime/boss/boss_player.gd")
const Presentation = preload("res://stg/runtime/boss/presentation_player.gd")
const Defaults = preload("res://stg/definitions/definition_factory.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const STEP = 1.0 / 120.0 # 秒；预览与导出都以 120 Hz 固定步长推进。
const MaterialPresentation = preload("res://stg/runtime/attacks/projectile_presentation.gd")
const FrameEffect = preload("res://stg/runtime/attacks/material_frame_effect.gd")
const MAX_ACTORS = 2000
signal audio_requested(stream: AudioStream, at: Vector2)
signal player_hit(damage: float)
signal boss_action_event(node_id: String, event: String)
var boss_presentation
var behavior_control:Dictionary={"movement":0,"animation":0}
var boss_invulnerable: bool = false
var boss_hit_serial: int = 0
var boss_last_hit_at: float = -1000000
var action_completed_at: Dictionary = {}
var player_velocity: Vector2 = Vector2.ZERO
var previous_player: Vector2
var player_sample_valid: bool = false

var project: STGProject
var actors: Array[STGBulletActor] = []
var summons: Array[Dictionary] = []
var barrages: Array = []
var behaviors: Array = []
var effects: Array[Dictionary] = []
var boss_player
var player: Vector2 = CombatSpace.PLAYER_SPAWN
var player_radius: float = 4
var boss: Vector2 = CombatSpace.ENEMY_SPAWN
var environment_offset: Vector2 = Vector2.ZERO # 关卡的出生偏移与卷轴位移；只作用于敌人编排，不移动攻击根节点。
var boss_visible: bool = true
var hp: float = 100
var player_last_hit_at: float = -1000000
var hits: int = 0
var time: float = 0 # 本次运行的累计秒数，动作冷却与命中时间都读取这一个时钟。
var rng = RandomNumberGenerator.new()
var program_audio_window: float = -10000
var program_audio_count: int = 0
var attack_epoch: int = 0
var presentation_clock_playing:bool=true
var presentation_rate:float=1
var presentation_enabled:bool=true
var summon_depth:int=0
var battle_budget:Dictionary={"summons":0,"actors":0}
var next_owner: int = 0
var show_collision: bool = false
var issue: String = ""
var muted: bool = true
var mode: String = ""
var completed: bool = false
var editor_markers: bool = true
var _validated_project: STGProject # 仅复用同一份只读配置；制作编辑必须传入新快照重新校验。

## 自定义入口：重置资源预览 / 导出运行；固定随机种子使相同配置可复现。
func reset(library: STGProject, kind: String, id: String, seed_value: int = 42) -> void:
    # 只接收当前配置，实例状态单独保存。
    _validated_project = null
    _reset_combat_state(library, kind, seed_value)
    if library == null or library.schema_version != STGProject.VERSION:
        issue = "资源库格式不受支持；请使用当前格式的资产索引。"
        return
    var errors = library.validate()
    issue = "；".join(errors)
    if not errors.is_empty():
        return
    var selected = library.find(kind, id)
    if selected == null:
        issue = ""
        return
    _validated_project = library
    _start_selected_resource(kind, id, selected)
    queue_redraw() # Godot 内置：请求重绘，不在逻辑更新中直接绘制。

## 重放同一份已校验的只读配置，避免拖动预览时间时重复遍历整个制作库。
## 新配置或失败状态仍走 reset；调用方无需接触运行器内部初始化顺序。
func restart_selected(id: String, seed_value: int = 42) -> void:
    var library = project
    var kind = mode
    if library == null or library != _validated_project or not issue.is_empty() or library.find(kind, id) == null:
        reset(library, kind, id, seed_value)
        return
    var selected = library.find(kind, id)
    _reset_combat_state(library, kind, seed_value)
    _start_selected_resource(kind, id, selected)
    queue_redraw()

func _reset_combat_state(library: STGProject, kind: String, seed_value: int) -> void:
    if boss_player != null:
        boss_player.runner.cancel()
    clear_attacks()
    attack_epoch += 1
    program_audio_window = -10000
    program_audio_count = 0
    if is_instance_valid(boss_presentation):
        boss_presentation.free()
    boss_presentation = Presentation.new()
    add_child(boss_presentation)
    boss_invulnerable = false
    boss_hit_serial = 0
    boss_last_hit_at = -1000000
    action_completed_at.clear()
    behavior_control={"movement":0,"animation":0}
    player_velocity = Vector2.ZERO
    player_sample_valid = false
    project = library
    mode = kind
    boss_player = null
    player = CombatSpace.PLAYER_SPAWN
    previous_player = player
    boss = CombatSpace.ENEMY_SPAWN
    environment_offset = Vector2.ZERO
    boss_visible = true
    hp = 100
    hits = 0
    player_last_hit_at = -1000000
    time = 0
    next_owner = 0
    completed = false
    rng.seed = seed_value

func _start_selected_resource(kind: String, id: String, selected: Resource) -> void:
    match kind:
        "bullets":
            preview_material(id)
        "barrages":
            play_barrage(id, boss)
        "behaviors":
            play_behavior(id, boss)
        "bosses":
            boss_presentation.configure(selected.visual_scene)
            boss_player = BossPlayer.new()
            boss_player.start(self, selected)
## 自定义接口：一个弹幕及其变形子弹共用 owner，供完成判定和停止攻击使用。
func allocate_owner() -> int:
    next_owner += 1
    return next_owner

func move_boss_frame(displacement: Vector2) -> void:
    # 关卡公开接口：平移敌人及当前移动缓存，避免 AI 下一帧把卷轴位移覆盖掉。
    # 已发出的普通子弹、区域和尾迹保持原战斗坐标，不随敌人根节点一起移动。
    boss += displacement
    environment_offset += displacement
    if boss_player != null: boss_player.runner.rebase(displacement)
    for behavior in behaviors: behavior.rebase(displacement)

## 自定义生成接口：origin 为战斗坐标，angle 为弧度；失败时记录 issue 并返回 null。






func preview_material(id:String) -> STGBulletActor:
 var material:STGBulletDefinition=project.find("bullets",id)
 if material==null:return null
 var actor=load("res://stg/runtime/attacks/program_trail.gd").new() if material.form=="trail" else load("res://stg/runtime/attacks/program_entity.gd").new()
 actor.setup(preload("res://stg/definitions/config_copy.gd").copy(material),STGAttackEntityOptions.new(),boss,0,allocate_owner())
 actor.static_preview=true
 add_child(actor);actors.append(actor);battle_budget.actors+=1
 if material.form=="trail":actor.seed_preview(boss)
 elif material.form=="laser":actor.capability="Beam2D";actor.points=PackedVector2Array([boss,boss+Vector2(material.visual.geometry.size.x,0)]);actor.width=material.visual.geometry.size.y
 actor.configure_presentation()
 return actor

func play_barrage(id: String, at: Vector2, owner_id: int = 0, heading: float = 0.0):
    var prefab: STGBarrageSkill = project.find("barrages", id)
    if prefab == null:
        issue = "招式引用不存在：" + id
        return null
    var instance = preload("res://stg/runtime/attacks/program_cast.gd").new()
    instance.world = self
    instance.start(prefab, at, owner_id if owner_id > 0 else allocate_owner(), heading, player)
    barrages.append(instance)
    return instance

## 行为资产与敌人流程共用 FlowRunner；归属和原点由调用现场显式传入。
func play_behavior(id: String, at: Vector2, owner_id: int = 0, heading: float = 0.0, depth: int = 0):
    var definition: STGBehaviorFlow = project.find("behaviors", id)
    if definition == null:
        issue = "行为引用不存在：" + id
        return null
    if depth > 32 or behaviors.size() >= 256:
        issue = "行为调用超过嵌套或并发上限，请检查循环引用"
        return null
    var data = preload("res://stg/runtime/boss/behavior_context.gd").new()
    data.world = self
    data.origin = at
    data.fixed_origin = true
    data.heading = heading
    data.owner_id = owner_id if owner_id > 0 else allocate_owner()
    data.depth = depth
    var runner = preload("res://stg/runtime/boss/flow_runner.gd").new()
    runner.start(definition, data)
    behaviors.append(runner)
    return runner

## 声音可静音；特效在同一战斗坐标实例化，离开树时与战斗一起清理。
func present_lifecycle(sound:AudioStream,scene:PackedScene,at:Vector2,heading:float=0,duration:float=2) -> void:
 if not presentation_enabled:return
 if sound!=null:create_program_presentation({"stream":sound,"position":at},0)
 if scene!=null:
  var node=create_program_presentation({"scene":scene,"position":at,"lifetime":duration},0)
  if node!=null:node.rotation=heading

func present_material_particles(scene: PackedScene, at: Vector2, heading: float, event_owner:int=0) -> void:
    if scene == null or not presentation_enabled: return
    var effect = MaterialPresentation.new()
    add_child(effect)
    effect.position = at
    effect.rotation = heading
    effect.configure(scene, "")
    effects.append({"node": effect, "natural": true,"owner":event_owner})

func present_material_expire(actor: STGBulletActor) -> void:
    if not presentation_enabled:return
    var clip = actor.definition.visual.expire_clip
    if actor.definition.visual.mode != "texture" or clip == null: return
    var effect = FrameEffect.new()
    effect.clip = clip
    effect.size = actor.definition.visual.geometry.size * actor.visual_scale
    effect.tint = actor.definition.visual.color
    effect.transform = Transform2D(actor.rotation,actor.program_position()) * actor.definition.visual.geometry.local_transform()
    add_child(effect)
    effects.append({"node": effect, "remaining": preload("res://stg/definitions/texture_frames.gd").duration(clip),"owner":actor.owner_id})

func _release_running_particles(actor: STGBulletActor) -> void:
    if not presentation_enabled:return
    if not is_instance_valid(actor.particle_presentation): return
    var effect = actor.particle_presentation
    effect.reparent(self, true)
    effect.set_emitting(false)
    actor.particle_presentation = null
    effects.append({"node": effect, "natural": true,"owner":actor.owner_id})

func present_material_hit(actor: STGBulletActor,at:Vector2=Vector2.INF) -> void:
    if not presentation_enabled:return
    var material = actor.definition
    if material.form == "moving": present_material_particles(material.hit_particles, actor.position, actor.rotation,actor.owner_id)
    var clip = material.visual.hit_clip
    if material.visual.mode != "texture" or clip == null: return
    var effect = FrameEffect.new()
    effect.clip = clip
    effect.size = material.visual.geometry.size * actor.visual_scale
    effect.tint = material.visual.color
    effect.transform = Transform2D(actor.rotation,actor.program_position() if at==Vector2.INF else at) * Transform2D(deg_to_rad(material.visual.geometry.rotation_degrees), material.visual.geometry.offset * actor.visual_scale)
    add_child(effect)
    effects.append({"node": effect, "remaining": preload("res://stg/definitions/texture_frames.gd").duration(clip),"owner":actor.owner_id})
## 自定义更新接口：dt 以秒计；敌人行为 → 攻击程序 → 攻击实体 → 回收的顺序不能互换。
func step(dt: float = STEP) -> void:
    if project == null or not issue.is_empty():
        return
    player_velocity = (player - previous_player) / maxf(dt, 0.000001) if player_sample_valid else Vector2.ZERO
    player_sample_valid = true
    previous_player = player
    time += dt
    if boss_player != null:
        boss_player.tick(self, dt)
    var behavior_index = 0
    while behavior_index < behaviors.size():
        if not behaviors[behavior_index].managed:behaviors[behavior_index].tick(dt)
        behavior_index += 1
    # Godot Array.duplicate：更新快照，变形或生成新实例不会改变本轮遍历范围。
    for instance in barrages.duplicate():
        instance.tick(self, dt)
    for actor in actors.duplicate():
        actor.show_collision = show_collision
        actor.tick(self, dt)
        if actor.alive: actor.tick_presentation(dt)
    for summon in summons.duplicate():
        var child = summon.world
        child.player = player
        child.player_radius = player_radius
        child.show_collision = show_collision
        _tick_summon(summon, dt)
        if not child.issue.is_empty(): issue = child.issue
        if summon.remaining <= 0 or child.completed:
            destroy_summon(summon)
    _remove_finished_attacks()
    # 同一时刻先结算实体及嵌套子流程，再决定宿主是否超时。
    if boss_player!=null and boss_player.runner!=null and boss_player.runner.pending_boundary():
        boss_player.runner.settle()
        boss_player.tick(self,0)
    for runner in behaviors.duplicate():
        if not runner.managed and runner.pending_boundary():runner.settle()
    _remove_finished_attacks()
    for i in range(effects.size() - 1, -1, -1):
        var effect = effects[i]
        if is_instance_valid(effect.node) and effect.node.has_method("tick") and not effect.get("manual_clock",false): effect.node.tick(dt)
        if not effect.get("natural", false): effect.remaining -= dt
        if not is_instance_valid(effect.node): effects.remove_at(i)
        elif effect.node.is_finished() if effect.get("natural", false) else effect.remaining <= 0:
            effect.node.free()
            effects.remove_at(i)
    boss_presentation.position = boss
    boss_presentation.visible = boss_visible
    completed = actors.is_empty() and barrages.is_empty() and behaviors.is_empty() and effects.is_empty() and summons.is_empty() and (boss_player == null or boss_player.finished)
    queue_redraw()

func _remove_finished_attacks() -> void:
    # 先回收子弹，再检查弹幕归属是否耗尽；避免弹幕多等待一帧。
    for i in range(actors.size() - 1, -1, -1):
        if not actors[i].alive:
            _release_running_particles(actors[i])
            actors[i].free() # Godot 内置：立即释放已完成实例，不积累等待释放节点
            actors.remove_at(i)
            battle_budget.actors=maxi(0,battle_budget.actors-1)
    for i in range(barrages.size() - 1, -1, -1):
        if barrages[i].is_finished(self):
            barrages.remove_at(i)
    for i in range(behaviors.size() - 1, -1, -1):
        if behaviors[i].is_finished(self): behaviors.remove_at(i)

func count_owned(owner_id: int, include_behaviors: bool = true) -> int:
    var count = 0
    for summon in summons:
        if summon.owner == owner_id: count += 1
    for actor in actors:
        if actor.alive and actor.owner_id == owner_id:
            count += 1
    # 分裂可先生成一个延迟发射计划。没有活弹也不能提前结束父招式。
    for instance in barrages:
        if instance.owner_id == owner_id and not instance.emission_finished():
            count += 1
    if include_behaviors:
        for behavior in behaviors:
            if behavior.owner_id == owner_id and not behavior.emission_finished(): count += 1
    return count

## 自定义扣血接口：percent 是最大生命值百分比；地下无敌等状态仍由运行器决定。
func damage_boss(percent: float) -> void:
    if boss_invulnerable or hp <= 0 or percent <= 0:
        return
    hp = maxf(0, hp - percent)
    boss_hit_serial += 1
    boss_last_hit_at = time
    if hp <= 0 and boss_player != null: boss_player.resolve_depletion(self)

func register_hit(damage: float) -> void:
    hits += 1
    player_last_hit_at = time
    player_hit.emit(damage)

## 召唤是独立敌人实例，位置与 AI 自己管理；回收不会触发死亡招式。
func spawn_summon(id: String, at: Vector2, owner_id: int, lifetime: float, entry: Dictionary = {}) -> Dictionary:
    var prefab: STGBossDefinition = project.find("bosses", id)
    if prefab == null:
        issue = "召唤敌人引用不存在：" + id
        return {}
    if battle_budget.summons>=64 or summon_depth>=8 or not is_finite(lifetime) or lifetime<=0 or lifetime>60 or not at.is_finite() or not entry.get("velocity",Vector2.ZERO).is_finite() or not is_finite(entry.get("launch",0.0)) or entry.get("launch",0.0)<0 or entry.get("launch",0.0)>60:
        issue = "达到 64 个召唤敌人上限"
        return {}
    var child = get_script().new()
    child.battle_budget=battle_budget;child.summon_depth=summon_depth+1;child.presentation_enabled=presentation_enabled;child.muted=muted
    add_child(child)
    child.set_presentation_clock(presentation_clock_playing,presentation_rate)
    # 父运行已经完整校验项目。子实例沿用相同配置，不为每次召唤重复扫描整个资源库。
    child._reset_combat_state(project, "bosses", rng.randi())
    var pending: bool = entry.get("launch", 0.0) > 0
    if not pending: child._start_selected_resource("bosses", id, prefab)
    else: child.boss_presentation.configure(prefab.visual_scene)
    child.editor_markers = false
    child.player_hit.connect(register_hit)
    child.move_boss_frame(at - child.boss)
    summons.append({"world": child, "id": id, "owner": owner_id, "remaining": lifetime, "pending": pending, "launch": entry.get("launch", 0.0), "velocity": entry.get("velocity", Vector2.ZERO), "first_step": entry.get("first_step", -1.0)})



    battle_budget.summons+=1
    return summons[-1]

func _tick_summon(summon: Dictionary, dt: float) -> void:
    var child = summon.world
    if summon.first_step >= 0:
        dt = minf(dt, summon.first_step)
        summon.first_step = -1.0
    summon.remaining -= dt
    if summon.pending:
        var move = minf(dt, summon.launch)
        child.boss += summon.velocity * move
        summon.launch -= move
        dt -= move
        child.boss_presentation.position = child.boss
        child.queue_redraw()
        if summon.launch > 0: return
        var at: Vector2 = child.boss
        child._start_selected_resource("bosses", summon.id, project.find("bosses", summon.id))
        child.move_boss_frame(at - child.boss)
        summon.pending = false
    if dt > 0: child.step(dt)

## 自定义强制清理：立即删除已有子弹，并取消所有未来发射；重置 / 死亡时调用。
func clear_attacks() -> void:
    for effect in effects:
        if is_instance_valid(effect.node): effect.node.free()
    effects.clear()
    for summon in summons.duplicate():
        destroy_summon(summon)
    summons.clear()
    for actor in actors:
        if is_instance_valid(actor):
            actor.stop()
            actor.free()
    battle_budget.actors=maxi(0,battle_budget.actors-actors.size())
    actors.clear()
    for instance in barrages:
        instance.cancel()
    barrages.clear()
    for behavior in behaviors: behavior.cancel()
    behaviors.clear()

## 自定义归属停止：实例先标记结束，由下一次 step 统一回收场景节点。
func stop_owner(owner_id:int) -> void:
 for effect in effects.duplicate():
  if effect.get("owner",-1)==owner_id:
   if is_instance_valid(effect.node):effect.node.free()
   effects.erase(effect)
 for behavior in behaviors:
  if behavior.owner_id==owner_id:behavior.cancel()
 for summon in summons.duplicate():
  if summon.owner==owner_id:destroy_summon(summon)
 for actor in actors:
  if actor.owner_id==owner_id:
   if is_instance_valid(actor.particle_presentation):actor.particle_presentation.free();actor.particle_presentation=null
   actor.stop()
 for instance in barrages:
  if instance.owner_id==owner_id:instance.cancel()

func _draw() -> void: # Godot 回调；世界占位表现，子弹由各自场景绘制。
    if project == null:
        return
    if boss_visible and (boss_presentation == null or boss_presentation.visual == null) and ((editor_markers and mode != "bullets") or mode == "bosses"):
        var definition = boss_player.definition if boss_player != null else null
        if definition != null and definition.texture != null:
            draw_texture_rect(definition.texture, Rect2(boss - Vector2(24, 24), Vector2(48, 48)), false)
        else:
            draw_circle(boss, 20, definition.color if definition != null else Color("aa8bff"))
        draw_arc(boss, 24, 0, TAU, 48, Color("d0c0ff"), 1, true)
    if editor_markers:
        draw_circle(player, 7, Color("ff3e68") if time - player_last_hit_at < 0.18 else Color("f7cedd"))
        draw_circle(player, player_radius, Color("ff547f"))


func _exit_tree() -> void:
    if boss_player != null: boss_player.runner.cancel()
    for instance in barrages: instance.cancel("removed")
    for behavior in behaviors: behavior.cancel()
    clear_attacks()


## 程序表现请求统一限流；不改变既有内置攻击的音效触发规则。
func present_program_event(life: STGAttackLifecycle, event: String, at: Vector2, angle: float, with_sound: bool = true, event_owner:int=0) -> void:
    if time-program_audio_window>=0.05:
        program_audio_window=time; program_audio_count=0
    var sound: AudioStream = life.get(event+"_sound") if with_sound else null
    if sound != null:
        if program_audio_count>=8: sound=null
        else: program_audio_count+=1
    var scene: PackedScene = life.get(event+"_effect") if effects.size()<256 else null
    if sound!=null:create_program_presentation({"stream":sound,"position":at},event_owner)
    if scene!=null:
        var node=create_program_presentation({"scene":scene,"position":at,"lifetime":life.effect_duration},event_owner)
        if node!=null:node.rotation=angle

func destroy_summon(summon:Dictionary) -> void:
 if not summons.has(summon):return
 summons.erase(summon)
 if is_instance_valid(summon.world):summon.world.clear_attacks();summon.world.free()
 battle_budget.summons=maxi(0,battle_budget.summons-1)
func create_program_presentation(data:Dictionary,owner:int):
 if not presentation_enabled or effects.size()>=256:return null
 var node=load("res://stg/runtime/attacks/program_presentation.gd").new();node.owner_id=owner;add_child(node)
 node.speed_scale=float(data.get("speed_scale",1));node.volume_db=float(data.get("volume_db",0))
 node.configure(self,data.get("position",Vector2.ZERO),data.get("stream"),data.get("scene"),data.get("lifetime",2.0),data.get("looped",false))
 node.set_clock(presentation_clock_playing,presentation_rate)
 effects.append({"node":node,"natural":true,"owner":owner,"manual_clock":data.get("manual_clock",false)});return node
func set_presentation_clock(playing:bool,speed:float) -> void:
 presentation_clock_playing=playing;presentation_rate=speed
 for effect in effects:
  if is_instance_valid(effect.node) and effect.node.has_method("set_clock"):effect.node.set_clock(playing,speed)
 for summon in summons:
  summon.world.muted=muted
  summon.world.set_presentation_clock(playing,speed)

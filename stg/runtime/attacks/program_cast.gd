@tool
extends RefCounted
## 攻击与实体程序复用能力会话，持久句柄按执行实例和战斗归属隔离。
const Session = preload("res://stg/runtime/extensions/extension_session.gd")
const Entity = preload("res://stg/runtime/attacks/program_entity.gd")
const Trail = preload("res://stg/runtime/attacks/program_trail.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
var world
var prefab: STGBarrageSkill
var owner_id: int
var _initial_origin:Vector2=Vector2.ZERO
var origin: Vector2:
    set(value):
        origin = value
        if not _started and not follow_enemy: _initial_origin=value
        if context != null: context._origin = value
var follow_enemy:bool=false
var follow_offset:Vector2=Vector2.ZERO
var heading: float
var elapsed: float = 0
var first_step_duration: float = -1
var cancelled: bool = false
var failed: bool = false
var session = Session.new()
var context: STGAttackContext
var entities: Dictionary = {}
var _ticket: int = 0
var _started: bool = false
var _commands: int = 0
var _command_time: float = -1
var _step: float = 0
var _spawn_sound_played: bool = false
var presentations:Dictionary={}
var _seed: int
func start(definition: STGBarrageSkill, at: Vector2, owner: int, angle: float = 0, _target: Vector2 = Vector2.ZERO) -> void:
    prefab = definition; origin = at; owner_id = owner; heading = angle
    _seed = world.rng.randi()
func tick(_world, dt: float) -> void:
    if cancelled: return
    if first_step_duration >= 0: dt = minf(dt, first_step_duration); first_step_duration = -1
    if follow_enemy: origin=world.boss+follow_offset
    _step = dt; _commands = 0
    elapsed += dt
    if not _started:
        _started = true
        context = STGAttackContext.new()
        context._origin = origin; context._initial_origin = _initial_origin; context._heading = heading; context._random.seed = _seed
        context._dispatch = command; context._query = query
        if not session.begin(prefab.attack_preset.program, prefab.attack_preset.parameters(prefab.program_parameters), "attack", context): _fail(session.issue); return
    if not session.finished: session.tick(dt)
    if session.failed: _fail("攻击程序报告失败")
    for ticket in presentations.keys():
        if not is_instance_valid(presentations[ticket]) or not presentations[ticket].alive:presentations.erase(ticket)
    for ticket in entities.keys():
        if _actor(_handle(int(ticket)))==null:entities.erase(ticket)
func _fail(text: String):
    failed = true
    for actor in entities.values():
        if actor is Dictionary:
            world.destroy_summon(actor)
        elif is_instance_valid(actor): actor.stop()
    world.issue = prefab.title + "：" + text
    cancel("failed")
    return null
func _actor(handle):
    if not handle is STGAttackHandle or handle._battle != world.attack_epoch or handle._execution != get_instance_id(): return null
    var actor = entities.get(handle._ticket)
    if actor is Dictionary:return actor if world.summons.has(actor) else null
    return actor if is_instance_valid(actor) and actor.alive else null
func query(key: String, handle):
    if key == "target": return world.player
    if key == "owner_position": return world.boss
    if key == "health": return world.hp
    if key == "time": return world.time
    if key == "owner_id": return owner_id
    if key == "damage": return float(prefab.attack_preset.parameters(prefab.program_parameters).get("damage",0))
    if key == "seconds_since_hit": return world.time-world.boss_last_hit_at
    if key == "action_elapsed": return world.time-world.action_completed_at.get(str(handle),-1000000.0)
    var actor = _actor(handle)
    if key == "valid": return actor!=null or _owns(handle) and is_instance_valid(presentations.get(handle._ticket)) and presentations[handle._ticket].alive
    if key == "position": return actor.world.boss if actor is Dictionary else (actor.program_position() if actor!=null else Vector2.ZERO)
    if key == "velocity": return actor.velocity if actor!=null else Vector2.ZERO
    return null
func command(key: String, data: Dictionary):
    if cancelled: return null
    return _execute(key, data)
func entity_command(key: String, data: Dictionary, own_handle: STGAttackHandle):
    if key not in ["transform","velocity","destroy"] or data.get("handle") != own_handle or _actor(own_handle)==null: return false
    return _execute(key,data)
func _execute(key: String, data: Dictionary):
    if _command_time != world.time: _command_time = world.time; _commands = 0
    _commands += 1
    if _commands > 4096: return _fail("单步程序命令超过4096次")
    for field in ["position","velocity"]:
        if data.has(field) and (not data[field] is Vector2 or not data[field].is_finite() or data[field].length()>1000000): return _fail("非有限坐标："+field)
    if data.has("rotation") and not is_finite(data.rotation): return _fail("非有限角度")
    if data.has("width") and (not is_finite(data.width) or data.width<=0 or data.width>4096): return _fail("宽度必须为0–4096之间的有限正数")
    if data.has("points"):
        if data.points.size()<2 or data.points.size()>512: return _fail("折线必须有2–512个点")
        for point in data.points:
            if not point.is_finite() or point.length()>1000000: return _fail("折线包含非有限坐标")
    if key=="create":return _create(data)
    if key=="enemy":
        if prefab.attack_preset.program.capability!="SummonEnemy":return _fail("当前程序未声明召唤能力")
        var id=prefab.attack_preset.reference_id if prefab.reference_override.is_empty() else prefab.reference_override
        var enemy=world.spawn_summon(id,data.position,owner_id,data.lifetime,{"launch":data.entry_duration,"velocity":data.velocity,"first_step":_step})
        if enemy.is_empty():return _fail(world.issue)
        enemy["source_skill"]=prefab.id
        _ticket+=1;entities[_ticket]=enemy;return _handle(_ticket)
    if key in ["sound","effect"]:
        if presentations.size()>=256:return _fail("附加表现超过256个")
        var node=world.create_program_presentation(data,owner_id)
        if node==null:return null
        if data.get("follow")!=null:
            var follow=_actor(data.follow)
            if follow==null or follow is Dictionary:node.stop();return null
            node.follow=follow;node.followed=true
        _ticket+=1;presentations[_ticket]=node;return _handle(_ticket)
    if key=="stop_presentation":
        var h=data.handle
        if not _owns(h) or not is_instance_valid(presentations.get(h._ticket)):return false
        presentations[h._ticket].stop();return true
    var actor = _actor(data.get("handle"))
    if actor == null:return false
    if actor is Dictionary:
        if key=="destroy":world.destroy_summon(actor);return true
        return false
    match key:
        "visual":
            var options:STGAttackEntityOptions=data.options
            if options==null:return false
            options.apply(actor.definition);actor.queue_redraw()
        "transform": actor.program_set_transform(data.position, data.rotation)
        "velocity": actor.velocity = data.velocity
        "points":
            if not actor is Entity or actor.capability not in ["Beam2D","Polyline2D"]: return false
            actor.points = data.points.duplicate()
            if actor.capability=="Beam2D": actor.rotation=(actor.points[-1]-actor.points[0]).angle()
        "width":
            if actor is Entity and actor.capability in ["Body2D","Area2D"]: return false
            actor.program_set_width(data.width)
        "active": actor.damaging = data.enabled
        "destroy": actor.stop()
        _: return false
    return true
func _create(data: Dictionary) -> STGAttackHandle:
    if entities.size()>=256 or world.battle_budget.actors>=world.MAX_ACTORS: _fail("程序实体数量超过上限"); return null
    var seconds: float = data.get("lifetime",0)
    if not is_finite(seconds) or seconds<=0 or seconds>60: _fail("实体寿命必须为0–60秒的有限正数"); return null
    var preset = prefab.attack_preset
    var material_id = preset.reference_id if prefab.reference_override.is_empty() else prefab.reference_override
    var material: STGBulletDefinition = world.project.find("bullets",material_id)
    var capability: String = data.capability
    if material == null or capability not in material.supported_capabilities(): _fail("素材不支持 "+capability); return null
    if capability not in ["Body2D","Trail2D","Area2D"] and not data.has("points"): _fail("缺少线段几何"); return null
    var segment: float = data.get("segment_seconds",1.0)
    if not is_finite(segment) or segment<=0 or segment>60: _fail("拖尾段寿命无效"); return null
    var options:STGAttackEntityOptions=data.get("options")
    if options==null:options=STGAttackEntityOptions.new()
    var copy:STGBulletDefinition=Copy.copy(material);options.apply(copy)
    var actor=Trail.new() if capability=="Trail2D" else Entity.new()
    var facing=data.get("velocity",Vector2.ZERO).angle() if capability=="Body2D" and data.get("velocity",Vector2.ZERO)!=Vector2.ZERO else heading
    actor.setup(copy,options,data.get("position",origin),facing,owner_id)
    if actor is Trail:actor.segment_life=segment;actor.capability="Trail2D"
    actor.lifetime = seconds; actor.velocity = data.get("velocity",Vector2.ZERO)
    actor.first_step_duration = _step
    if actor is Trail: actor.driver_position = data.get("position",origin)
    else:
        actor.capability = capability
        actor.points = data.get("points",PackedVector2Array()).duplicate()
        if capability=="Beam2D": actor.rotation=(actor.points[-1]-actor.points[0]).angle()
    if data.has("width"): actor.program_set_width(data.width)
    actor.set_meta("source_skill",prefab.id)
    world.add_child(actor);
    if world.presentation_enabled:actor.configure_presentation()
    world.actors.append(actor);world.battle_budget.actors+=1
    _ticket += 1
    entities[_ticket] = actor
    var handle = STGAttackHandle.new()
    handle._battle = world.attack_epoch; handle._execution = get_instance_id(); handle._ticket = _ticket
    if data.get("entity_program") != null:
        var binding: STGExtensionBinding = data.entity_program
        var entity_context = STGAttackEntityContext.new()
        entity_context._handle = handle; entity_context._dispatch = entity_command.bind(handle); entity_context._query = query; entity_context._random.seed = hash([_seed,_ticket])
        actor.entity_session = Session.new()
        if not actor.entity_session.begin(binding.definition,binding.parameters,"entity",entity_context): _fail(actor.entity_session.issue)
    world.present_program_event(options.lifecycle,"spawn",data.get("position",origin),heading,not _spawn_sound_played,owner_id)
    _spawn_sound_played=true
    if capability=="Body2D":world.present_material_particles(copy.spawn_particles,data.get("position",origin),heading,owner_id)
    if options.run_sound!=null:
        actor.run_presentation=world.create_program_presentation({"stream":options.run_sound,"position":actor.position,"looped":true},owner_id)
        if actor.run_presentation!=null:actor.run_presentation.follow=actor;actor.run_presentation.followed=true
    return handle
func emission_finished() -> bool: return cancelled or _started and session.finished
func is_finished(_world) -> bool:
 var done=emission_finished() and world.count_owned(owner_id,false)==0
 if done:
  for p in presentations.values():
   if is_instance_valid(p) and p.looped:p.stop()
 return done
func cancel(reason:String="stopped") -> void:
 if cancelled:return
 cancelled=true;session.cancel(reason)
 for p in presentations.values():
  if is_instance_valid(p) and (p.looped or reason in ["failed","invalid","removed"]):p.stop()
 if reason in ["failed","invalid","removed"]:
  for actor in entities.values():
   if actor is Dictionary:world.destroy_summon(actor)
   elif is_instance_valid(actor):actor.stop()

func _handle(ticket:int) -> STGAttackHandle:
 var handle=STGAttackHandle.new();handle._battle=world.attack_epoch;handle._execution=get_instance_id();handle._ticket=ticket
 return handle
func _owns(handle) -> bool:return handle is STGAttackHandle and handle._battle==world.attack_epoch and handle._execution==get_instance_id()

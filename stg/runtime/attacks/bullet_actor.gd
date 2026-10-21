@tool
class_name STGBulletActor
extends Node2D
## 子弹场景实例。setup/tick/stop 是自定义运行接口，finished 在原实例结束时发出。
signal finished
var capability:String="Body2D"
var run_presentation
const Collision = preload("res://stg/runtime/attacks/bullet_collision.gd")
const Visual = preload("res://stg/runtime/attacks/bullet_visual.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Frames = preload("res://stg/definitions/texture_frames.gd")
const Presentation = preload("res://stg/runtime/attacks/projectile_presentation.gd")
var particle_presentation: Node2D
var material_preview_time: float = 0.0
@export var definition: STGBulletDefinition
var lifecycle: STGAttackLifecycle
var static_preview: bool = false
var first_step_duration: float = -1.0
var owner_id: int = 0
var age: float = 0.0 # 从实例出生起的秒数，不含敌人行为准备时间。
var stage_index: int = -1
var speed_scale: float = 1.0 # 发射时采样，整颗子弹的后续运动阶段沿用同一个倍率。
var visual_scale: float = 1.0
var collision_scale: float = 1.0
var previous: Vector2
var alive: bool = true
var hit_once: bool = false
var next_hit_at: float = 0.0
var activation_checked: bool = false
var bounds_armed: bool = false
var show_collision: bool = false
var collision

## 自定义初始化：origin 为战斗坐标，angle 为弧度；碰撞形状只在出场时构建一次。
func setup(prefab:STGBulletDefinition, options:STGAttackEntityOptions, origin:Vector2, angle:float, instance_owner:int) -> void:
 definition=prefab;lifecycle=options.lifecycle;position=origin;previous=origin;rotation=angle;owner_id=instance_owner
 collision=Collision.build(prefab);bounds_armed=CombatSpace.BOUNDS.grow(lifecycle.bounds_margin).has_point(origin)

func tick(_world,dt:float) -> void:
 if static_preview:tick_presentation(dt)

func _crossed_exit() -> bool:
    if lifecycle.exit_mode == "ground":
        if previous.y <= lifecycle.ground_y and position.y >= lifecycle.ground_y:
            var vertical_distance = position.y - previous.y
            if vertical_distance > 0.000001:
                position = previous.lerp(position, (lifecycle.ground_y - previous.y) / vertical_distance)
            return true
        return false
    if lifecycle.exit_mode == "bounds":
        var inside = CombatSpace.BOUNDS.grow(lifecycle.bounds_margin).has_point(position)
        if inside:
            bounds_armed = true
        return bounds_armed and not inside
    return false

func _contact_damage(target: Vector2) -> float:
    var geometry = definition.collision
    if definition.form == "area" and geometry.kind == "circle":
        var point = geometry.local_transform().affine_inverse() * ((target - position).rotated(-rotation) / maxf(collision_scale, 0.00001))
        var distance = (point / (geometry.size / 2)).length()
        if distance >= lifecycle.damage_falloff_start:
            return lifecycle.damage * lifecycle.damage_falloff_scale
    return lifecycle.damage

func _expire(world) -> void:
 world.present_program_event(lifecycle,"expire",position,rotation,true,owner_id)
 _emit_successor(world,lifecycle.on_expire_barrage_id,lifecycle.on_expire_behavior_id)
 if definition.visual.expire_clip!=null:world.present_material_expire(self)
 stop()

func _emit_successor(world, barrage_id: String, behavior_id: String, event_position: Vector2 = Vector2.INF) -> void:
    var at = position if event_position == Vector2.INF else event_position
    if not barrage_id.is_empty():
        world.play_barrage(barrage_id, at, owner_id, rotation)
    if not behavior_id.is_empty():
        world.play_behavior(behavior_id, at, owner_id, rotation)



func stop() -> void:
    if is_instance_valid(run_presentation):run_presentation.stop()
    if not alive:
        return
    alive = false
    finished.emit()

func _exit_tree() -> void:
    pass

## 表现与正式运行状态分开，创建和推进由 simulation 统一调用。
func configure_presentation() -> void:
    if definition.form == "moving" and definition.run_particles != null:
        particle_presentation = Presentation.new()
        add_child(particle_presentation)
        particle_presentation.configure(definition.run_particles, "")
        particle_presentation.place(self)

func tick_presentation(dt: float) -> void:
    material_preview_time += dt
    if is_instance_valid(particle_presentation):
        particle_presentation.place(self)
        particle_presentation.tick(dt)
    queue_redraw()

func current_texture() -> Texture2D:
    var visual = definition.visual
    var seconds = material_preview_time if static_preview else age
    var run_start: float = 0.0
    if not static_preview and visual.spawn_clip != null:
        run_start = Frames.duration(visual.spawn_clip)
        if seconds < run_start: return Frames.texture_at(visual.spawn_clip, seconds)
    if visual.run_clip != null: return Frames.texture_at(visual.run_clip, maxf(0, seconds - run_start), true)
    return visual.texture

## 自定义绘制查询：返回当前透明度，不改变运行状态。
func opacity() -> float:
    return 1.0

func _draw() -> void: # Godot 回调：引擎要求重绘时调用
    Visual.draw(self)




func geometry_snapshot() -> Dictionary:
 var at=program_position() if has_method("program_position") else position
 if capability in ["Body2D","Trail2D"]:return {"kind":"path","points":PackedVector2Array([at])}
 if capability in ["Beam2D","Polyline2D"]:return {"kind":"geometry","points":get("points").duplicate()}
 var shape=definition.visual.geometry
 var outline=shape.outline();var transform=Transform2D(rotation,position)*shape.local_transform()
 for i in outline.size():outline[i]=transform*outline[i]
 if not outline.is_empty():outline.append(outline[0])
 return {"kind":"geometry","points":outline}

func program_position() -> Vector2:return position

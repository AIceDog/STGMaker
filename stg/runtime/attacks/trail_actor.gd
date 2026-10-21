@tool
class_name STGBulletTrailActor
extends STGBulletActor
## 尾迹子弹接口 tick/rebase。每段使用独立出生时间，旧段留在战斗坐标里。
const TrailVisual = preload("res://stg/runtime/attacks/trail_visual.gd")
const MAX_SEGMENTS = 1024
var segments: Array = [] # {a, b, born, distance}；端点为战斗坐标，born 为本实例的出生秒数。
var segment_life:float=1.0
var recording: bool = false
var last_sample: Vector2
var last_emitter: Vector2
var has_sample: bool = false
var distance: float = 0 # 已生成尾迹的累计长度，用于连续贴图 UV。
var emitter_path: Array = [] # {point, distance}；仅保留尾部偏移所需的一小段真实路径。
var path_distance: float = 0 # 发射者真实路径的累计长度，用于按路程取尾部偏移。

## 自定义覆盖：尾迹段保存绝对战斗坐标，Node2D 保持原点，忽略普通子弹的朝向。
func setup(prefab:STGBulletDefinition,options:STGAttackEntityOptions,origin:Vector2,_angle:float,instance_owner:int) -> void:
 definition=prefab;lifecycle=options.lifecycle;owner_id=instance_owner
 position=Vector2.ZERO;last_sample=origin;last_emitter=origin;texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
 var geometry:STGBulletGeometry=prefab.collision.duplicate(true);geometry.offset=Vector2.ZERO;geometry.rotation_degrees=0
 collision=Collision.for_geometry(geometry)



func seed_preview(origin: Vector2) -> void:
    # 单独编辑尾迹定义时展示静态示意，不假装这就是 Boss 的实际路径。
    segments = [{"a": origin, "b": origin + Vector2(100, 30), "born": 0.0, "distance": 0.0}, {"a": origin + Vector2(100, 30), "b": origin + Vector2(200, 0), "born": 0.0, "distance": 104.4}]

func tick(_world,dt:float) -> void:
 if static_preview:tick_presentation(dt)

func _tick_segments(world) -> void:
    # 每段使用 age - born；后生成的段不能继承整条尾迹已经消耗的寿命。
    var life = segment_life
    for i in range(segments.size() - 1, -1, -1):
        var part = segments[i]
        var part_age: float = age - part.born
        if part_age + 0.000001 >= life:
            segments.remove_at(i)
            continue
        var can_hit = age >= next_hit_at if lifecycle.hit_mode == "repeat" else not hit_once
        if can_hit and is_active(part_age):
            var ends = definition.collision.trail_endpoints(part.a, part.b)
            var closest = Geometry2D.get_closest_point_to_segment(world.player, ends[0], ends[1])
            if _segment_hits(part, part_age, world.player, world.player_radius):
                hit_once = true
                next_hit_at = age + lifecycle.hit_interval
                preload("res://stg/runtime/extensions/hit_effects.gd").apply(self, world, lifecycle.damage, closest)
                world.present_program_event(lifecycle,"hit",closest,rotation,true,owner_id)
                if definition.visual.hit_clip!=null:world.present_material_hit(self,closest)
                _emit_successor(world, lifecycle.on_hit_barrage_id, lifecycle.on_hit_behavior_id, closest)

func _segment_hits(part: Dictionary, part_age: float, target: Vector2, radius: float) -> bool:
    var geometry = definition.collision
    if geometry.kind == "rectangle":
        var ends = geometry.trail_endpoints(part.a, part.b)
        var closest = Geometry2D.get_closest_point_to_segment(target, ends[0], ends[1])
        return target.distance_to(closest) <= collision_radius(part_age) + radius
    var placement = Transform2D((part.b - part.a).angle(), (part.a + part.b) / 2) * geometry.local_transform()
    var scale_factor = 1.0
    placement *= Transform2D(0, Vector2(part.a.distance_to(part.b), scale_factor), 0, Vector2.ZERO)
    return collision.hits_at(placement, Vector2.ZERO, target, radius)

func _sample(at: Vector2) -> void:
    var delta = at - last_emitter
    var previous_emitter = last_emitter
    last_emitter = at
    if delta.length() > definition.trail_break_distance:
        has_sample = false
        emitter_path = [{"point": at, "distance": 0.0}]
        path_distance = 0
        return # 瞬移会断开尾迹，不生成横跨画面的攻击线。
    if delta.length_squared() < 0.000001:
        return
    if emitter_path.is_empty():
        emitter_path.append({"point": previous_emitter, "distance": 0.0})
    var step_length: float = at.distance_to(emitter_path[-1].point)
    if step_length < definition.trail_spacing:
        return
    path_distance += step_length
    emitter_path.append({"point": at, "distance": path_distance})
    if path_distance < definition.trail_offset:
        return
    # 按走过的路程向后取点；直接减当前朝向会在突然转弯时把尾迹甩出真实路径。
    var sample_distance = path_distance - definition.trail_offset
    var point = _point_at_path_distance(sample_distance)
    _append_segment(point)

func _point_at_path_distance(sample_distance: float) -> Vector2:
    # 只保留目标路程左右的相邻样本，避免发射者历史路径无限增长。
    while emitter_path.size() > 1 and emitter_path[1].distance <= sample_distance:
        emitter_path.pop_front()
    var point: Vector2 = emitter_path[0].point
    if emitter_path.size() > 1:
        var before = emitter_path[0]
        var after = emitter_path[1]
        point = before.point.lerp(after.point, (sample_distance - before.distance) / (after.distance - before.distance))
    return point

func _append_segment(point: Vector2) -> void:
    if not has_sample:
        last_sample = point
        has_sample = true
        return
    var length = last_sample.distance_to(point)
    if length < definition.trail_spacing:
        return
    segments.append({"a": last_sample, "b": point, "born": age, "distance": distance})
    if segments.size() > MAX_SEGMENTS:
        segments.pop_front()
    distance += length
    last_sample = point
func is_active(part_age: float) -> bool:
    return part_age >= 0 and part_age < segment_life

## 自定义查询：把单段执行期秒数换成 0..1，供表现 / 碰撞曲线共享。
func stage_progress(part_age: float) -> float:
    return clampf(part_age / segment_life, 0, 1)

## 自定义查询：返回单段当前碰撞半径，独立于贴图的视觉宽度。
func collision_radius(part_age: float) -> float:
    return definition.collision.size.y / 2 * 1.0

## 自定义查询：返回单段透明度，预警、执行和淡出使用各自的年龄区间。
func segment_opacity(part_age: float) -> float:
    return 1.0 if is_active(part_age) else 0.0

func rebase(offset: Vector2) -> void:
    for part in segments:
        part.a -= offset
        part.b -= offset
    for sample in emitter_path:
        sample.point -= offset
    last_sample -= offset
    last_emitter -= offset

func _draw() -> void: # Godot 回调；实际绘制在独立模块。
    if definition != null:
        TrailVisual.draw(self)



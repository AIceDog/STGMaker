@tool
extends RefCounted
## 轨迹只读采样器：隔离配置与运行状态，复用正式 STGSimulation 的 120 Hz 更新。
## 每帧分批推进；取消时结束扩展实例。结果保存战斗坐标，不随预览缩放重新模拟。
const MAX_SEGMENTS = 8192 # 包括高亮副本；基础线段最多占一半。
const MAX_SECONDS = 8.0
const MAX_PATHS = 48
const MAX_ACTIVE_ACTORS = 512
const SAMPLE_EVERY = 4 # 30 Hz 记录点；运动执行仍然是正式运行器的 120 Hz。
const STEPS_PER_FRAME = 8
const FRAME_BUDGET_US = 4000
const SEED = 42
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
var paths: Array[Dictionary] = []
var running: bool = false
var limited: bool = false
var omitted_forms: bool = false
var issue: String = ""
var revision: int = 0
var _skill_id: String = ""
var target: Vector2
var _world: STGSimulation
var _tracked: Dictionary = {}
var _seen: Dictionary = {}
var _steps: int = 0
var _point_count:int=0
const MAX_POINTS=32768
var _draw_key: Array = []
var _past_lines = PackedVector2Array()
var _future_lines = PackedVector2Array()
var _highlight_past = PackedVector2Array()
var _highlight_future = PackedVector2Array()
var _markers=PackedVector2Array()

func start(project: STGProject, id: String, player: Vector2) -> void:
    cancel()
    paths.clear()
    _tracked.clear()
    _seen.clear()
    _draw_key.clear()
    limited = false
    omitted_forms = false
    issue = ""
    _steps = 0
    _point_count=0
    target = player
    _skill_id = id
    revision += 1
    if project == null or project.find("barrages", id) == null:
        return
    # 与导出共用依赖闭包，只复制当前招式需要的配置；大型库拖动目标时不复制所有敌人。
    var closure = Compiler.compile_library(project, [{"collection": "barrages", "id": id}])
    if not closure.issue.is_empty():
        issue = closure.issue
        return
    _world = STGSimulation.new()
    # 不加入 SceneTree：采样没有窗口、自动播放、输入或外接音频 / 命中监听器。
    # 编译结果隔离阶段、曲线、形状和参数，只读美术与扩展声明遵守现有共享契约。
    _world.presentation_enabled=false
    _world.reset(closure.library, "barrages", id, SEED)
    _world.muted = true
    _world.editor_markers = false
    _world.player = player
    _world.previous_player = player
    issue = _world.issue
    running = issue.is_empty()
    if not running:
        _free_world()

func advance(step_limit: int = STEPS_PER_FRAME, budget_us: int = FRAME_BUDGET_US) -> bool:
    # 返回本批是否改变路径，供画布重绘；没有异步协程，取消后不会留下后台任务。
    if not running:
        return false
    var started = Time.get_ticks_usec()
    for i in step_limit:
        _world.step()
        _steps += 1
        _capture(_steps % SAMPLE_EVERY == 0)
        if not _world.issue.is_empty():
            issue = _world.issue
        if _world.battle_budget.actors + _world.battle_budget.summons > MAX_ACTIVE_ACTORS:
            limited = true
            _finish()
            break
        if not issue.is_empty() or _world.completed or _steps * STGSimulation.STEP >= MAX_SECONDS:
            limited = limited or not _world.completed
            _finish()
            break
        if budget_us > 0 and Time.get_ticks_usec() - started >= budget_us:
            break
    revision += 1
    return true

func _capture(record_existing:bool) -> void:
    if _world==null:return
    var sources=[]
    for actor in _world.actors:sources.append({"key":actor.get_instance_id(),"node":actor,"geometry":actor.geometry_snapshot(),"skill":actor.get_meta("source_skill","")})
    for summon in _world.summons:
        sources.append({"key":summon.world.get_instance_id(),"node":null,"geometry":{"kind":"path","points":PackedVector2Array([summon.world.boss])},"skill":summon.get("source_skill",""),"summon":summon})
    var fresh=sources.filter(func(source):return not _seen.has(source.key))
    var chosen=mini(MAX_PATHS-paths.size(),fresh.size())
    if chosen<fresh.size():limited=true
    for i in chosen:
        var source=fresh[floori(float(i)*fresh.size()/chosen)]
        var geometry=source.geometry
        if geometry.points.is_empty():continue
        var record={"points":PackedVector2Array(),"times":PackedFloat64Array(),"skill":source.skill,"kind":geometry.kind,"frames":[],"last_frame":-100.0}
        _tracked[source.key]=paths.size();paths.append(record)
        if source.node!=null:source.node.finished.connect(_record_finished.bind(source.node),CONNECT_ONE_SHOT)
    for source in sources:_seen[source.key]=true
    for source in sources:
        if not _tracked.has(source.key):continue
        var record=paths[_tracked[source.key]];var geometry=source.geometry
        if geometry.kind=="path":
            if source.has("summon") and not source.summon.pending and not record.points.is_empty():continue
            var point:Vector2=geometry.points[0]
            if point.is_finite() and (record.points.is_empty() or record_existing and point.distance_squared_to(record.points[-1])>.01):
                if _point_count>=MAX_POINTS:limited=true;continue
                record.points.append(point);record.times.append(_world.time);_point_count+=1
        elif record.frames.is_empty() or record_existing and _world.time-record.last_frame>=.5 and record.frames.size()<16:
            if _point_count+geometry.points.size()>MAX_POINTS:limited=true;continue
            if not Array(geometry.points).all(func(p):return p.is_finite()):continue
            record.frames.append({"points":geometry.points,"time":_world.time});record.last_frame=_world.time;_point_count+=geometry.points.size()

func _record_finished(actor: STGBulletActor) -> void:
    # 命中 / 越界会在本次 step 内回收节点；结束信号保留精确终点而不额外推进一帧。
    if not is_instance_valid(_world) or not _tracked.has(actor.get_instance_id()):
        return
    var record = paths[_tracked[actor.get_instance_id()]]
    if record.kind!="path" or record.points.is_empty() or _point_count>=MAX_POINTS:return
    if record.points[-1].distance_squared_to(actor.program_position()) > 0.01:
        record.points.append(actor.program_position())
        record.times.append(_world.time)
        _point_count+=1

func _finish() -> void:
    _capture(true)
    running = false
    _free_world()

func cancel() -> void:
    running = false
    _free_world()

func clear() -> void:
    cancel()
    paths.clear()
    _draw_key.clear()
    issue = ""
    revision += 1

func _free_world() -> void:
    if is_instance_valid(_world):
        _stop_instances(_world)
        _world.free()
    _world = null

func _stop_instances(world: STGSimulation) -> void:
    # 脱离 SceneTree 的 Node 不会收到 _exit_tree，必须显式停止扩展与行为执行器。
    if world.boss_player != null:
        world.boss_player.runner.cancel()
    for summon in world.summons:
        _stop_instances(summon.world)
    for actor in world.actors:
        actor.stop()
    world.clear_attacks()

func status() -> String:
    if not issue.is_empty():
        return "轨迹预估不可用：" + issue
    var text = "轨迹预估 · 当前目标固定"
    if running:
        text += " · 采样中"
    elif limited and paths.is_empty():
        text = "前 8 秒没有飞行弹道 · 更晚事件请开始测试"
    elif limited:
        text += " · 已截取（最多 8 秒 / 48 条）"
    elif paths.is_empty():
        text = "暂无攻击轨迹"
    if omitted_forms:
        text += " · 含攻击范围几何"
    return text

func draw(layer: Control, canvas: Control, played_time: float) -> void:
    # 重绘频繁但模拟与折线缓存独立；暂停、改颜色或缩放不会重复执行运动脚本。
    var key = [revision, floori(played_time * 30), canvas.screen_rect(), canvas.zoom()]
    if key != _draw_key:
        _draw_key = key
        _past_lines.clear()
        _future_lines.clear()
        _highlight_past.clear()
        _highlight_future.clear()
        _markers.clear()
        for stored in paths:
            var record=stored
            if not stored.frames.is_empty():
                var frame=stored.frames[0]
                for candidate in stored.frames:
                    if candidate.time<=played_time:frame=candidate
                record=stored.duplicate();record.points=frame.points;record.times=PackedFloat64Array();record.times.resize(frame.points.size());record.times.fill(frame.time)
            if record.points.size()==1 and canvas.screen_rect().has_point(canvas.overlay_point(record.points[0])):
                _markers.append(canvas.overlay_point(record.points[0]))
            var selected = record.get("skill", "") == canvas.host.selected_id
            var phase = 0.0
            for i in range(1, record.points.size()):
                if _past_lines.size() + _future_lines.size() >= MAX_SEGMENTS: break
                if not record.points[i - 1].is_finite() or not record.points[i].is_finite(): continue
                var clipped = _clip_segment(canvas.overlay_point(record.points[i - 1]), canvas.overlay_point(record.points[i]), canvas.screen_rect())
                if clipped.is_empty(): continue
                var a: Vector2 = clipped[0]
                var b: Vector2 = clipped[1]
                if record.times[i] <= played_time:
                    _past_lines.append_array(PackedVector2Array([a, b]))
                    if selected: _highlight_past.append_array(PackedVector2Array([a, b]))
                else:
                    var start = _future_lines.size()
                    phase = _dash_segment(a, b, phase)
                    if selected: _highlight_future.append_array(_future_lines.slice(start))
    for point in _markers:layer.draw_circle(point,6,Color("55dfbc"),false,1.5)
    if not _past_lines.is_empty():
        layer.draw_multiline(_past_lines, Color(0.35, 0.76, 0.82, 0.24), 1.0, true)
    if not _future_lines.is_empty():
        layer.draw_multiline(_future_lines, Color(0.35, 0.84, 0.88, 0.58), 1.3, true)
    if not _highlight_past.is_empty(): layer.draw_multiline(_highlight_past, Color(1, 0.75, 0.47, 0.42), 1.4, true)
    if not _highlight_future.is_empty(): layer.draw_multiline(_highlight_future, Color(1, 0.75, 0.47, 0.85), 1.8, true)

func _dash_segment(a: Vector2, b: Vector2, phase: float) -> float:
    const DASH = 7.0
    const PERIOD = 12.0
    var length = a.distance_to(b)
    if length < 0.001:
        return phase
    var direction = (b - a) / length
    var distance = 0.0
    while distance < length and _past_lines.size() + _future_lines.size() < MAX_SEGMENTS:
        var in_dash = phase < DASH
        var span = minf((DASH if in_dash else PERIOD) - phase, length - distance)
        if in_dash and span > 0.001:
            _future_lines.append_array(PackedVector2Array([a + direction * distance, a + direction * (distance + span)]))
        distance += maxf(span, 0.001)
        phase = fmod(phase + maxf(span, 0.001), PERIOD)
    return phase

func _clip_segment(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
    # 裁剪发生在虚线细分之前，极远但有限的坐标也不能生成数百万段。
    if not a.is_finite() or not b.is_finite(): return PackedVector2Array()
    var d = b - a
    if not d.is_finite(): return PackedVector2Array()
    var lower = 0.0
    var upper = 1.0
    var p = [-d.x, d.x, -d.y, d.y]
    var q = [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
    for i in 4:
        if absf(p[i]) < 0.0000001:
            if q[i] < 0: return PackedVector2Array()
        else:
            var ratio: float = q[i] / p[i]
            if p[i] < 0: lower = maxf(lower, ratio)
            else: upper = minf(upper, ratio)
            if lower > upper: return PackedVector2Array()
    return PackedVector2Array([a + lower * d, a + upper * d])

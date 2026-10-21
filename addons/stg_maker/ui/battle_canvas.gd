@tool
extends Control
## 场景画布：坐标换算、控制点和一次拖动的临时副本。运动预览始终调用 STGSimulation。
## screen/value 与玩家控制接口是自定义方法；_ready/_draw/_gui_input 才是 Godot 回调。
var host
var source_project: STGProject
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
var world: Node2D
var edit_mode: String = "none"
var handles: Array = []
var dragging: int = -1
var path: Curve2D
var path_scope: Array = []
var path_key: String = "path"
var path_origin: Vector2
var path_angle: float = 0
var path_scale: Vector2 = Vector2.ONE
const PlayerControls = preload("res://addons/stg_maker/ui/preview_player.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const BattleOverlay = preload("res://addons/stg_maker/ui/battle_overlay.gd")
const Entities = preload("res://stg/definitions/entity_definitions.gd")
const TrajectoryPreview = preload("res://addons/stg_maker/ui/trajectory_preview.gd")
const ARENA = CombatSpace.BOUNDS
var battle_screen: Control # 只裁剪战斗内容；外层画布仍可绘制屏幕边框、路径手柄与提示。
var battle_overlay: Control
var player_controls = PlayerControls.new()
var dragging_player: bool = false
var level_shoot_held: bool = false
var trajectory = TrajectoryPreview.new()
var _trajectory_last_request: int = 0
var _trajectory_active: bool = false
var _seek_target_steps: int = -1
var _seek_steps: int = 0
var _budget_frame: int = -1
var _budget_started: int = 0
var _budget_steps: int = 0

func reserve_preview_step() -> bool:
    # 播放、定位和只读轨迹共享本帧的八步 / 4ms 预算。
    var frame = Engine.get_process_frames()
    if _budget_frame != frame:
        _budget_frame = frame
        _budget_started = Time.get_ticks_usec()
        _budget_steps = 0
    if _budget_steps >= 8 or Time.get_ticks_usec() - _budget_started >= 4000: return false
    _budget_steps += 1
    return true

func _ready() -> void: # Godot 回调
    focus_mode = Control.FOCUS_ALL
    focus_exited.connect(release_player_controls)
    get_window().focus_exited.connect(release_player_controls)
    custom_minimum_size = Vector2(460, 320)
    battle_screen = Control.new()
    battle_screen.clip_contents = true # Godot 内置：攻击离开虚拟屏幕后不绘制到留黑区和旁边的 UI。
    battle_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(battle_screen)
    world = STGSimulation.new()
    battle_screen.add_child(world)
    battle_overlay = BattleOverlay.new()
    battle_overlay.canvas = self
    battle_screen.add_child(battle_overlay)
    world.audio_requested.connect(_sound)
    resized.connect(update_screen_transform)
    update_screen_transform()

func _exit_tree() -> void:
    trajectory.cancel()

func _process(_delta: float) -> void:
    if host == null or world == null:
        return
    if is_seeking():
        if host.collection != "barrages" or not is_visible_in_tree() or host.playing:
            cancel_seek()
        else:
            _advance_seek()
    if not _trajectories_enabled():
        if trajectory.running or not trajectory.paths.is_empty():
            trajectory.clear()
        _trajectory_active = false
        return
    if not _trajectory_active:
        request_trajectories()
    # 移动玩家会改变瞄准 / 追踪结果；最多每 180 ms 重建，避免拖动时每帧复制资源库。
    var now = Time.get_ticks_msec()
    if world.player.distance_squared_to(trajectory.target) > 1.0 and now - _trajectory_last_request >= 180:
        request_trajectories()
    var changed = false
    while trajectory.running and reserve_preview_step():
        changed = trajectory.advance(1, 0) or changed
    if changed:
        battle_overlay.queue_redraw()
        queue_redraw()

func _trajectories_enabled() -> bool:
    return host != null and host.collection == "barrages" and host.show_trajectories and is_visible_in_tree()

func set_trajectories_visible(enabled: bool) -> void:
    host.show_trajectories = enabled
    request_trajectories()
    queue_redraw()
    battle_overlay.queue_redraw()

func request_trajectories() -> void:
    _trajectory_last_request = Time.get_ticks_msec()
    _trajectory_active = _trajectories_enabled()
    if _trajectory_active:
        trajectory.start(host.session.project, host.selected_id, world.player)
    else:
        trajectory.clear()

func is_seeking() -> bool:
    return _seek_target_steps >= 0

func seek_destination() -> float:
    return _seek_target_steps * STGSimulation.STEP if is_seeking() else world.time

func cancel_seek() -> void:
    if is_seeking() and world != null and host != null:
        world.muted = not host.sound_enabled
    _seek_target_steps = -1

func seek_preview(seconds: float) -> void:
    # 时间滑块只重放预览，不写配置、撤销栈或策划文件；采用同一个固定随机种子。
    if host.collection != "barrages" or not world.issue.is_empty():
        return
    host.playing = false
    host.accumulator = 0
    release_player_controls()
    var target = world.player
    cancel_seek()
    world.muted = true
    var library = host.session.project
    var selected = library.find("barrages", host.selected_id)
    if source_project == library and world.mode == "barrages" and selected != null:
        # Session 每次编辑替换快照。运行器只重放同一份已校验快照；新快照仍完整校验。
        world.restart_selected(host.selected_id, TrajectoryPreview.SEED)
    else:
        reset_preview()
        world.restart_selected(host.selected_id, TrajectoryPreview.SEED)
    world.player = target
    world.previous_player = target
    for barrage in world.barrages:
        barrage.locked_player = target
    world.show_collision = host.show_collision
    # 重放期间静音，完成后恢复当前声音设置；跳到某时刻不应集中播放中间的枪声。
    world.muted = true
    _seek_target_steps = roundi(clampf(seconds, 0, TrajectoryPreview.MAX_SECONDS) / STGSimulation.STEP)
    _seek_steps = 0
    if not world.issue.is_empty() or _seek_target_steps == 0:
        _seek_target_steps = -1
        world.muted = not host.sound_enabled
    battle_overlay.queue_redraw()
    queue_redraw()

func _advance_seek() -> void:
    world.muted = true
    var started = Time.get_ticks_usec()
    for i in 8:
        if not reserve_preview_step(): break
        world.step()
        _seek_steps += 1
        if _seek_steps >= _seek_target_steps or not world.issue.is_empty():
            cancel_seek()
            break
        if Time.get_ticks_usec() - started >= 4000:
            break
    if not is_seeking():
        world.muted = not host.sound_enabled
    battle_overlay.queue_redraw()
    queue_redraw()

func screen_rect() -> Rect2:
    var font_height = get_theme_default_font_size()
    var top = maxf(44, font_height + 24)
    var bottom = maxf(42, font_height + 20)
    var available = Rect2(Vector2(16, top), Vector2(maxf(1, size.x - 32), maxf(1, size.y - top - bottom)))
    return CombatSpace.fit_screen(available)

func zoom() -> float: return screen_rect().size.x / CombatSpace.DESIGN_SIZE.x
# screen / value 在画布像素与 960×540 设计坐标间换算；原点始终在虚拟屏幕中心。
func screen(point: Vector2) -> Vector2: return screen_rect().get_center() + point * zoom()
func value(point: Vector2) -> Vector2: return (point - screen_rect().get_center()) / zoom()

func update_screen_transform() -> void:
    var frame = screen_rect()
    battle_screen.position = frame.position
    battle_screen.size = frame.size
    world.position = frame.size / 2.0
    world.scale = Vector2.ONE * zoom()
    queue_redraw()
    battle_overlay.queue_redraw()

func reset_preview() -> void:
    if world == null: return
    cancel_seek()
    release_player_controls()
    var level_mode = host.collection in ["levels", "waves", "obstacles"]
    if level_mode != (world is STGLevelSimulation):
        world.free()
        world = STGLevelSimulation.new() if level_mode else STGSimulation.new()
        battle_screen.add_child(world)
        battle_screen.move_child(world, 0)
        world.audio_requested.connect(_sound)
        update_screen_transform()
    source_project = host.session.project
    var closure = Compiler.compile_library(source_project, [{"collection": host.collection, "id": host.selected_id}]) if not host.selected_id.is_empty() else {"library": STGProject.create(), "issue": ""}
    if not closure.issue.is_empty():
        world.reset(STGProject.create(), host.collection, host.selected_id)
        world.issue = closure.issue
        world.completed = false
    else:
        if level_mode: world.reset(closure.library, host.collection, host.selected_id, host.segment_index if host.level_test_from_selected else 0)
        else: world.reset(closure.library, host.collection, host.selected_id)
    if host.collection == "bosses" and host.boss_phase() != null: world.hp = host.boss_phase().enter_hp
    world.show_collision = host.show_collision
    world.muted = not host.sound_enabled
    world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if host.pixel_art else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    if world.issue.is_empty(): world.step()
    request_trajectories()
    rebuild()

func rebuild() -> void:
    handles.clear()
    path = null
    path_scale = Vector2.ONE
    dragging = -1
    var resource = host.current()
    if resource == null or edit_mode == "none":
        queue_redraw()
        return
    if resource is STGLevelDefinition:
        if edit_mode == "level_spawn" and host.level_event() != null:
            handles.append({"kind": "level_spawn", "point": host.level_event().spawn_position})
        queue_redraw()
        return
    path_origin = world.boss
    path_angle = 0
    if edit_mode in ["path", "skill_path", "flight_path"]:
        if resource is STGBossDefinition or resource is STGBehaviorFlow:
            var binding = motion_binding()
            if not binding.is_empty() and binding.definition.mode == "curve":
                path = binding.definition.path; path_scope = binding.scope; path_key = "path"
                if path != null: path_origin -= path.get_point_position(0)
        if path != null:
            # 拖动只更新这份临时路径；鼠标释放时才提交一次配置快照。
            path = path.duplicate(true)
            _path_handles()
    elif edit_mode in ["target", "skill_target"]:
        var binding = motion_binding()
        if not binding.is_empty():
            var move = binding.definition
            path_origin = {"relative": world.boss, "player": world.player, "world": Vector2.ZERO}[move.target_mode]
            handles.append({"kind": "boss_target", "point": path_origin + move.target})
    queue_redraw()



func _path_handles() -> void:
    handles.clear()
    for i in path.point_count:
        var anchor = path.get_point_position(i) * path_scale
        handles.append({"kind": "point", "index": i, "point": path_origin + anchor.rotated(path_angle)})
        handles.append({"kind": "in", "index": i, "point": path_origin + (anchor + path.get_point_in(i) * path_scale).rotated(path_angle)})
        handles.append({"kind": "out", "index": i, "point": path_origin + (anchor + path.get_point_out(i) * path_scale).rotated(path_angle)})

func _draw() -> void: # Godot 回调；draw_* 是 Godot 内置绘制方法。
    draw_rect(Rect2(Vector2.ZERO, size), Color("080e16"))
    var frame = screen_rect()
    draw_rect(frame, Color("0c1622"))
    for x in range(int(ARENA.position.x), int(ARENA.end.x) + 1, 60):
        draw_line(screen(Vector2(x, ARENA.position.y)), screen(Vector2(x, ARENA.end.y)), Color("233446"))
    for y in range(int(ARENA.position.y), int(ARENA.end.y) + 1, 60):
        draw_line(screen(Vector2(ARENA.position.x, y)), screen(Vector2(ARENA.end.x, y)), Color("233446"))
    draw_rect(frame, Color("7894b0"), false, 2)
    battle_overlay.queue_redraw()
    var font = get_theme_font("font", "Label")
    var font_size = get_theme_default_font_size()
    draw_string(font, Vector2(16, font_size + 10), "虚拟屏幕 · 3840:2160（16:9）", HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, font_size, Color("b9cbdc"))
    var hint = "点击屏幕后 WASD 移动 · 玩家在左 / 敌人在右" if edit_mode == "none" else ("局部路径：拖动点与灰色手柄 · 双击加点 · 右键删点" if edit_mode in ["path", "skill_path", "flight_path"] else "拖动橙色控制点编辑 · 一次拖动可一次撤销")
    if edit_mode == "none" and size.x < 600: hint = "WASD 移动 · 左玩家 / 右敌人"
    if world is STGLevelSimulation and edit_mode == "none": hint = "WASD 移动 · 按住空格测试射击"
    draw_string(font, Vector2(16, size.y - 12), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, font_size, Color("b9cbdc"))

func overlay_point(point: Vector2) -> Vector2:
    return screen(point) - screen_rect().position

func draw_edit_overlay(layer: Control) -> void:
    # 自定义绘制接口：使用屏幕局部坐标，路径和控制点与攻击一起裁剪。
    if _trajectories_enabled():
        trajectory.draw(layer, self, world.time)
        var font = get_theme_font("font", "Label")
        var font_size = maxi(12, get_theme_default_font_size() - 2)
        layer.draw_string(font, Vector2(10, font_size + 7), trajectory.status(), HORIZONTAL_ALIGNMENT_LEFT, battle_screen.size.x - 20, font_size, Color("8ec9d0"))
    _draw_selected_attack(layer)
    _draw_level_spawn_overlay(layer)
    _draw_path_overlay(layer)
    _draw_barrage_spawn_overlay(layer)
    if edit_mode in ["target", "skill_target"] and not handles.is_empty():
        layer.draw_line(overlay_point(world.boss), overlay_point(handles[0].point), Color("55dfbc"), 2, true)
        layer.draw_circle(overlay_point(handles[0].point), 14, Color("ffbf79"), false, 2, true)
    for handle in handles:
        var tangent = handle.kind in ["in", "out"]
        layer.draw_circle(overlay_point(handle.point), 3.5 if tangent else 5, Color("91a9bf") if tangent else Color("ffbf79"))

func _draw_level_spawn_overlay(layer: Control) -> void:
    if host == null or not host.current() is STGLevelDefinition or edit_mode != "level_spawn" or host.level_event() == null:
        return
    var event = host.level_event()
    var wave = host.session.project.find("waves", event.wave_id)
    if wave == null:
        return
    var settings = Entities.settings(host.session.project, wave)
    var radius = settings.body_radius if settings != null else 18.0
    for i in wave.count:
        var point = overlay_point(event.spawn_position + wave.offset(i))
        layer.draw_circle(point, radius * zoom(), Color("ffbf79"), false, 2, true)
    var origin = overlay_point(event.spawn_position)
    layer.draw_line(origin - Vector2(16, 0), origin + Vector2(16, 0), Color("55dfbc"), 2)

func _draw_path_overlay(layer: Control) -> void:
    if path == null:
        return
    var line = PackedVector2Array()
    for point in path.get_baked_points():
        line.append(overlay_point(path_origin + (point * path_scale).rotated(path_angle)))
    if line.size() > 1:
        layer.draw_polyline(line, Color("55dfbc"), 2, true)
    for i in path.point_count:
        var anchor = overlay_point(path_origin + (path.get_point_position(i) * path_scale).rotated(path_angle))
        for tangent in [path.get_point_in(i), path.get_point_out(i)]:
            var end = overlay_point(path_origin + ((path.get_point_position(i) + tangent) * path_scale).rotated(path_angle))
            layer.draw_line(anchor, end, Color("738ba1"))

func _draw_barrage_spawn_overlay(_layer:Control) -> void:
    pass

func _gui_input(event: InputEvent) -> void: # Godot 回调
    if _handle_preview_key(event):
        accept_event()
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _left_button_input(event)
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and path != null:
        _remove_path_point(event.position)
    elif event is InputEventMouseMotion:
        _pointer_motion_input(event)

func _handle_preview_key(event: InputEvent) -> bool:
    if edit_mode != "none":
        return false
    if event is InputEventKey and world is STGLevelSimulation:
        var space = event.physical_keycode == KEY_SPACE or event.keycode == KEY_SPACE
        if space and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
            level_shoot_held = event.pressed
            return true
    return player_controls.handle_key(event)

func _left_button_input(event: InputEventMouseButton) -> void:
    if event.pressed:
        # 输入焦点只在画布内取得；失焦由 release_player_controls 清空测试按键。
        grab_focus()
        for i in handles.size():
            if screen(handles[i].point).distance_to(event.position) < 10:
                dragging = i
                break
        if event.double_click and edit_mode in ["path", "skill_path", "flight_path"] and dragging < 0 and path != null:
            var point = (value(event.position) - path_origin).rotated(-path_angle) / path_scale
            path.add_point(point, Vector2.ZERO, Vector2.ZERO, path.point_count - 1)
            host.edit_path(path_scope, path_key, path)
        elif edit_mode == "none":
            dragging_player = screen(world.player).distance_to(event.position) <= 16
            if dragging_player:
                player_controls.clear()
                host.playing = false
    else:
        if dragging >= 0:
            var handle = handles[dragging]
            dragging = -1
            # 释放前只动临时 handles / path；这里才把整次拖动写进一次撤销。
            if path != null:
                host.edit_path(path_scope, path_key, path)
            else:
                _commit_handle(handle)
        dragging_player = false

func _remove_path_point(at: Vector2) -> void:
    for handle in handles:
        var middle_point = handle.kind == "point" and handle.index > 0 and handle.index < path.point_count - 1
        if middle_point and screen(handle.point).distance_to(at) < 10:
            path.remove_point(handle.index)
            host.edit_path(path_scope, path_key, path)
            break

func _pointer_motion_input(event: InputEventMouseMotion) -> void:
    if edit_mode == "none" and dragging_player and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
        cancel_seek()
        var margin = Vector2.ONE * world.player_radius
        world.player = value(event.position).clamp(ARENA.position + margin, ARENA.end - margin)
        world.queue_redraw()
        battle_overlay.queue_redraw()
        queue_redraw()
        host.update_preview_ui()
    elif dragging >= 0:
        var handle = handles[dragging]
        handle.point = value(event.position)
        if path != null:
            _update_path_handle(handle)
        queue_redraw()
        accept_event()

func _update_path_handle(handle: Dictionary) -> void:
    # 鼠标先转设计坐标，再撤销路径朝向；曲线中的点和切线保存的是局部坐标。
    var point = (handle.point - path_origin).rotated(-path_angle) / path_scale
    match handle.kind:
        "point":
            if handle.index > 0 or host.collection == "barrages":
                path.set_point_position(handle.index, point)
        "in": path.set_point_in(handle.index, point - path.get_point_position(handle.index))
        "out": path.set_point_out(handle.index, point - path.get_point_position(handle.index))
    var active_index = dragging
    _path_handles()
    dragging = active_index

func _commit_handle(handle: Dictionary) -> void:
    var local: Vector2 = handle.point - path_origin
    if handle.kind == "level_spawn":
        host.edit_path(host.level_event_scope(), "spawn_position", handle.point, true)
        return
    if handle.kind == "boss_target":
        host.edit_path(motion_binding().scope, "target", local)
        return
func _sound(stream: AudioStream, _at: Vector2) -> void:
    var audio = AudioStreamPlayer.new()
    audio.stream = stream
    add_child(audio)
    audio.finished.connect(audio.queue_free)
    audio.play()

func release_player_controls() -> void:
    # 自定义公开接口；离开画布、切换工具或窗口失焦时清空按键，避免“卡住”移动。
    player_controls.clear()
    dragging_player = false
    level_shoot_held = false

func control_player(dt: float, paused: bool = false) -> void:
    if is_seeking():
        return
    if world is STGLevelSimulation: world.set_audio_paused(paused)
    if not is_visible_in_tree() or not has_focus() or edit_mode != "none":
        release_player_controls()
        return
    player_controls.move(world, dt, ARENA)
    if world is STGLevelSimulation and not paused and level_shoot_held: world.shoot_player()
    if paused:
        # 继续播放时，不把整段暂停移动误判成一帧速度。
        world.previous_player = world.player
        world.player_velocity = Vector2.ZERO
        world.player_sample_valid = false
        if world is STGLevelSimulation: world.reset_player_sample()

func step_preview(dt: float = STGSimulation.STEP) -> void:
    cancel_seek()
    if world is STGLevelSimulation: world.set_audio_paused(false)
    control_player(dt)
    world.step(dt)

func motion_binding() -> Dictionary:
    if host.current() is STGBossDefinition or host.current() is STGBehaviorFlow:
        var node=host.boss_node()
        if node!=null and node.behavior_preset!=null and node.behavior_preset.program!=null and "movement" in node.behavior_preset.program.capabilities:
            return {"definition":node.parameters(),"scope":host.boss_node_scope()+["program_parameters"]}
    return {}

func _can_drop_data(at: Vector2, data) -> bool: # Godot 拖放目标回调
    return screen_rect().has_point(at) and host.LevelCommands.accepts_drop(host, data)

func _drop_data(at: Vector2, data) -> void: # Godot 拖放目标回调
    host.LevelCommands.drop_resource(host, data, host.segment_index, 0, value(at))

func _draw_selected_attack(layer: Control) -> void:
    if host.collection != "barrages": return
    var count = 0
    for actor in world.actors:
        if actor.get_meta("source_skill", "") != host.selected_id: continue
        layer.draw_circle(overlay_point(actor.position), maxf(5, minf(18, actor.definition.visual.geometry.size.length() / 2 * zoom() + 3)), Color("ffbf79"), false, 1.5, true)
        count += 1
        if count >= 128: break

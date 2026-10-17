@tool
extends Control
## 完整计划时间轴：阶段重排 / 长度、跨阶段出场拖动、资源拖放。释放时才提交一次历史。
const Timing = preload("res://stg/definitions/level_timing.gd")
const Tracks = preload("res://addons/stg_maker/ui/timeline_tracks.gd")
const Selection = preload("res://addons/stg_maker/ui/timeline_selection.gd")
signal selection_changed(count: int)
var host
var selected_event_ids: Array = []
var selection_level_id: String = ""
var snap_interval: float = 0.1
var drag_origin_time: float = 0
var drag_delta: float = 0
var marquee_origin: Vector2
var marquee_rect: Rect2
var marquee_seed: Array = []
var zoom_factor: float = 1
var environment_visible: bool = true
var geometry: Dictionary = {}
var rectangles: Dictionary = {} # 当前阶段事件矩形，保留简洁的查询接口。
var drag_kind: String = ""
var source_index: int = 0
var source_event: String = ""
var drop_index: int = 0
var temporary_time: float = 0 # 整关计划坐标；提交时才换算成目标阶段内时间。
var temporary_duration: float = 0
var grab_offset: float = 0
var panning: bool = false
var hover_rect: Rect2

func _ready() -> void: # Godot 回调
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_exited.connect(func(): hover_rect = Rect2(); mouse_default_cursor_shape = Control.CURSOR_ARROW; queue_redraw())

func set_zoom(value: float) -> void:
	zoom_factor = clampf(value, 1, 16)
	if is_instance_valid(host.timeline_zoom): host.timeline_zoom.set_value_no_signal(zoom_factor)
	queue_redraw()

func fit_all() -> void:
	set_zoom(1)
	host.timeline_scroll.scroll_horizontal = 0

func set_snap_interval(value: float) -> void:
	snap_interval = maxf(0, value)

func snapped_time(value: float) -> float:
	return snappedf(value, snap_interval if snap_interval > 0 else 0.01)

func clear_selection() -> void:
	_set_selection([])

func _set_selection(ids: Array) -> void:
	if selected_event_ids == ids: return
	selected_event_ids = ids.duplicate()
	selection_changed.emit(selected_event_ids.size())
	queue_redraw()

func _repair_selection(level: STGLevelDefinition) -> void:
	if selection_level_id != level.id:
		selection_level_id = level.id
		clear_selection()
	var valid: Array = []
	for entry in Selection.events(level, selected_event_ids): valid.append(entry.id)
	_set_selection(valid)

func time_x(value: float) -> float:
	# 使用未滚动的 Control 局部坐标；ScrollContainer 负责横向平移，不改事件时间。
	var left = get_theme_default_font_size() * 5.5
	return left + value / maxf(0.1, Timing.total(host.current())) * maxf(1, size.x - left - 30)

func x_time(value: float, clamp_to_level: bool = true) -> float:
	var left = get_theme_default_font_size() * 5.5
	var result = (value - left) / maxf(1, size.x - left - 30) * Timing.total(host.current())
	return clampf(result, 0, Timing.total(host.current())) if clamp_to_level else result

func event_rect(index: int, id: String) -> Rect2:
	for entry in geometry.get("events", []):
		if entry.index == index and entry.id == id: return entry.rect
	return Rect2()

func _draw() -> void: # Godot 回调；draw_* 为内置绘制方法。
	if host == null or host.collection != "levels" or host.current() == null: return
	var level: STGLevelDefinition = host.current()
	_repair_selection(level)
	var font = get_theme_font("font", "Label")
	var font_size = get_theme_default_font_size()
	custom_minimum_size.x = maxf(320, (host.timeline_scroll.size.x - 20) * zoom_factor)
	geometry = Tracks.build(host.session.project, level, size.x, font_size, environment_visible)
	custom_minimum_size.y = geometry.height
	rectangles.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color("101a28"))
	_draw_time_grid(level, font, font_size)
	_draw_track_labels(font, font_size)
	_draw_segments(level, font, font_size)
	_draw_events(font, font_size)
	_draw_environment(level, font, font_size)
	if hover_rect.has_area() and drag_kind.is_empty():
		draw_rect(hover_rect.grow(1.5), Color("c5e6ee"), false, 1.5)
	_draw_playhead(font_size)
	_draw_drag(font, font_size)

func _draw_time_grid(level: STGLevelDefinition, font: Font, font_size: int) -> void:
	var interval = maxf(1, ceilf(Timing.total(level) / (8 * zoom_factor)))
	for i in int(Timing.total(level) / interval) + 1:
		var at = i * interval
		var x = time_x(at)
		draw_line(Vector2(x, font_size + 10), Vector2(x, size.y), Color("263b51"), 1)
		draw_string(font, Vector2(x, font_size + 3), "%.0fs" % at, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("adbed2"))

func _draw_track_labels(font: Font, font_size: int) -> void:
	for label in geometry.labels:
		draw_string(font, Vector2(8, label.y), label.title, HORIZONTAL_ALIGNMENT_LEFT, font_size * 5, font_size, Color("92aac2"))

func _draw_segments(level: STGLevelDefinition, font: Font, font_size: int) -> void:
	for index in geometry.segments.size():
		var segment = level.segments[index]
		var rect: Rect2 = geometry.segments[index]
		var selected = index == host.segment_index
		draw_rect(rect, Color("36516b") if selected else Color("243648"))
		if selected:
			draw_rect(rect, Color("ffbf79"), false, 2)
		var prefix = "◆ " if segment.exit_rule.mode != "time" else ""
		draw_string(font, rect.position + Vector2(5, font_size + 3), prefix + segment.title, HORIZONTAL_ALIGNMENT_LEFT, maxf(0, rect.size.x - 12), font_size, Color.WHITE)
		# 阶段右缘画出双线手柄，和横向缩放鼠标指针对应。
		for offset in [4, 7]:
			draw_line(rect.end - Vector2(offset, rect.size.y - 6), rect.end - Vector2(offset, 6), Color("99afc7"), 1)

func _draw_events(font: Font, font_size: int) -> void:
	for entry in geometry.events:
		var rect: Rect2 = entry.rect
		if entry.index == host.segment_index:
			rectangles[entry.id] = rect
		draw_rect(rect, Color("416875") if entry.kind == "enemy" else Color("795e46"))
		if selected_event_ids.has(entry.id) or (selected_event_ids.is_empty() and entry.index == host.segment_index and entry.id == host.event_id):
			draw_rect(rect, Color("ffbf79"), false, 2)
		draw_string(font, rect.position + Vector2(4, font_size + 1), entry.event.title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, font_size, Color.WHITE)
		draw_line(Vector2(rect.position.x, rect.end.y - 2), Vector2(rect.position.x + entry.generation_width, rect.end.y - 2), Color("64e0c0"), 3)

func _draw_environment(level: STGLevelDefinition, font: Font, font_size: int) -> void:
	for entry in geometry.environment:
		var rect: Rect2 = entry.rect
		draw_rect(rect, Color("294537"))
		var speed = level.segments[entry.index].scroll_speed
		draw_string(font, rect.position + Vector2(5, font_size + 1), "停止" if speed == 0 else "向左 %.0f" % speed, HORIZONTAL_ALIGNMENT_LEFT, maxf(0, rect.size.x - 8), font_size)
	if geometry.has("music"):
		var rect: Rect2 = geometry.music
		draw_rect(rect, Color("39364e"))
		draw_string(font, rect.position + Vector2(5, font_size + 1), "背景音乐" if level.music != null else "未绑定音乐 · 点击配置", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, font_size)

func _draw_playhead(font_size: int) -> void:
	if host.canvas.world is STGLevelSimulation and host.canvas.world.definition != null:
		var x = time_x(host.canvas.world.planned_time())
		draw_line(Vector2(x, font_size + 10), Vector2(x, size.y), Color("ff6d95"), 2)

func _draw_drag(font: Font, font_size: int) -> void:
	if drag_kind == "event":
		var x = time_x(temporary_time)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("ffbf79"), 2)
		draw_string(font, Vector2(x + 4, font_size * 2 + 8), "%.2fs · %d 条 · %+.2fs" % [temporary_time, selected_event_ids.size(), drag_delta], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		for entry in geometry.events:
			if selected_event_ids.has(entry.id):
				var ghost: Rect2 = entry.rect
				ghost.position.x = time_x(entry.at + drag_delta)
				draw_rect(ghost, Color(1, 0.75, 0.47, 0.24))
				draw_rect(ghost, Color("ffbf79"), false, 2)
	elif drag_kind == "marquee":
		draw_rect(marquee_rect, Color(0.39, 0.88, 0.75, 0.12))
		draw_rect(marquee_rect, Color("64e0c0"), false, 1.5)
	elif drag_kind == "segment":
		var rect: Rect2 = geometry.segments[drop_index]
		draw_rect(rect, Color("64e0c0"), false, 3)
	elif drag_kind == "resize":
		var x = time_x(Timing.start(host.current(), source_index) + temporary_duration)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("ffbf79"), 2)

func _gui_input(event: InputEvent) -> void: # Godot 原生输入回调
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin_drag(event.position, event.ctrl_pressed or event.shift_pressed)
			else: _commit_drag()
			queue_redraw()
			accept_event()
		elif event.ctrl_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_zoom(zoom_factor * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8))
			accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		drag_kind = ""
		clear_selection()
		accept_event()
	elif event is InputEventMouseMotion:
		_update_hover(event.position)
		if panning:
			host.timeline_scroll.scroll_horizontal -= roundi(event.relative.x)
			accept_event()
		elif not drag_kind.is_empty():
			_update_drag_position(event.position)
			queue_redraw()
			accept_event()

func _update_hover(at: Vector2) -> void:
	# 矩形沿用绘制后的同一份布局；提示与拖动不能各算一套命中范围。
	var next_rect = Rect2()
	var cursor = Control.CURSOR_ARROW
	for entry in geometry.get("events", []):
		if entry.rect.has_point(at):
			next_rect = entry.rect
			cursor = Control.CURSOR_DRAG
			break
	if not next_rect.has_area():
		for rect in geometry.get("segments", []):
			if rect.has_point(at):
				next_rect = rect
				cursor = Control.CURSOR_HSIZE if at.x >= rect.end.x - 8 else Control.CURSOR_DRAG
				break
	if not next_rect.has_area():
		for entry in geometry.get("environment", []):
			if entry.rect.has_point(at):
				next_rect = entry.rect
				cursor = Control.CURSOR_POINTING_HAND
				break
	if not next_rect.has_area() and geometry.has("music") and geometry.music.has_point(at):
		next_rect = geometry.music
		cursor = Control.CURSOR_POINTING_HAND
	mouse_default_cursor_shape = cursor
	if hover_rect != next_rect:
		hover_rect = next_rect
		queue_redraw()

func _begin_drag(at: Vector2, additive: bool = false) -> void:
	grab_focus()
	_repair_selection(host.current())
	if _begin_event_drag(at, additive) or _begin_segment_drag(at):
		return
	if _select_environment_at(at): return
	marquee_origin = at
	marquee_rect = Rect2(at, Vector2.ZERO)
	marquee_seed = selected_event_ids.duplicate() if additive else []
	drag_kind = "marquee"
	_set_selection(marquee_seed)

func _begin_event_drag(at: Vector2, additive: bool = false) -> bool:
	for entry in geometry.get("events", []):
		if not entry.rect.has_point(at):
			continue
		source_index = entry.index
		source_event = entry.id
		var ids = selected_event_ids.duplicate()
		if additive:
			if ids.has(entry.id): ids.erase(entry.id)
			else: ids.append(entry.id)
		elif not ids.has(entry.id): ids = [entry.id]
		_set_selection(ids)
		if not ids.has(entry.id): return true
		drag_kind = "event"
		temporary_time = entry.at
		drag_origin_time = entry.at
		drag_delta = 0
		grab_offset = at.x - time_x(entry.at)
		host.segment_index = entry.index
		host.select_level_event(entry.id)
		return true
	return false

func _begin_segment_drag(at: Vector2) -> bool:
	for index in geometry.get("segments", []).size():
		var rect: Rect2 = geometry.segments[index]
		if not rect.has_point(at):
			continue
		source_index = index
		clear_selection()
		drop_index = index
		drag_kind = "resize" if at.x >= rect.end.x - 8 else "segment"
		temporary_duration = host.current().segments[index].duration
		grab_offset = 0
		host.select_level_segment(index)
		host.select_inspector_tab(1)
		return true
	return false

func _select_environment_at(at: Vector2) -> bool:
	for entry in geometry.get("environment", []):
		if entry.rect.has_point(at):
			clear_selection()
			host.select_level_segment(entry.index)
			host.select_inspector_tab(1)
			return true
	if geometry.has("music") and geometry.music.has_point(at):
		clear_selection()
		host.select_inspector_tab(2)
		return true
	return false

func _update_drag_position(at: Vector2) -> void:
	# 移动过程中只更新临时显示；不修改 Resource，也不持续追加撤销快照。
	var time = x_time(at.x - grab_offset)
	match drag_kind:
		"event":
			var plan = Selection.plan(host.current(), selected_event_ids, snapped_time(time) - drag_origin_time)
			drag_delta = plan.delta
			temporary_time = drag_origin_time + drag_delta
		"marquee":
			marquee_rect = Rect2(marquee_origin, at - marquee_origin).abs()
			var ids = marquee_seed.duplicate()
			for entry in geometry.events:
				if marquee_rect.intersects(entry.rect) and not ids.has(entry.id): ids.append(entry.id)
			_set_selection(ids)
		"segment": drop_index = Timing.segment_at(host.current(), time)
		_:
			var start = Timing.start(host.current(), source_index)
			temporary_duration = clampf(snapped_time(x_time(at.x, false) - start), 0.1, 600)

func _commit_drag() -> void:
	# 先退出拖动状态，再提交一次事务；同步触发的界面刷新不再读临时拖动值。
	var kind = drag_kind
	drag_kind = ""
	if kind == "event":
		host.LevelCommands.move_events(host, selected_event_ids, drag_delta, source_event)
	elif kind == "marquee" and not selected_event_ids.is_empty():
		for entry in geometry.events:
			if selected_event_ids.has(entry.id):
				host.segment_index = entry.index
				host.select_level_event(entry.id)
				break
	elif kind == "segment":
		host.LevelCommands.move_segment(host, source_index, drop_index)
	elif kind == "resize" and not is_equal_approx(host.current().segments[source_index].duration, temporary_duration):
		host.LevelCommands.resize_segment(host, temporary_duration, source_index)

func _get_tooltip(at: Vector2) -> String: # Godot 提示回调
	if host == null or host.collection != "levels" or not host.current() is STGLevelDefinition:
		return "关卡时间轴用于安排阶段和出场；切换到关卡后选择具体内容进行编辑。"
	for entry in geometry.get("events", []):
		if entry.rect.has_point(at): return "%s\n整关计划 %.2fs · 阶段开始后 %.2fs\n点击在右侧编辑；Ctrl / Shift 点击可多选。\n拖动已选条一起改时间，释放后只提交一次修改。\n跨阶段时换算为新阶段内时间；\n击败目标不能跨阶段，此时整批保持原位。\n绿色底线表示生成过程，条结束后敌人继续战斗。" % [entry.event.title, entry.at, entry.event.at]
	for index in geometry.get("segments", []).size():
		if geometry.segments[index].has_point(at):
			var segment = host.current().segments[index]
			var rule = segment.exit_rule
			var ending = STGLevelExitRule.MODE_LABELS[STGLevelExitRule.MODES.find(rule.mode)]
			if rule.mode != "time":
				ending += " · " + STGLevelExitRule.CONDITION_LABELS[STGLevelExitRule.CONDITIONS.find(rule.condition)]
			return "%s · 计划长度 %.2fs\n结束：%s。\n点击在右侧修改结束条件与卷轴。\n拖动中部调整阶段顺序，拖动右边缘改计划长度；\n◆ 表示结束还要检查条件。\n条件阶段的实际耗时可能与计划不同，\n后续阶段按真实结束时间推进。" % [segment.title, segment.duration, ending]
	for entry in geometry.get("environment", []):
		if entry.rect.has_point(at): return "点击选中这个阶段，在右侧设置关卡卷轴速度。\n实体是否跟随卷轴由自身设置决定，\n已发射的子弹继续独立运动。"
	if geometry.has("music") and geometry.music.has_point(at):
		return "点击打开整关的背景 / 音乐属性；这是环境设置，不会改变敌人出场或行为流程。"
	return "整关计划时间轴：前段等待时，后段整体顺延。\nCtrl / Shift 点选多条，或从空白处拖框选；\n按住 Ctrl / Shift 框选会追加，Esc 清除或取消拖动。\n多选拖动保持时间间距，到整关边界时一起停止。\nCtrl + 滚轮缩放；中键拖动平移。\n把左侧素材拖入可新增出场，时间按工具栏的吸附设置对齐。"

func _can_drop_data(_at: Vector2, data) -> bool: # Godot 拖放目标回调
	return host.LevelCommands.accepts_drop(host, data)

func _drop_data(at: Vector2, data) -> void: # Godot 拖放目标回调
	var time = clampf(snapped_time(x_time(at.x)), 0, Timing.total(host.current()))
	var index = Timing.segment_at(host.current(), time)
	host.LevelCommands.drop_resource(host, data, index, snappedf(time - Timing.start(host.current(), index), 0.01))

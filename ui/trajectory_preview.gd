@tool
extends RefCounted
## 轨迹只读采样器：隔离配置与运行状态，复用正式 STGSimulation 的 120 Hz 更新。
## 每帧分批推进；取消时结束扩展实例。结果保存战斗坐标，不随预览缩放重新模拟。
const MAX_SECONDS = 8.0
const MAX_PATHS = 48
const MAX_ACTIVE_ACTORS = 512
const SAMPLE_EVERY = 4 # 30 Hz 记录点；运动执行仍然是正式运行器的 120 Hz。
const STEPS_PER_FRAME = 48
const FRAME_BUDGET_US = 2500
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
var _draw_key: Array = []
var _past_lines = PackedVector2Array()
var _future_lines = PackedVector2Array()
var _highlight_past = PackedVector2Array()
var _highlight_future = PackedVector2Array()

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
	_world.reset(closure.library, "barrages", id, SEED)
	_world.muted = true
	_world.editor_markers = false
	_world.player = player
	_world.previous_player = player
	# call_start 瞄准在 reset 时锁定；此处同步到用户正在预览的目标位置。
	for barrage in _world.barrages:
		barrage.locked_player = player
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
		if _world.actors.size() > MAX_ACTIVE_ACTORS:
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

func _capture(record_existing: bool) -> void:
	var fresh: Array = []
	for actor in _world.actors:
		var key = actor.get_instance_id()
		if _seen.has(key):
			continue
		_seen[key] = true
		# 激光是线段 / 曲线、区域是覆盖范围、尾迹是空间轨迹，均不伪装成飞行弹道。
		if actor.definition.form != "moving":
			omitted_forms = true
			continue
		fresh.append(actor)
	var available = MAX_PATHS - paths.size()
	var chosen = mini(available, fresh.size())
	if chosen < fresh.size():
		limited = true
	# 同帧大量生成时均匀选取整个扇面 / 圆环，避免只画出紧邻的前 48 颗。
	for i in chosen:
		var actor = fresh[floori(float(i) * fresh.size() / chosen)]
		var record = {"points": PackedVector2Array([actor.previous, actor.position]),
			"times": PackedFloat64Array([maxf(0, _world.time - STGSimulation.STEP), _world.time]),
			"skill": actor.get_meta("source_skill", "")}
		_tracked[actor.get_instance_id()] = paths.size()
		paths.append(record)
		actor.finished.connect(_record_finished.bind(actor), CONNECT_ONE_SHOT)
	if not record_existing:
		return
	for actor in _world.actors:
		var key = actor.get_instance_id()
		if not _tracked.has(key):
			continue
		var record = paths[_tracked[key]]
		if record.points[-1].distance_squared_to(actor.position) > 0.01:
			record.points.append(actor.position)
			record.times.append(_world.time)

func _record_finished(actor: STGBulletActor) -> void:
	# 命中 / 越界会在本次 step 内回收节点；结束信号保留精确终点而不额外推进一帧。
	if not is_instance_valid(_world) or not _tracked.has(actor.get_instance_id()):
		return
	var record = paths[_tracked[actor.get_instance_id()]]
	if record.points[-1].distance_squared_to(actor.position) > 0.01:
		record.points.append(actor.position)
		record.times.append(_world.time)

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
		text = "暂无飞行弹道"
	if omitted_forms:
		text += " · 激光 / 区域看实际范围"
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
		for record in paths:
			var selected = record.get("skill", "") == canvas.host.selected_id
			var phase = 0.0
			for i in range(1, record.points.size()):
				var a = canvas.overlay_point(record.points[i - 1])
				var b = canvas.overlay_point(record.points[i])
				if record.times[i] <= played_time:
					_past_lines.append_array(PackedVector2Array([a, b]))
					if selected: _highlight_past.append_array(PackedVector2Array([a, b]))
				else:
					var start = _future_lines.size()
					phase = _dash_segment(a, b, phase)
					if selected: _highlight_future.append_array(_future_lines.slice(start))
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
	while distance < length:
		var in_dash = phase < DASH
		var span = minf((DASH if in_dash else PERIOD) - phase, length - distance)
		if in_dash and span > 0.001:
			_future_lines.append_array(PackedVector2Array([a + direction * distance, a + direction * (distance + span)]))
		distance += maxf(span, 0.001)
		phase = fmod(phase + maxf(span, 0.001), PERIOD)
	return phase

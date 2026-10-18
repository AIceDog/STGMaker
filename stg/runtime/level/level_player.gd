@tool
class_name STGLevelSimulation
extends Node2D
## 关卡运行入口 reset/step/shoot_player/damage_entity。预览与导出使用这一套调度。
## 片段计时、编队计时和敌人 AI 共用 dt；等清场只阻止进入下一片段，不冻结当前战斗。
signal audio_requested(stream: AudioStream, at: Vector2)
signal player_hit(damage: float)
signal entity_resolved(instance_id: int, reason: String)
signal finished
const Defaults = preload("res://stg/definitions/definition_factory.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Scroll = preload("res://stg/runtime/level/scroll_player.gd")
const WavePlayer = preload("res://stg/runtime/level/wave_player.gd")
const EntityPlayer = preload("res://stg/runtime/level/entity_player.gd")
const Background = preload("res://stg/runtime/level/background_player.gd")
const PlayerShots = preload("res://stg/runtime/level/player_shots.gd")
const Goals = preload("res://stg/runtime/level/goal_player.gd")
const Timing = preload("res://stg/definitions/level_timing.gd")
const Entities = preload("res://stg/definitions/entity_definitions.gd")
const MAX_ENTITIES = 96
var project: STGProject
var definition: STGLevelDefinition
var scroll = Scroll.new()
var player_shots = PlayerShots.new()
var goals = Goals.new()
var background
var music_player: AudioStreamPlayer
var audio_paused: bool = true
var entities: Array = []
var wave_jobs: Array = []
var fired_events: Dictionary = {}
var resolved_entities: Dictionary = {}
var next_instance_id: int = 0
var segment_index: int = 0
var segment_elapsed: float = 0 # 当前阶段的实际秒数，等待目标时继续增加。
var waiting_clear: bool = false
var condition_failure: String = "" # 未达成的游戏目标不冻结战斗；issue 只接收资源 / 程序错误。
var time: float = 0 # 本次测试 / 运行的累计秒数；从中间阶段测试时从零开始。
var player: Vector2 = CombatSpace.PLAYER_SPAWN
var player_radius: float = 4
var player_velocity: Vector2 = Vector2.ZERO
var previous_player: Vector2
var player_sample_valid: bool = false
var player_last_hit_at: float = -1000
var hits: int = 0
var issue: String = ""
var completed: bool = false
var show_collision: bool = false
var muted: bool = true
var editor_markers: bool = true
# 与工作台的公共预览接口保持一致；关卡不运行一个总 Boss，也不使用总 Boss 血量。
var boss: Vector2 = CombatSpace.ENEMY_SPAWN
var boss_player = null
var hp: float = 100
var actors: Array:
	get:
		var result: Array = []
		for entity in entities:
			if entity.simulation != null:
				result.append_array(entity.simulation.actors)
		return result

## 自定义入口：重新运行指定关卡 / 编队 / 障碍，可从某个阶段开始测试。
func reset(library: STGProject, kind: String, id: String, start_segment: int = 0) -> void:
	clear()
	if library == null or library.schema_version != STGProject.VERSION:
		issue = "资源库格式不受支持；请使用当前格式的资产索引。"
		return
	project = library
	issue = "；".join(project.validate())
	if not issue.is_empty():
		return
	if project.find(kind, id) == null:
		issue = "请选择一个关卡、编队或障碍"
		return
	definition = _select_definition(kind, id)
	if definition == null:
		issue = "请选择一个关卡"
		return
	_reset_progress(start_segment)
	_create_environment()
	queue_redraw() # Godot 内置：等待下一次绘制回调。

func _select_definition(kind: String, id: String) -> STGLevelDefinition:
	match kind:
		"waves":
			return Defaults.wave_preview(id, project.find("waves", id))
		"obstacles":
			# 独立障碍与关卡使用同一条出场链；临时编队只存在于运行副本，不写入策划项目。
			project = project.snapshot()
			var preview_wave = Defaults.wave(id, true)
			preview_wave.count = 1
			project.waves.append(preview_wave)
			return Defaults.obstacle_preview(preview_wave.id)
	return project.find("levels", id)

func _reset_progress(start_segment: int) -> void:
	segment_index = clampi(start_segment, 0, definition.segments.size() - 1)
	segment_elapsed = 0
	waiting_clear = false
	condition_failure = ""
	time = 0
	hits = 0
	player_last_hit_at = -1000
	completed = false
	player = definition.player_spawn
	previous_player = player
	player_velocity = Vector2.ZERO
	player_sample_valid = false

func _create_environment() -> void:
	background = Background.new()
	background.show_behind_parent = true # Godot 内置 CanvasItem：背景绘制在本层玩家和子弹下方。
	add_child(background)
	background.configure(definition)
	if definition.music != null:
		music_player = AudioStreamPlayer.new()
		music_player.stream = definition.music
		add_child(music_player)

## 自定义查询：返回当前阶段的配置，不复制，也不保存运行进度。
func segment() -> STGLevelSegment:
	return definition.segments[segment_index]

## 自定义固定步长入口；dt 的单位是秒。此处顺序也是预览与导出的统一时序。
func step(dt: float = STGSimulation.STEP) -> void:
	if definition == null or completed or not issue.is_empty():
		return
	_sync_music()
	_sample_player_velocity(dt)
	time += dt
	segment_elapsed += dt
	scroll.advance(segment().scroll_speed, dt)
	background.update_scroll(scroll.distance)
	_start_due_waves(dt)
	_tick_wave_jobs(dt)
	for entity in entities:
		entity.tick(self, dt)
	player_shots.tick(self, dt)
	_release_drained_entities()
	if actors.size() > STGSimulation.MAX_ACTORS:
		issue = "关卡攻击实例超过 2000，请减少编队数量或子弹寿命"
	if issue.is_empty():
		_check_exit()
	queue_redraw()

func _sample_player_velocity(dt: float) -> void:
	player_velocity = (player - previous_player) / maxf(dt, 0.000001) if player_sample_valid else Vector2.ZERO
	previous_player = player
	player_sample_valid = true

func _start_due_waves(dt: float) -> void:
	for event in segment().events:
		if not fired_events.has(event.id) and segment_elapsed + 0.000001 >= event.at:
			fired_events[event.id] = true
			var job = WavePlayer.new()
			# 新任务经过本 tick 后的累计时间恰好是“阶段时间 - 事件时间”。
			# 不能给刚到触发点的事件额外加一个 dt，导致后续成员提前出场。
			var initial_elapsed = segment_elapsed - event.at - dt
			job.start(project.find("waves", event.wave_id), event.spawn_position, segment().id, event.id, initial_elapsed)
			wave_jobs.append(job)

func _tick_wave_jobs(dt: float) -> void:
	for job in wave_jobs:
		job.tick(self, dt)
	for i in range(wave_jobs.size() - 1, -1, -1):
		if wave_jobs[i].finished_spawning():
			wave_jobs.remove_at(i)

func _release_drained_entities() -> void:
	# 已离场的敌人仍可能承载旧攻击；攻击耗尽后才释放稳定的场景根节点。
	for i in range(entities.size() - 1, -1, -1):
		if entities[i].is_drained():
			entities[i].free()
			entities.remove_at(i)

func _check_exit() -> void:
	var result = goals.evaluate(self)
	waiting_clear = result.waiting
	condition_failure = result.get("blocked", "")
	if not result.failed.is_empty():
		issue = result.failed
		return
	if not result.ready:
		return
	_end_segment()
	if segment_index + 1 < definition.segments.size():
		segment_index += 1
		segment_elapsed = 0
		waiting_clear = false
		condition_failure = ""
		fired_events.clear()
	else:
		_finish_level()

func _finish_level() -> void:
	completed = true
	_finish_entities()
	if is_instance_valid(music_player):
		music_player.stop()
	finished.emit()

func _end_segment() -> void:
	# 持续型实体跨关卡阶段保留；其余停止行为，旧攻击仍正常收尾。
	for entity in entities:
		if entity.group_id == segment().id and not entity.settings.persist_across_segments:
			entity.resolve("phase_end")
	for i in range(wave_jobs.size() - 1, -1, -1):
		var job = wave_jobs[i]
		if job.group_id == segment().id and not Entities.settings(project, job.definition).persist_across_segments:
			wave_jobs.remove_at(i)

## 自定义查询：整关计划坐标。等待目标时停在阶段末端，与实际 time 分开。
func planned_time() -> float:
	if definition == null:
		return 0
	# 目标提前达成也完成了最后阶段；完成游标应落在整关末尾。
	if completed:
		return Timing.total(definition)
	return Timing.start(definition, segment_index) + minf(segment_elapsed, segment().duration)

## 自定义出场接口：at 使用 960×540 战斗坐标；返回实体，超过容量时返回 null。
func spawn_entity(wave: STGWaveDefinition, at: Vector2, group: String, event_id: String = ""):
	if entities.size() >= MAX_ENTITIES:
		issue = "场上实体超过 96，请减少编队数量或寿命"
		return null
	next_instance_id += 1
	var entity = EntityPlayer.new()
	add_child(entity)
	entity.setup(project, wave, at, next_instance_id, group, event_id)
	goals.register(entity)
	entity.resolved.connect(_entity_resolved)
	if entity.simulation != null:
		entity.simulation.audio_requested.connect(audio_requested.emit)
		entity.simulation.player_hit.connect(register_hit)
	entities.append(entity)
	return entity

func shoot_player() -> void:
	if not completed and issue.is_empty():
		player_shots.fire(player, time)

func reset_player_sample() -> void:
	# 暂停时移动玩家，不把这段位移作为下一帧的预测速度传给每个敌人。
	previous_player = player
	player_velocity = Vector2.ZERO
	player_sample_valid = false
	for entity in entities:
		if entity.simulation != null:
			entity.simulation.player = player
			entity.simulation.previous_player = player
			entity.simulation.player_velocity = Vector2.ZERO
			entity.simulation.player_sample_valid = false

## 自定义游戏接口：按实例 ID 扣最大生命值百分比，由实体决定能否受伤。
func damage_entity(instance_id: int, percent: float) -> void:
	for entity in entities:
		if entity.instance_id == instance_id:
			entity.damage(maxf(0, percent))
			return

## 自定义命中入口：汇总敌人 / 子弹命中，0.2 秒内只上报一次给游戏玩家系统。
func register_hit(damage: float) -> void:
	if damage <= 0 or time - player_last_hit_at < 0.2:
		return
	hits += 1
	player_last_hit_at = time
	player_hit.emit(damage)

func set_audio_paused(value: bool) -> void:
	audio_paused = value
	if is_instance_valid(music_player):
		music_player.stream_paused = value

func _sync_music() -> void:
	if not is_instance_valid(music_player):
		return
	if muted:
		music_player.stop()
	elif not music_player.playing:
		music_player.play()
		music_player.stream_paused = audio_paused

func _entity_resolved(id: int, reason: String) -> void:
	resolved_entities[id] = reason
	goals.resolve(id, reason)
	entity_resolved.emit(id, reason)

func status() -> String:
	if definition == null or definition.segments.is_empty():
		return ""
	if completed:
		return "关卡结束"
	return "%s · %s · 计划 %.1fs · 实际 %.1fs · 卷轴 %.0f" % [segment().title, _progress_state(), planned_time(), time, scroll.distance]

func _progress_state() -> String:
	var state = "正在推进"
	if not condition_failure.is_empty():
		state = condition_failure
	elif waiting_clear:
		state = "等待清场" if segment().exit_rule.condition == "clear" else "等待击败目标"
	if waiting_clear:
		state += "，已等待 %.1fs" % maxf(0, segment_elapsed - segment().duration)
	return state

## 自定义清理接口：结束本次运行，释放实例和音频，保留用户的共享配置。
func clear() -> void:
	_finish_entities()
	if is_instance_valid(background):
		background.free()
	background = null
	if is_instance_valid(music_player):
		music_player.free()
	music_player = null
	fired_events.clear()
	resolved_entities.clear()
	goals.clear()
	condition_failure = ""
	next_instance_id = 0
	scroll = Scroll.new()
	definition = null

func _finish_entities() -> void:
	wave_jobs.clear()
	for entity in entities:
		entity.free()
	entities.clear()
	player_shots.clear()

func _draw() -> void: # Godot 回调；子弹和敌人由各自场景绘制。
	if editor_markers:
		draw_circle(player, 7, Color("ff3e68") if time - player_last_hit_at < 0.18 else Color("f7cedd"))
		draw_circle(player, player_radius, Color("ff547f"))
	for shot in player_shots.shots:
		draw_line(shot.position - Vector2(8, 0), shot.position + Vector2(4, 0), Color("77dfff"), 3, true)

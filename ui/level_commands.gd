@tool
extends RefCounted
## 关卡编辑接口：依赖、事件和片段在一次事务中修改；不接触运行实例。
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const Demo = preload("res://addons/stg_maker/authoring/templates/level_demo.gd")
const Selection = preload("res://addons/stg_maker/ui/timeline_selection.gd")

static func enemy_id(host, dependencies: Array) -> String:
	if not host.session.project.bosses.is_empty(): return host.session.project.bosses[0].id
	var enemy = D.boss()
	enemy.title = "关卡起步敌人"
	enemy.entity_settings = D.entity_settings(true)
	dependencies.append(["bosses", enemy])
	return enemy.id

static func create_wave(host, obstacle: bool, dependencies: Array) -> STGWaveDefinition:
	if not obstacle: return D.wave(enemy_id(host, dependencies))
	var definition = D.obstacle()
	dependencies.append(["obstacles", definition])
	return D.wave(definition.id, true)

static func create_level(host, template: String, dependencies: Array) -> STGLevelDefinition:
	if template == "empty_level": return D.level()
	if template == "three_section":
		var built = Demo.new().build()
		var bundle = preload("res://addons/stg_maker/authoring/template_import.gd").copy_bundle(host.session.project, built, "levels", built.levels[-1].id)
		if not bundle.issues.is_empty(): host.message("\n".join(bundle.issues)); return null
		for entry in bundle.entries:
			if entry[0] != "levels": dependencies.append(entry)
		for entry in bundle.entries:
			if entry[0] == "levels": return entry[1]
	var wave: STGWaveDefinition
	if not host.session.project.waves.is_empty(): wave = host.session.project.waves[0]
	else:
		wave = create_wave(host, false, dependencies)
		dependencies.append(["waves", wave])
	return D.level(wave.id)

static func add_event(host) -> void:
	var dependencies: Array = []
	var wave_id = host.session.project.waves[0].id if not host.session.project.waves.is_empty() else ""
	if wave_id.is_empty():
		var wave = create_wave(host, false, dependencies)
		wave_id = wave.id
		dependencies.append(["waves", wave])
	var event = D.level_event(wave_id, minf(1, host.level_segment().duration))
	var level_id: String = host.selected_id
	var segment_index: int = host.segment_index
	host.inspector_dirty = true
	host.event_id = event.id
	host.session.edit(func(project):
		for entry in dependencies: project.get(entry[0]).append(entry[1])
		project.find("levels", level_id).segments[segment_index].events.append(event))

static func add_wave_for_event(host, obstacle: bool) -> void:
	var dependencies: Array = []
	var wave = create_wave(host, obstacle, dependencies)
	var scope: Array = host.level_event_scope()
	var level_id: String = host.selected_id
	host.inspector_dirty = true
	host.session.edit(func(project):
		for entry in dependencies: project.get(entry[0]).append(entry[1])
		project.waves.append(wave)
		host.ConfigPath.resolve(project.find("levels", level_id), scope).wave_id = wave.id)
	host.edit_reference("waves", wave.id)

static func resize_segment(host, duration: float, selected_index: int = -1) -> void:
	var level_id: String = host.selected_id
	var index: int = host.segment_index if selected_index < 0 else selected_index
	host.inspector_dirty = true
	host.session.edit(func(project):
		var segment = project.find("levels", level_id).segments[index]
		segment.duration = duration
		for event in segment.events: event.at = minf(event.at, duration))

static func set_exit_mode(host, mode: String) -> void:
	host.edit_path(["segments", host.segment_index, "exit_rule"], "mode", mode, true)

static func set_condition(host, condition: String) -> void:
	var id: String = host.selected_id
	var index: int = host.segment_index
	host.inspector_dirty = true
	host.session.edit(func(project):
		var segment = project.find("levels", id).segments[index]
		segment.exit_rule.condition = condition
		if condition == "defeat_target" and segment.exit_rule.target_event_id.is_empty():
			for event in segment.events:
				var wave = project.find("waves", event.wave_id)
				if wave != null and wave.kind == "enemy":
					segment.exit_rule.target_event_id = event.id
					break)

static func move_segment(host, from: int, to: int) -> void:
	if from == to: return
	host.Commands.edit_list(host, ["segments"], "move", func(): return null, from, to)

static func move_event(host, from: int, event_id: String, to: int, at: float) -> void:
	var level = host.current()
	var rule = level.segments[from].exit_rule
	if from != to and rule.mode != "time" and rule.condition == "defeat_target" and rule.target_event_id == event_id:
		host.message("这个事件是阶段的击败目标，请先更换结束目标，再跨阶段移动。")
		return
	var id: String = host.selected_id
	host.segment_index = to
	host.event_id = event_id
	host.inspector_dirty = true
	host.session.edit(func(project):
		var segments = project.find("levels", id).segments
		for i in segments[from].events.size():
			if segments[from].events[i].id == event_id:
				var event = segments[from].events[i]
				event.at = clampf(at, 0, segments[to].duration)
				if from != to:
					segments[from].events.remove_at(i)
					segments[to].events.append(event)
				break)

static func move_events(host, ids: Array, delta: float, primary_id: String = "") -> bool:
	var level: STGLevelDefinition = host.current()
	var plan = Selection.plan(level, ids, delta)
	if is_zero_approx(plan.delta) or plan.moves.is_empty(): return false
	# 整批预检后才提交；一个指定目标不能跨阶段时，其他事件也不会被部分移动。
	for move in plan.moves:
		var rule = level.segments[move.from].exit_rule
		if move.from != move.to and rule.mode != "time" and rule.condition == "defeat_target" and rule.target_event_id == move.id:
			host.message("整批未移动：“%s”的击败目标不能跨阶段。请先更换阶段结束目标，或取消选择该事件。" % level.segments[move.from].title)
			return false
	var level_id: String = level.id
	var moves: Array = plan.moves
	for move in moves:
		if move.id == primary_id:
			host.segment_index = move.to
			host.event_id = primary_id
			break
	host.inspector_dirty = true
	host.session.edit(func(project):
		var segments = project.find("levels", level_id).segments
		var pending: Array = []
		# 先收集全部对象，再移除与插入，避免同批同阶段的数组索引相互影响。
		for move in moves:
			for event in segments[move.from].events:
				if event.id == move.id:
					pending.append({"move": move, "event": event})
					break
		for entry in pending:
			var move = entry.move
			if move.from != move.to: segments[move.from].events.erase(entry.event)
		for entry in pending:
			var move = entry.move
			entry.event.at = move.at
			if move.from != move.to: segments[move.to].events.append(entry.event))
	return true

static func accepts_drop(host, data) -> bool:
	return host.collection == "levels" and host.current() != null and data is Dictionary and data.get("kind", "") in ["bosses", "waves", "obstacles"] and host.session.project.find(data.kind, data.get("id", "")) != null

static func drop_resource(host, data: Dictionary, index: int, at: float, spawn: Vector2 = Vector2(450, -100)) -> void:
	if not accepts_drop(host, data): return
	var wave_id: String = data.id if data.kind == "waves" else ""
	var wave: STGWaveDefinition
	if wave_id.is_empty():
		wave = D.wave(data.id, data.kind == "obstacles")
		wave.count = 1
		wave.interval = 0
		wave.spacing = Vector2.ZERO
		wave.title = host.session.project.find(data.kind, data.id).title + " · 单体出场"
		wave_id = wave.id
	var event = D.level_event(wave_id, at)
	event.title = host.session.project.find(data.kind, data.id).title
	event.spawn_position = spawn
	var level_id: String = host.selected_id
	host.segment_index = index
	host.event_id = event.id
	host.inspector_tab = 0
	host.inspector_dirty = true
	host.playing = false
	host.canvas.edit_mode = "level_spawn"
	host.session.edit(func(project):
		if wave != null: project.waves.append(wave)
		project.find("levels", level_id).segments[index].events.append(event))

static func add_obstacle_for_wave(host) -> void:
	var obstacle = D.obstacle()
	var id: String = host.selected_id
	host.inspector_dirty = true
	host.session.edit(func(project):
		project.obstacles.append(obstacle)
		project.find("waves", id).obstacle_id = obstacle.id)
	host.edit_reference("obstacles", obstacle.id)

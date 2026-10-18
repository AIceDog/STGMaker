@tool
extends RefCounted
## 关卡校验接口 check：时间、引用、实体属性和结束条件。只校验当前生效配置。
const Locations = preload("res://stg/definitions/validation_locations.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Entities = preload("res://stg/definitions/entity_definitions.gd")

static func check(project, issues: PackedStringArray, locations: Variant = null) -> void:
	for entity in project.bosses + project.obstacles:
		if entity != null:
			var start = issues.size()
			_check_entity(entity, issues)
			Locations.mark(issues, start, locations, "bosses" if entity is STGBossDefinition else "obstacles", entity.id, ["entity_settings"])
	for wave in project.waves:
		if wave != null:
			var start = issues.size()
			_check_wave(project, wave, issues)
			Locations.mark(issues, start, locations, "waves", wave.id)
	for level in project.levels:
		if level != null:
			var start = issues.size()
			_check_level(project, level, issues, locations)
			Locations.mark(issues, start, locations, "levels", level.id)

static func _check_wave(project, wave: STGWaveDefinition, issues: PackedStringArray) -> void:
	if wave.kind not in ["enemy", "obstacle"]:
		issues.append(wave.title + "：未知实体类型")
	if wave.kind == "enemy" and project.find("bosses", wave.enemy_id) == null:
		issues.append(wave.title + "：敌人引用不存在")
	if wave.kind == "obstacle" and project.find("obstacles", wave.obstacle_id) == null:
		issues.append(wave.title + "：障碍引用不存在")
	if wave.count < 1 or wave.count > 32:
		issues.append(wave.title + "：数量需要 1–32")
	if not is_finite(wave.interval) or wave.interval < 0 or not wave.spacing.is_finite():
		issues.append(wave.title + "：出场间隔或排列无效")

static func _check_level(project, level: STGLevelDefinition, issues: PackedStringArray, locations: Variant = null) -> void:
	if not level.player_spawn.is_finite() or not CombatSpace.BOUNDS.has_point(level.player_spawn):
		issues.append(level.title + "：玩家出生点需要在屏幕内")
	if level.segments.is_empty() or level.segments.size() > 64:
		issues.append(level.title + "：需要 1–64 个关卡阶段")
	for layer in level.background_layers:
		if layer == null or not is_finite(layer.scroll_ratio) or layer.scroll_ratio < 0:
			issues.append(level.title + "：背景滚动倍率无效")
	var segment_ids = {}
	var event_ids = {} # 事件在完整关卡内具有唯一身份，移动阶段后目标仍可追踪。
	for i in level.segments.size():
		var start = issues.size()
		_check_segment(project, level, level.segments[i], segment_ids, event_ids, issues, locations, i)
		Locations.mark(issues, start, locations, "levels", level.id, ["segments", i])

static func _check_segment(project, level: STGLevelDefinition, segment: STGLevelSegment, segment_ids: Dictionary, event_ids: Dictionary, issues: PackedStringArray, locations: Variant = null, segment_index: int = 0) -> void:
	if segment == null:
		issues.append(level.title + "：存在空阶段")
		return
	if segment.id.is_empty() or segment_ids.has(segment.id):
		issues.append(level.title + "：阶段 ID 为空或重复")
	segment_ids[segment.id] = true
	if not is_finite(segment.duration) or segment.duration <= 0 or segment.duration > 600:
		issues.append(segment.title + "：计划长度需大于 0 且不超过 600 秒")
	if not is_finite(segment.scroll_speed) or segment.scroll_speed < 0:
		issues.append(segment.title + "：卷轴速度必须非负")
	if segment.events.size() > 128:
		issues.append(segment.title + "：最多 128 个出场事件")
	for event_index in segment.events.size():
		var event = segment.events[event_index]
		var start = issues.size()
		if event == null:
			issues.append(segment.title + "：存在空事件")
			continue
		if event.id.is_empty() or event_ids.has(event.id):
			issues.append(segment.title + "：事件 ID 为空或重复")
		event_ids[event.id] = true
		if not is_finite(event.at) or event.at < 0 or event.at > segment.duration:
			issues.append(event.title + "：出场时间需在阶段内")
			Locations.mark(issues, issues.size() - 1, locations, "levels", level.id, ["segments", segment_index, "events", event_index], "at")
		if not event.spawn_position.is_finite():
			issues.append(event.title + "：出生坐标无效")
		if project.find("waves", event.wave_id) == null:
			issues.append(event.title + "：编队引用不存在")
			Locations.mark(issues, issues.size() - 1, locations, "levels", level.id, ["segments", segment_index, "events", event_index], "wave_id")
		Locations.mark(issues, start, locations, "levels", level.id, ["segments", segment_index, "events", event_index])
	_check_exit_rule(project, segment, issues)

static func _check_entity(entity, issues: PackedStringArray) -> void:
	var settings: STGEntitySettings = entity.entity_settings
	if settings == null:
		issues.append(entity.title + "：缺少实体关卡属性")
		return
	if settings.movement_policy not in ["scroll", "independent"] or settings.exit_boundary not in ["left", "screen", "never"]:
		issues.append(entity.title + "：移动 / 离场规则无效")
	for number in [settings.scroll_factor, settings.exit_margin, settings.lifetime, settings.contact_damage]:
		if not is_finite(number) or number < 0:
			issues.append(entity.title + "：卷轴、离场、伤害参数必须非负")
	if not is_finite(settings.body_radius) or settings.body_radius <= 0:
		issues.append(entity.title + "：实体碰撞半径必须为正")

static func _check_exit_rule(project, segment: STGLevelSegment, issues: PackedStringArray) -> void:
	var rule = segment.exit_rule
	if rule == null:
		issues.append(segment.title + "：缺少结束规则")
		return
	if rule.mode not in STGLevelExitRule.MODES or rule.condition not in STGLevelExitRule.CONDITIONS:
		issues.append(segment.title + "：结束方式无效")
	if rule.mode == "time":
		return
	var targets = 0
	for event in segment.events:
		if event == null:
			continue
		var wave = project.find("waves", event.wave_id)
		if wave == null:
			continue
		if not rule.includes_event(event.id, wave.kind, wave.counts_for_clear):
			continue
		if rule.condition != "clear" and wave.kind != "enemy":
			if rule.condition == "defeat_target":
				issues.append(event.title + "：指定击败目标必须是敌人出场事件")
			continue
		targets += 1
		var settings = Entities.settings(project, wave)
		if settings == null:
			continue
		if rule.condition != "clear" and not settings.destructible:
			issues.append(event.title + "：不可破坏实体不能作为击败目标")
		if rule.condition == "clear" and not settings.destructible and settings.lifetime == 0:
			if settings.exit_boundary == "never":
				issues.append(event.title + "：不可破坏且不会离场的实体无法清场，请调整离场规则或取消计入目标")
			elif wave.kind == "obstacle":
				# 障碍没有 AI，水平卷轴路径可静态确定；检查每个成员，避免一只未入场的成员永远卡住。
				for i in wave.count:
					if not _obstacle_can_exit(settings, segment.scroll_speed, event.spawn_position + wave.offset(i)):
						issues.append(event.title + "：第 %d 个障碍无法入场或离场，不能计入清场目标" % (i + 1))
						break
	if rule.condition != "clear" and targets == 0:
		issues.append(segment.title + "：请选择有效的击败目标")

static func _obstacle_can_exit(settings: STGEntitySettings, scroll_speed: float, spawn: Vector2) -> bool:
	var entry_bounds = CombatSpace.BOUNDS.grow(settings.body_radius)
	var exit_bounds = entry_bounds.grow(settings.exit_margin)
	var moving_left = settings.movement_policy == "scroll" and settings.scroll_factor > 0 and scroll_speed > 0
	if settings.require_screen_entry and not entry_bounds.has_point(spawn):
		# 卷轴只向左移动：屏幕左侧或屏幕纵向范围外的出生点永远不会进入。
		if not moving_left or spawn.x < entry_bounds.position.x or spawn.y < entry_bounds.position.y or spawn.y > entry_bounds.end.y:
			return false
	if moving_left:
		return true # 已确定能够入场，继续向左最终越过 left / screen 回收线。
	# 不移动也可能已经在回收线外；未要求先入场时会在首帧正常回收。
	if settings.exit_boundary == "left":
		return spawn.x < exit_bounds.position.x
	return settings.exit_boundary == "screen" and not exit_bounds.has_point(spawn)

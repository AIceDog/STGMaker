@tool
extends RefCounted
## 唯一当前格式的资产校验。素材是静态几何，招式和行为的引用共同构成生效依赖图。
const Locations = preload("res://stg/definitions/validation_locations.gd")
const Curves = preload("res://stg/definitions/curve_validation.gd")
const BehaviorValidation = preload("res://stg/definitions/behavior_validation.gd")
const MovementValidation = preload("res://stg/definitions/movement_validation.gd")
const LevelValidation = preload("res://stg/definitions/level_validation.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const Schema = preload("res://stg/definitions/asset_schema.gd")

static func check(project) -> PackedStringArray: return _run(project)

static func diagnostics(project) -> Array[Dictionary]:
	var locations = {}
	var issues = _run(project, locations)
	var result: Array[Dictionary] = []
	for index in issues.size():
		var entry: Dictionary = locations.get(index, {}).duplicate()
		entry["message"] = issues[index]
		result.append(entry)
	return result

static func _run(project, locations: Variant = null) -> PackedStringArray:
	var issues = PackedStringArray()
	if project.schema_version != Schema.VERSION: return PackedStringArray(["不支持的资产格式版本"])
	for collection in References.COLLECTIONS:
		var identifiers = {}
		for resource in project.get(collection):
			if resource == null: issues.append("存在空资源"); continue
			var start = issues.size()
			if resource.id.is_empty() or identifiers.has(resource.id): issues.append("资源 ID 为空或重复：" + resource.title)
			identifiers[resource.id] = true
			if resource is STGBulletDefinition: _check_bullet(resource, issues)
			elif resource is STGBarrageSkill: _check_barrage(project, resource, issues, locations)
			elif resource is STGBehaviorFlow: BehaviorValidation.check(resource, project, issues, resource.title, locations, resource.id, -1)
			elif resource is STGBossDefinition: _check_boss(project, resource, issues, locations)
			for reference in References.collect(resource):
				if project.find(reference.collection, reference.id) == null: issues.append(resource.title + "：引用不存在：" + reference.collection + ":" + reference.id)
			Locations.mark(issues, start, locations, collection, resource.id)
	var visited = {}
	for collection in ["barrages", "behaviors"]:
		for resource in project.get(collection):
			if resource != null: _cycle(project, collection, resource.id, [], visited, issues)
	preload("res://stg/definitions/summon_validation.gd").check(project, issues, locations)
	LevelValidation.check(project, issues, locations)
	return issues

static func _check_bullet(bullet: STGBulletDefinition, issues: PackedStringArray) -> void:
	if bullet.form not in ["moving", "laser", "area", "trail"] or bullet.scene == null: issues.append(bullet.title + "：子弹场景或形式无效")
	var presentation_issue = preload("res://stg/definitions/scene_contract.gd").presentation_issue(bullet.visual_scene, bullet.visual_animation)
	if not presentation_issue.is_empty(): issues.append(bullet.title + "：" + presentation_issue)
	if bullet.form == "moving":
		for scene in [bullet.spawn_particles, bullet.run_particles, bullet.hit_particles]:
			var particle_issue = preload("res://stg/definitions/scene_contract.gd").presentation_issue(scene, "")
			if not particle_issue.is_empty(): issues.append(bullet.title + "：" + particle_issue)
	if not is_finite(bullet.particle_duration) or bullet.particle_duration <= 0: issues.append(bullet.title + "：粒子保留时间必须大于零")
	if bullet.visual == null: issues.append(bullet.title + "：外观配置缺失")
	else:
		for issue in bullet.visual.validate(): issues.append(bullet.title + "：" + issue)
		if bullet.form not in ["moving", "laser"] and [bullet.visual.spawn_clip, bullet.visual.run_clip, bullet.visual.hit_clip, bullet.visual.expire_clip].any(func(clip): return clip != null): issues.append(bullet.title + "：当前只有子弹与激光支持阶段贴图动画")
	if bullet.collision == null: issues.append(bullet.title + "：碰撞配置缺失")
	else:
		for issue in bullet.collision.validate(): issues.append(bullet.title + "：" + issue)
	if bullet.beam_path != null: Curves.check_path(bullet.beam_path, issues, bullet.title)
	if bullet.form == "trail":
		for value in [bullet.trail_spacing, bullet.trail_break_distance]:
			if not is_finite(value) or value <= 0: issues.append(bullet.title + "：尾迹采样参数必须大于零")
		if not is_finite(bullet.trail_offset) or bullet.trail_offset < 0: issues.append(bullet.title + "：尾部偏移必须非负")

static func _check_barrage(project, skill: STGBarrageSkill, issues: PackedStringArray, locations: Variant = null) -> void:
	var pattern = skill.fire_pattern
	var projectile = skill.projectile
	if pattern == null or projectile == null or projectile.lifecycle == null:
		issues.append(skill.title + "：招式缺少发射、弹体或生命周期配置")
		return
	if pattern.extension != null:
		for issue in pattern.extension.validate("emission"): issues.append(skill.title + "：" + issue)
	if pattern.count < 1 or pattern.count > 256 or pattern.rounds < 1 or pattern.rounds > 64: issues.append(skill.title + "：数量 / 轮数超出范围")
	if pattern.group_size < 0 or pattern.group_size > 256 or not is_finite(pattern.group_interval) or pattern.group_interval < 0: issues.append(skill.title + "：分组数量 / 间隔无效")
	if not is_finite(pattern.rotation_per_projectile): issues.append(skill.title + "：每颗旋转参数无效")
	if projectile.delivery not in ["position", "trajectory"]: issues.append(skill.title + "：生成模式无效")
	if pattern.summon_mode not in ["position", "launch"] or not is_finite(pattern.summon_launch_speed) or pattern.summon_launch_speed < 0 or not is_finite(pattern.summon_launch_duration) or pattern.summon_launch_duration <= 0: issues.append(skill.title + "：召唤入场参数无效")
	if not is_finite(skill.trail_max_length) or skill.trail_max_length < 0: issues.append(skill.title + "：拖尾最大路径长度无效")
	for key in ["at", "interval", "radius", "line_length", "angle", "aim_offset", "angle_jitter", "speed_scale_min", "speed_scale_max", "spread", "rotation_per_round", "safe_gap_radius", "extension_duration", "summon_life"]:
		if not is_finite(pattern.get(key)): issues.append(skill.title + "：发射参数无效：" + key)
	if pattern.at < 0 or pattern.interval < 0 or pattern.radius < 0 or pattern.line_length < 0 or pattern.safe_gap_radius < 0 or pattern.angle_jitter < 0: issues.append(skill.title + "：发射时间 / 尺寸不能为负")
	if pattern.speed_scale_min <= 0 or pattern.speed_scale_max < pattern.speed_scale_min: issues.append(skill.title + "：速度倍率无效")
	if pattern.extension_duration <= 0 or pattern.extension_duration > 60: issues.append(skill.title + "：自定义发射上限需为 0–60 秒")
	if pattern.arrangement not in ["point", "circle", "line", "path"] or pattern.direction not in ["fan", "parallel", "outward", "inward", "aim", "random"] or pattern.anchor not in ["origin", "boss", "player", "world"]: issues.append(skill.title + "：发射类型无效")
	if pattern.aim_lock not in ["each_round", "call_start"] or pattern.anchor_axes not in ["both", "x", "y"] or pattern.safe_gap_axis not in ["x", "y"]: issues.append(skill.title + "：发射坐标轴或锁定方式无效")
	if pattern.sound_unit not in ["cast", "round", "projectile"]: issues.append(skill.title + "：音效播放单位无效")
	if not pattern.offset.is_finite() or not pattern.aim_target_offset.is_finite(): issues.append(skill.title + "：发射 / 瞄准偏移无效")
	if pattern.arrangement == "path": Curves.check_path(pattern.path, issues, skill.title)
	if not pattern.enemy_id.is_empty():
		if project.find("bosses", pattern.enemy_id) == null or pattern.summon_life <= 0: issues.append(skill.title + "：召唤敌人或生存上限无效")
	else:
		var material = project.find("bullets", projectile.bullet_id)
		if material == null:
			var start = issues.size()
			issues.append(skill.title + "：子弹素材引用不存在")
			Locations.mark(issues, start, locations, "barrages", skill.id, ["projectile"], "bullet_id")
		if projectile.motion_stages.is_empty() or projectile.motion_stages.size() > 32: issues.append(skill.title + "：飞行过程需要 1–32 个步骤")
		for index in projectile.motion_stages.size():
			var start = issues.size()
			_check_motion_stage(project, skill.title, projectile.motion_stages[index], issues, locations, {"collection": "barrages", "id": skill.id, "scope": ["projectile", "motion_stages", index]})
			Locations.mark(issues, start, locations, "barrages", skill.id, ["projectile", "motion_stages", index])
		if material != null and material.form == "trail" and (not is_finite(skill.trail_duration) or skill.trail_duration <= 0): issues.append(skill.title + "：尾迹生成时长无效")
	if pattern.enemy_id.is_empty(): _check_lifecycle(projectile.lifecycle, issues, skill.title)
	elif not is_finite(projectile.lifecycle.warning) or projectile.lifecycle.warning < 0 or not is_finite(projectile.lifecycle.effect_duration) or projectile.lifecycle.effect_duration <= 0:
		issues.append(skill.title + "：召唤前摇 / 特效时长无效")

static func _check_lifecycle(life: STGAttackLifecycle, issues: PackedStringArray, title: String) -> void:
	for key in ["warning", "fade", "damage", "damage_falloff_start", "damage_falloff_scale", "hit_interval", "bounds_margin"]:
		if not is_finite(life.get(key)) or life.get(key) < 0: issues.append(title + "：生命周期参数无效：" + key)
	if life.hit_interval <= 0: issues.append(title + "：重复命中间隔必须大于零")
	if not is_finite(life.effect_duration) or life.effect_duration <= 0: issues.append(title + "：特效最长持续时间必须大于零")
	if life.hit_mode not in ["persistent", "activation", "repeat"] or life.exit_mode not in ["none", "ground", "bounds"]: issues.append(title + "：命中 / 回收规则无效")
	if not is_finite(life.ground_y): issues.append(title + "：地面坐标无效")
	if life.damage_falloff_start > 1 or life.damage_falloff_scale > 1: issues.append(title + "：区域远端伤害比例需为0–1")
	for prefix in ["on_hit", "on_expire"]:
		if not str(life.get(prefix + "_barrage_id")).is_empty() and not str(life.get(prefix + "_behavior_id")).is_empty(): issues.append(title + "：同一后继应选择招式或行为子流程")
	for effect in life.hit_effects:
		if effect == null: issues.append(title + "：存在空命中效果")
		else:
			for issue in effect.validate("effect"): issues.append(title + "：" + issue)

static func _cycle(project, collection: String, identifier: String, ancestors: Array, visited: Dictionary, issues: PackedStringArray) -> int:
	var key = collection + ":" + identifier
	if key in ancestors:
		issues.append("攻击 / 后继 / 行为引用形成循环：" + identifier)
		return 0
	if visited.has(key):
		if ancestors.size() + visited[key] > 64: issues.append("攻击后继超过64层：" + identifier)
		return visited[key]
	if ancestors.size() >= 64: issues.append("攻击后继超过64层：" + identifier); return 0
	var asset = project.find(collection, identifier)
	if asset == null: return 0
	var depth = 1
	for reference in References.collect(asset):
		if reference.collection in ["barrages", "behaviors"]: depth = maxi(depth, 1 + _cycle(project, reference.collection, reference.id, ancestors + [key], visited, issues))
	visited[key] = depth
	return depth

static func _check_motion_stage(project, title: String, stage: STGMotionStage, issues: PackedStringArray, locations: Variant = null, location: Dictionary = {}) -> void:
	if stage == null:
		issues.append(title + "：存在空阶段")
		return
	if stage.mode not in ["path", "aim", "track", "velocity", "sine", "ballistic", "orbit", "wait", "transform", "extension"]:
		issues.append(title + "：未知运动方式")
	if stage.mode == "extension":
		if stage.extension == null:
			issues.append(title + "：请选择自定义运动扩展")
		else:
			for issue in stage.extension.validate("motion"):
				issues.append(title + "：" + issue)
	if not is_finite(stage.duration) or stage.duration <= 0 or stage.duration > 60:
		issues.append(title + "：阶段时长需为 0–60 秒")
		Locations.mark(issues, issues.size() - 1, locations, location.get("collection", ""), location.get("id", ""), location.get("scope", []), "duration")
	if stage.mode == "extension":
		if not is_finite(stage.angular_speed): issues.append(title + "：几何旋转参数无效")
		Curves.check_curve(stage.visual_scale_curve, issues, title)
		Curves.check_curve(stage.collision_scale_curve, issues, title)
		return
	for number in [stage.speed, stage.turn_speed, stage.orbit_radius, stage.orbit_speed]:
		if not is_finite(number):
			issues.append(title + "：运动参数无效")
	if stage.speed < 0 or stage.turn_speed < 0 or stage.orbit_radius < 0:
		issues.append(title + "：速度 / 半径不能为负")
	if stage.orbit_center not in ["boss", "player", "origin"] or not is_finite(stage.orbit_end_radius) or stage.orbit_end_radius < -1 or not is_finite(stage.angular_speed) or not is_finite(stage.track_until_distance) or stage.track_until_distance < 0:
		issues.append(title + "：环绕 / 旋转 / 追踪停止参数无效")
	if not stage.track_target_offset.is_finite(): issues.append(title + "：追踪偏移无效")
	if stage.mode == "sine":
		for value in [stage.sine_amplitude, stage.sine_frequency, stage.sine_phase]:
			if not is_finite(value):
				issues.append(title + "：S 形摆动参数无效")
	if stage.mode == "ballistic":
		for value in [stage.gravity, stage.flight_time, stage.flight_speed, stage.flight_min_time, stage.flight_max_time, stage.flight_min_distance, stage.velocity_x_player_factor, stage.velocity_x_limit]:
			if not is_finite(value):
				issues.append(title + "：抛物线参数无效")
		if not stage.initial_velocity.is_finite() or stage.flight_time < 0 or stage.flight_speed <= 0 or stage.flight_min_time <= 0 or stage.flight_max_time < stage.flight_min_time or stage.flight_min_distance < 0 or stage.velocity_x_limit < 0 or stage.flight_distance_mode not in ["distance", "horizontal"]:
			issues.append(title + "：抛物线时间 / 距离参数无效")
	if stage.mode == "path":
		Curves.check_path(stage.path, issues, title)
	Curves.check_curve(stage.visual_scale_curve, issues, title)
	Curves.check_curve(stage.collision_scale_curve, issues, title)
	Curves.check_curve(stage.progress_curve, issues, title, true)
	if stage.mode == "transform":
		var transformed = project.find("barrages", stage.transform_attack_id)
		if transformed == null:
			issues.append(title + "：变形引用不存在")
		elif transformed.kind(project) == "summon": issues.append(title + "：召唤不能作为弹体变形目标，请使用后续招式调用")
		elif transformed.projectile != null and project.find("bullets", transformed.projectile.bullet_id) != null and project.find("bullets", transformed.projectile.bullet_id).form == "trail":
			issues.append(title + "：轨迹尾迹需要由招式跟随 Boss 生成")

static func _check_boss(project, boss: STGBossDefinition, issues: PackedStringArray, locations: Variant = null) -> void:
	if not boss.on_death_skill_id.is_empty() and project.find("barrages", boss.on_death_skill_id) == null:
		issues.append(boss.title + "：死亡招式引用不存在")
	if not boss.on_death_behavior_id.is_empty() and project.find("behaviors", boss.on_death_behavior_id) == null: issues.append(boss.title + "：死亡行为引用不存在")
	if boss.phases.is_empty():
		issues.append(boss.title + "：至少需要一个阶段")
	var previous_hp = 101.0
	var previous_life = -1
	for phase_index in boss.phases.size():
		var phase = boss.phases[phase_index]
		var phase_start = issues.size()
		if phase == null:
			issues.append(boss.title + "：存在空阶段")
			continue
		if phase.life < previous_life or phase.life < 0:
			issues.append(boss.title + "：血条编号必须非负且递增")
		if phase.life != previous_life: previous_hp = 101
		if phase.entry_mode not in ["hp", "sequence"] or phase.time_exit not in ["next", "life_start", "finish"] or phase.depleted_exit not in ["auto", "next", "finish"]:
			issues.append(boss.title + "：阶段进入 / 结束方式无效")
		if not phase.entry_barrage_id.is_empty():
			var entry_skill = project.find("barrages", phase.entry_barrage_id)
			if entry_skill == null:
				issues.append(boss.title + "：转场招式不存在或附带 Boss 位移")
		if not phase.entry_behavior_id.is_empty() and project.find("behaviors", phase.entry_behavior_id) == null: issues.append(boss.title + "：转场行为引用不存在")
		for value in [phase.life_hp, phase.depleted_refill]:
			if not is_finite(value) or value <= 0 or value > 100: issues.append(boss.title + "：补充血量需为 1–100%")
		for value in [phase.entry_delay, phase.time_limit]:
			if not is_finite(value) or value < 0: issues.append(boss.title + "：阶段时间必须非负")
		if (phase.entry_mode == "hp" and phase.enter_hp >= previous_hp) or phase.enter_hp < 0 or phase.enter_hp > 100 or not is_finite(phase.enter_hp):
			issues.append(boss.title + "：阶段血量阈值需要递减")
		if phase.entry_mode == "hp": previous_hp = phase.enter_hp
		previous_life = phase.life
		BehaviorValidation.check(phase.behavior_flow, project, issues, boss.title + " / " + phase.title, locations, boss.id, phase_index)
		Locations.mark(issues, phase_start, locations, "bosses", boss.id, ["phases", phase_index])
	BehaviorValidation.check_presentation(boss, issues)


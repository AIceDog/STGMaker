@tool
extends RefCounted
## 唯一当前格式的资产校验。素材是静态几何，招式和行为的引用共同构成生效依赖图。
const Locations = preload("res://stg/definitions/validation_locations.gd")
const Curves = preload("res://stg/definitions/curve_validation.gd")
const BehaviorValidation = preload("res://stg/definitions/behavior_validation.gd")
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
            if resource is STGBehaviorPreset:
                for issue in resource.validate(): issues.append(resource.title+"："+issue)
            elif resource is STGAttackPreset:
                for issue in resource.validate(project): issues.append(resource.title + "：" + issue)
            elif resource is STGBulletDefinition: _check_bullet(resource, issues, locations)
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

static func _check_bullet(bullet: STGBulletDefinition, issues: PackedStringArray, locations: Variant = null) -> void:
    if bullet.form not in ["moving", "laser", "area", "trail"]: issues.append(bullet.title + "：子弹形式无效")
    if bullet.form == "moving":
        for key in ["spawn_particles", "run_particles", "hit_particles"]:
            var start = issues.size()
            var issue = preload("res://stg/definitions/scene_contract.gd").particles_issue(bullet.get(key), key != "run_particles")
            if not issue.is_empty(): issues.append(bullet.title + " / " + {"spawn_particles": "刚发射粒子", "run_particles": "运行中粒子", "hit_particles": "命中后粒子"}[key] + "：" + issue)
            Locations.mark(issues, start, locations, "bullets", bullet.id, [], key)
    if bullet.visual == null: issues.append(bullet.title + "：外观配置缺失")
    else:
        for issue in bullet.visual.validate(): issues.append(bullet.title + "：" + issue)
        if bullet.form not in ["moving", "laser"] and [bullet.visual.spawn_clip, bullet.visual.run_clip, bullet.visual.hit_clip, bullet.visual.expire_clip].any(func(clip): return clip != null): issues.append(bullet.title + "：当前只有子弹与激光支持阶段贴图动画")
    if bullet.collision == null: issues.append(bullet.title + "：碰撞配置缺失")
    else:
        for issue in bullet.collision.validate(): issues.append(bullet.title + "：" + issue)
    if bullet.form == "trail":
        for value in [bullet.trail_spacing, bullet.trail_break_distance]:
            if not is_finite(value) or value <= 0: issues.append(bullet.title + "：尾迹采样参数必须大于零")
        if not is_finite(bullet.trail_offset) or bullet.trail_offset < 0: issues.append(bullet.title + "：尾部偏移必须非负")

static func _check_barrage(project, skill: STGBarrageSkill, issues: PackedStringArray, _locations: Variant = null) -> void:
 if skill.attack_preset==null:issues.append(skill.title+"：缺少招式程序");return
 for issue in skill.attack_preset.validate(project,skill.program_parameters,skill.reference_override):issues.append(skill.title+"："+issue)

static func _check_lifecycle(life: STGAttackLifecycle, issues: PackedStringArray, title: String) -> void:
    for key in ["damage", "damage_falloff_start", "damage_falloff_scale", "hit_interval", "bounds_margin"]:
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
    BehaviorValidation.check_presentation(boss, project, issues)


@tool
extends RefCounted
## 招式只引用素材；发射、运动、命中与表现由同一份招式配置负责。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const D = preload("res://stg/definitions/definition_factory.gd")
const Motion = preload("res://addons/stg_maker/ui/motion_fields.gd")
const Extensions = preload("res://addons/stg_maker/ui/extension_fields.gd")

static func build(host, parent, skill: STGBarrageSkill) -> void:
	F.text(parent, "招式名称", skill.title, R.setter(host, [], "title"))
	var kind = skill.kind(host.session.project)
	if host.inspector_tab == 1:
		if kind == "summon": F.note(parent, "召唤后的生命值、碰撞和行为在敌人资产中配置。")
		else: _lifecycle(host, parent, skill.projectile.lifecycle)
	elif host.inspector_tab == 2: _presentation(host, parent, skill)
	else:
		_type(host, parent, skill, kind)
		var phase = F.group(parent, "子弹节奏" if kind == "moving" else "阶段节奏")
		R.number(host, phase, ["projectile", "lifecycle"], skill.projectile.lifecycle, "warning", "前摇时间 s", 0, 30)
		if kind != "summon": R.number(host, phase, ["projectile", "lifecycle"], skill.projectile.lifecycle, "fade", "后摇时间 s", 0, 30)
		F.note(phase, "每颗弹体生成后先前摇，再移动和判伤；自然结束后停止运动与判定，进入后摇。" if kind != "summon" else "前摇期间显示召唤特效；结束后出现敌人，入场运动结束才开始敌人自己的行为。")
		if kind == "trail":
			var trail = F.section(parent, "拖尾长度与时间")
			R.number(host, trail, [], skill, "trail_max_length", "最大路径长度", 0, 10000)
			R.number(host, trail, [], skill, "trail_duration", "沿移动路径生成时长 s", 0.01, 60)
			R.number(host, trail, ["projectile", "motion_stages", 0], skill.projectile.motion_stages[0], "duration", "每段保留时间 s", 0.01, 60)
			F.note(trail, "长度使用战斗坐标距离，0 表示只按每段寿命限制。路径由敌人实际移动生成；宽度与碰撞在素材中编辑。")
			return
		_firing(host, parent, skill.fire_pattern)
		var trajectory = F.group(parent, "弹道")
		if kind == "laser" or kind == "summon": _delivery(host, trajectory, skill, kind)
		_spawn(host, trajectory, skill.fire_pattern, kind)
		if skill.fire_pattern.extension == null: _direction(host, trajectory, skill.fire_pattern)
		if kind != "summon" and skill.projectile.delivery == "trajectory": _motion(host, trajectory, skill)

static func _type(host, parent, skill: STGBarrageSkill, kind: String) -> void:
	var group = F.group(parent, "招式类型与引用")
	var keys = ["moving", "laser", "trail", "summon"]
	var names = ["子弹", "激光", "拖尾", "召唤敌人"]
	if kind == "area": keys.append("area"); names.append("区域")
	F.select(group, "招式类型", kind, keys, names, func(value):
		var entries: Array = host.session.project.bosses if value == "summon" else host.session.project.bullets.filter(func(item): return item.form == value)
		if entries.is_empty(): host.message("先在%s中创建可引用的内容。" % ("敌人 / Boss" if value == "summon" else "子弹素材")); host.refresh(true); return
		R.edit(host, [], func(target, _project):
			target.fire_pattern.enemy_id = entries[0].id if value == "summon" else ""
			if value != "summon":
				target.projectile.bullet_id = entries[0].id
				target.projectile.delivery = "trajectory"
				if value == "trail":
					target.projectile.motion_stages.assign([D.stage("wait")])
					target.fire_pattern.count = 1
					target.fire_pattern.rounds = 1
					target.fire_pattern.group_size = 0))
	if kind == "summon":
		R.resource_reference(host, group, ["fire_pattern"], "enemy_id", skill.fire_pattern.enemy_id, "bosses", "召唤的敌人")
		R.reference_editor(host, group, "bosses", skill.fire_pattern.enemy_id, "编辑敌人 →")
		R.number(host, group, ["fire_pattern"], skill.fire_pattern, "summon_life", "最多存活 s", 0.01, 60)
	else:
		R.resource_reference(host, group, ["projectile"], "bullet_id", skill.projectile.bullet_id, "bullets", "子弹素材", func(item): return item.form == kind)
		R.reference_editor(host, group, "bullets", skill.projectile.bullet_id, "编辑子弹素材 →")
		F.note(group, "素材统一编辑外观和碰撞，修改会影响所有引用处。")

static func _firing(host, parent, pattern: STGFirePattern) -> void:
	var scope = ["fire_pattern"]
	var timing = F.group(parent, "发射节奏")
	for field in [["at", "开始延迟 s", 0, 60], ["count", "每轮数量", 1, 256], ["rounds", "轮数", 1, 64], ["interval", "轮间隔 s", 0, 30]]:
		R.number(host, timing, scope, pattern, field[0], field[1], field[2], field[3], 1 if field[0] in ["count", "rounds"] else 0.01)
	var module = F.fold(timing, "发射实现", pattern.extension != null, "attack.generator")
	Extensions.slot(host, module, scope, "extension", "emission", "发射模式 / 模块")
	if pattern.extension != null:
		R.number(host, module, scope, pattern, "extension_duration", "每轮执行上限 s", 0.01, 60)
		F.note(module, "脚本模块决定该轮内部的生成规则和发出时刻；上方每轮数量作为模块的公共输入。")
	else:
		F.select(timing, "发射方式", "simultaneous" if pattern.group_size == 0 else "grouped", ["simultaneous", "grouped"], ["齐射", "分组发射"], func(value): host.edit_path(scope, "group_size", 0 if value == "simultaneous" else 1, true))
		if pattern.group_size > 0:
			R.number(host, timing, scope, pattern, "group_size", "每组数量", 1, 256, 1)
			R.number(host, timing, scope, pattern, "group_interval", "组间隔 s", 0, 30)
			F.note(timing, "一轮 %d 颗，分 %d 批，末批 %d 颗。分组只安排时间，弹体序号与弹道仍按完整轮计算。" % [pattern.count, ceili(float(pattern.count) / pattern.group_size), (pattern.count - 1) % pattern.group_size + 1])
	F.note(timing, "开始延迟从招式释放时计算；轮间隔是相邻轮第一批的起点间隔，可按设置重叠。")

static func _delivery(host, parent, skill: STGBarrageSkill, kind: String) -> void:
	if kind == "summon":
		F.select(parent, "生成模式", skill.fire_pattern.summon_mode, ["position", "launch"], ["指定位置召唤", "发射出去"], R.setter(host, ["fire_pattern"], "summon_mode", true))
		if skill.fire_pattern.summon_mode == "launch":
			R.number(host, parent, ["fire_pattern"], skill.fire_pattern, "summon_launch_speed", "入场速度", 0, 3000)
			R.number(host, parent, ["fire_pattern"], skill.fire_pattern, "summon_launch_duration", "入场飞行时间 s", 0.01, 30)
	else:
		F.select(parent, "生成模式", skill.projectile.delivery, ["position", "trajectory"], ["指定位置生成", "沿弹道发射"], func(value):
			R.edit(host, ["projectile"], func(target, _project):
				target.delivery = value
				if value == "position":
					var seconds = 0.0
					for stage in target.motion_stages: seconds += stage.duration
					var wait = D.stage("wait")
					wait.duration = maxf(0.01, seconds)
					target.motion_stages.assign([wait])))
		if skill.projectile.delivery == "position": R.number(host, parent, ["projectile", "motion_stages", 0], skill.projectile.motion_stages[0], "duration", "攻击中持续时间 s", 0.01, 60)

static func _spawn(host, parent, pattern: STGFirePattern, kind: String) -> void:
	var scope = ["fire_pattern"]
	var spawn = F.section(parent, "出生位置与排列")
	var name = {"moving": "子弹生成位置", "laser": "激光生成位置", "summon": "敌人生成位置"}.get(kind, "生成位置")
	F.select(spawn, name, pattern.anchor, ["origin", "boss", "player", "world"], ["调用原点", "敌人坐标", "玩家坐标", "固定战斗坐标"], func(value):
		R.edit(host, scope, func(target, _project): target.anchor = value; target.anchor_axes = "both"))
	R.vector_inline(host, spawn, scope, pattern, "offset", "位置偏移")
	if pattern.anchor_axes != "both": F.note(spawn, "当前资源只读取 %s 坐标；重新选择生成位置后使用完整 X/Y。" % pattern.anchor_axes.to_upper())
	F.select(spawn, "排列方式", pattern.arrangement, ["point", "circle", "line", "path"], ["单点", "圆周", "线段", "曲线"], R.setter(host, scope, "arrangement", true))
	if pattern.arrangement == "circle": R.number(host, spawn, scope, pattern, "radius", "排列半径", 0, 2000)
	if pattern.arrangement == "line": R.number(host, spawn, scope, pattern, "line_length", "排列长度", 0, 2000)
	F.button(spawn, "在画面编辑出生排列", func(): host.set_tool("path" if pattern.arrangement == "path" else "spawn"))

static func _direction(host, parent, pattern: STGFirePattern) -> void:
	var scope = ["fire_pattern"]
	var box = F.section(parent, "初始方向与规律旋转")
	var keys = ["fan", "parallel", "outward", "inward", "aim"]
	var names = ["扇形", "平行", "向外", "向内", "瞄准玩家"]
	# 已有资源的随机方向忠实显示，但不在新制作选项中提供随机能力。
	if pattern.direction == "random": keys.append("random"); names.append("随机（当前资源使用）")
	F.select(box, "方向分布", pattern.direction, keys, names, R.setter(host, scope, "direction", true))
	R.number(host, box, scope, pattern, "angle", "中心方向 °", -360, 360)
	if pattern.direction == "fan" or pattern.direction == "aim" and pattern.aim_spread: R.number(host, box, scope, pattern, "spread", "展开角度 °", 0, 360)
	if pattern.direction == "aim":
		F.toggle(box, "围绕玩家方向展开扇形", pattern.aim_spread, R.setter(host, scope, "aim_spread", true))
		F.select(box, "目标锁定时机", pattern.aim_lock, ["each_round", "call_start"], ["每轮重新瞄准", "招式开始时锁定"], R.setter(host, scope, "aim_lock"))
		R.vector_inline(host, box, scope, pattern, "aim_target_offset", "瞄准目标偏移")
		R.number(host, box, scope, pattern, "aim_offset", "方向偏移 °", -360, 360)
	R.number(host, box, scope, pattern, "rotation_per_projectile", "每颗方向递增 °", -360, 360)
	R.number(host, box, scope, pattern, "rotation_per_round", "每轮方向递增 °", -360, 360)
	if pattern.angle_jitter != 0 or pattern.speed_scale_min != pattern.speed_scale_max: F.note(box, "当前资源包含已有随机参数，本页不新增随机设置；原参数继续参与运行。")

static func _motion(host, parent, skill: STGBarrageSkill) -> void:
	var stages = skill.projectile.motion_stages
	if stages.is_empty(): return
	host.stage_index = clampi(host.stage_index, 0, stages.size() - 1)
	var box = F.fold(parent, "高级弹道 · 飞行过程", false, "attack.motion")
	F.note(box, "先保留现有飞行能力，详细制作流程等待后续设计。")
	var labels = []
	for i in stages.size(): labels.append("%d · %s" % [i + 1, stages[i].title])
	F.select(box, "当前步骤", str(host.stage_index), range(stages.size()).map(func(i): return str(i)), labels, func(value): host.stage_index = int(value); host.refresh(true))
	Motion.build(host, box, stages[host.stage_index], ["projectile", "motion_stages", host.stage_index])
	R.list_buttons(host, box, ["projectile", "motion_stages"], host.stage_index, func(): return D.stage("wait"), "＋ 飞行步骤")

static func _lifecycle(host, parent, life: STGAttackLifecycle) -> void:
	var scope = ["projectile", "lifecycle"]
	var hit = F.group(parent, "命中规则")
	R.number(host, hit, scope, life, "damage", "伤害", 0, 10000)
	F.toggle(hit, "接触时造成伤害", life.damage_on_contact, R.setter(host, scope, "damage_on_contact"))
	F.select(hit, "命中时机", life.hit_mode, ["persistent", "activation", "repeat"], ["存在期间命中一次", "生效瞬间判定一次", "按间隔重复判定"], R.setter(host, scope, "hit_mode", true))
	if life.hit_mode == "repeat": R.number(host, hit, scope, life, "hit_interval", "重复命中间隔 s", 0.01, 60)
	var falloff = F.fold(hit, "圆形区域远端伤害", false, "attack.falloff")
	R.number(host, falloff, scope, life, "damage_falloff_start", "远区开始半径比例", 0, 1)
	R.number(host, falloff, scope, life, "damage_falloff_scale", "远区伤害倍率", 0, 1)
	var exit = F.fold(parent, "提前结束条件", false, "attack.exit")
	F.select(exit, "提前回收条件", life.exit_mode, ["none", "ground", "bounds"], ["飞行过程完成", "触地", "离开边界"], R.setter(host, scope, "exit_mode", true))
	if life.exit_mode == "ground": R.number(host, exit, scope, life, "ground_y", "地面 Y 坐标", -2000, 2000)
	if life.exit_mode == "bounds": R.number(host, exit, scope, life, "bounds_margin", "边界外保留距离", 0, 2000)
	_successor(host, parent, scope, life, "on_hit", "命中后的后续行为")
	_successor(host, parent, scope, life, "on_expire", "自然结束后的后续行为")
	Extensions.effects(host, parent, scope, life)

static func _successor(host, parent, scope: Array, life, prefix: String, title: String) -> void:
	var box = F.fold(parent, title, false, "attack." + prefix)
	var attack_key = prefix + "_barrage_id"
	var flow_key = prefix + "_behavior_id"
	var mode = "attack" if not str(life.get(attack_key)).is_empty() else ("behavior" if not str(life.get(flow_key)).is_empty() else "none")
	F.select(box, "调用类型", mode, ["none", "attack", "behavior"], ["无", "招式", "行为子流程"], func(value):
		R.edit(host, scope, func(target, project):
			target.set(attack_key, project.barrages[0].id if value == "attack" and not project.barrages.is_empty() else "")
			target.set(flow_key, project.behaviors[0].id if value == "behavior" and not project.behaviors.is_empty() else "")))
	if mode != "none":
		var collection = "barrages" if mode == "attack" else "behaviors"
		var key = attack_key if mode == "attack" else flow_key
		R.resource_reference(host, box, scope, key, life.get(key), collection, "调用内容")
		R.reference_editor(host, box, collection, life.get(key), "编辑后续行为 →")

static func _presentation(host, parent, skill: STGBarrageSkill) -> void:
	var life = skill.projectile.lifecycle
	var scope = ["projectile", "lifecycle"]
	F.note(parent, "素材阶段动画与粒子自动播放；这里配置招式额外的音效和特效。相同表现只需在一处配置。")
	if skill.kind(host.session.project) != "summon": F.select(parent, "发射音效播放单位", skill.fire_pattern.sound_unit, ["cast", "round", "projectile"], ["每次释放", "每轮发射", "每颗弹体"], R.setter(host, ["fire_pattern"], "sound_unit"))
	R.number(host, parent, scope, life, "effect_duration", "特效最长持续 s", 0.01, 60)
	for pair in ([["spawn", "召唤"]] if skill.kind(host.session.project) == "summon" else [["spawn", "发射"], ["hit", "命中"], ["expire", "自然结束"]]):
		var box = F.group(parent, pair[1] + "表现")
		R.asset(host, box, pair[0] + "_sound", pair[1] + "音效", life.get(pair[0] + "_sound"), scope)
		R.asset(host, box, pair[0] + "_effect", pair[1] + "特效场景", life.get(pair[0] + "_effect"), scope)
	F.note(parent, "自然结束、命中、变形和强制清屏分别处理，不会把所有结束都当成命中。")

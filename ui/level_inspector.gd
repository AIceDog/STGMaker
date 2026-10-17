@tool
extends RefCounted
## 关卡表单：出场、阶段、环境各自一页；事件始终保存阶段内时间。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const D = preload("res://addons/stg_maker/authoring/defaults.gd")
const Commands = preload("res://addons/stg_maker/ui/level_commands.gd")
const Timing = preload("res://stg/definitions/level_timing.gd")

static func build(host, box, level: STGLevelDefinition) -> void:
	var segment: STGLevelSegment = host.level_segment()
	F.select(box, "当前阶段", str(host.segment_index), _indices(level.segments), level.segments.map(func(item): return item.title), func(value): host.select_level_segment(int(value)))
	match host.inspector_tab:
		0: _event(host, box, segment)
		1: _segment(host, box, level, segment)
		2: _background(host, box, level)

static func _event(host, box, segment: STGLevelSegment) -> void:
	var ids = segment.events.map(func(event): return event.id)
	var names = segment.events.map(func(event): return "%.2fs · %s" % [event.at, event.title])
	F.select(box, "出场事件", host.event_id, ids, names, host.select_level_event)
	F.button(box, "＋ 出场事件", func(): Commands.add_event(host))
	var event = host.level_event()
	if event == null:
		F.note(box, "在时间轴点击出场条，或从左侧拖入敌人、编队、障碍安排出场。")
		return
	var scope = host.level_event_scope()
	var group = F.group(box, "事件参数")
	F.text(group, "事件名称", event.title, R.setter(host, scope, "title"))
	R.number(host, group, scope, event, "at", "阶段内时间 s", 0, segment.duration)
	F.note(group, "全关计划 %.2f s；前一阶段等待时，这次出场整体顺延。" % (Timing.start(host.current(), host.segment_index) + event.at))
	var target_event = segment.exit_rule.mode != "time" and segment.exit_rule.condition == "defeat_target" and segment.exit_rule.target_event_id == event.id
	R.resource_reference(host, group, scope, "wave_id", event.wave_id, "waves", "使用编队", func(item): return not target_event or item.kind == "enemy")
	var wave = host.session.project.find("waves", event.wave_id)
	if wave != null: F.note(group, "%d 个实体 · 间隔 %.2f s · 生成历时 %.2f s" % [wave.count, wave.interval, (wave.count - 1) * wave.interval])
	R.reference_editor(host, group, "waves", event.wave_id, "编辑这份编队 →")
	R.vector(host, group, scope, event, "spawn_position", "编队出生点")
	F.button(group, "在画面拖动出生点", func(): host.set_tool("level_spawn"))
	var options = F.fold(box, "新建与复制", false)
	F.button(options, "新建敌人编队并使用 →", func(): Commands.add_wave_for_event(host, false))
	F.button(options, "新建障碍编队并使用 →", func(): Commands.add_wave_for_event(host, true))
	R.list_buttons(host, options, ["segments", host.segment_index, "events"], host.level_event_index(), func(): return D.level_event(event.wave_id), "+ 事件")
	F.note(box, "拖动出场条可跨阶段移动。条结束只表示生成结束；敌人的追踪、攻击和离场仍在实体定义中设置。")

static func _segment(host, box, level: STGLevelDefinition, segment: STGLevelSegment) -> void:
	F.text(box, "关卡名称", level.title, R.setter(host, [], "title"))
	var scope = ["segments", host.segment_index]
	var group = F.group(box, "阶段安排")
	F.text(group, "阶段名称", segment.title, R.setter(host, scope, "title"))
	F.number(group, "计划时长 s", segment.duration, func(value): Commands.resize_segment(host, value), 0.1, 600, 0.1)
	F.note(group, "缩短时长时，超出范围的事件会移到结尾；可以撤销。")
	R.number(host, group, scope, segment, "scroll_speed", "向左滚动速度", 0, 500)
	var rule = segment.exit_rule
	var ending = F.group(box, "推进条件")
	F.select(ending, "结束方式", rule.mode, STGLevelExitRule.MODES, STGLevelExitRule.MODE_LABELS, func(value): Commands.set_exit_mode(host, value))
	if rule.mode != "time":
		F.select(ending, "等待目标", rule.condition, STGLevelExitRule.CONDITIONS, STGLevelExitRule.CONDITION_LABELS, func(value): Commands.set_condition(host, value))
		if rule.condition == "defeat_target":
			var targets = segment.events.filter(func(item):
				var wave = host.session.project.find("waves", item.wave_id)
				return wave != null and wave.kind == "enemy")
			F.select(ending, "指定敌人出场", rule.target_event_id, targets.map(func(item): return item.id), targets.map(func(item): return item.title), R.setter(host, scope + ["exit_rule"], "target_event_id", true))
			if targets.is_empty(): F.note(ending, "先拖入敌人或敌人编队，再指定本阶段的击败目标。")
		F.toggle(ending, "等待所属攻击收尾", rule.wait_attacks, R.setter(host, scope + ["exit_rule"], "wait_attacks"))
		F.note(ending, "清场允许实体离场；击败目标只记录真实死亡。尚未生成的编队成员也计入目标，等待时战斗继续运行。")
	F.note(ending, "计划长度用于排版。实际耗时由推进条件决定，后续阶段一起顺延。" if rule.mode != "time" else "到达计划时长后进入下一阶段。")
	R.list_buttons(host, box, ["segments"], host.segment_index, func(): return D.level_segment(), "+ 阶段")
	var advanced = F.fold(box, "玩家出生点", false)
	R.vector(host, advanced, [], level, "player_spawn", "屏幕设计坐标")

static func _background(host, box, level: STGLevelDefinition) -> void:
	R.asset(host, box, "music", "背景音乐", level.music)
	F.note(box, "在测试选项中开启声音，音乐随预览暂停；测试射击和命中使用占位表现。")
	if not level.background_layers.is_empty():
		F.select(box, "背景层", str(host.background_index), _indices(level.background_layers), level.background_layers.map(func(item): return item.title), func(value): _select_background(host, int(value)))
		var layer = level.background_layers[host.background_index]
		var scope = ["background_layers", host.background_index]
		var group = F.group(box, "当前背景层")
		F.text(group, "名称", layer.title, R.setter(host, scope, "title"))
		R.number(host, group, scope, layer, "scroll_ratio", "滚动倍率", 0, 3)
		R.asset(host, group, "texture", "循环贴图", layer.texture, scope)
	R.list_buttons(host, box, ["background_layers"], host.background_index, func(): return D.background_layer(), "+ 背景层")
	F.note(box, "小倍率适合远景，大倍率适合近景。贴图按高度等比铺贴，建议使用左右可衔接的图像；空贴图显示滚动星点。")

static func _indices(entries: Array) -> Array:
	var result = []
	for i in entries.size(): result.append(str(i))
	return result

static func _select_background(host, index: int) -> void:
	host.background_index = index
	host.Inspector.build(host)

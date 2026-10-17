@tool
extends RefCounted
## Boss 属性入口：血量阶段、条件、动作段分别分组；连接仅在流程画布编辑。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const NodeFields = preload("res://addons/stg_maker/ui/behavior_node_fields.gd")
const EntityFields = preload("res://addons/stg_maker/ui/entity_fields.gd")

static func build(host, box, boss: STGBossDefinition) -> void:
	if host.inspector_tab == 3:
		EntityFields.build(host, box, boss.entity_settings)
		var death = F.group(box, "死亡时调用")
		_event(host, death, [], boss, "on_death_skill_id", "on_death_behavior_id", "死亡时调用")
		F.note(death, "死亡后调用一次；不是常规攻击循环。离场回收不会触发。")
		return
	# 阶段选择常驻；节点参数与阶段/美术分开，点击图节点会回到当前节点页。
	F.select(box, "当前血量阶段", str(host.phase_index), range(boss.phases.size()).map(func(i): return str(i)), boss.phases.map(func(phase): return phase.title), func(value):
		host.phase_index = int(value); host.flow_path.clear(); host.flow_node_id = ""; host.refresh(true))
	if host.inspector_tab <= 1: _node(host, box)
	else:
		F.text(box, "Boss 名称", boss.title, R.setter(host, [], "title"))
		_phase_settings(host, box, boss)
		_appearance(host, box, boss)

static func _phase_settings(host, box, boss: STGBossDefinition) -> void:
	var phase = host.boss_phase()
	var scope = ["phases", host.phase_index]
	var settings = F.group(box, "阶段设置", "boss.phase.settings")
	F.text(settings, "阶段名称", phase.title, R.setter(host, scope, "title", true))
	R.number(host, settings, scope, phase, "life", "血条编号（0 起）", 0, 20, 1)
	F.select(settings, "进入方式", phase.entry_mode, ["hp", "sequence"], ["当前血条降至阈值", "前阶段结束后进入"], R.setter(host, scope, "entry_mode", true))
	if host.phase_index > 0 and phase.entry_mode == "hp": R.number(host, settings, scope, phase, "enter_hp", "进入血量 ≤ %", 0, 100)
	var transition = F.fold(settings, "血条、转场与限时结束", false, "boss.phase.transition")
	R.number(host, transition, scope, phase, "life_hp", "新血条初始血量 %", 1, 100)
	R.number(host, transition, scope, phase, "entry_delay", "转场等待 s", 0, 60)
	F.toggle(transition, "转场期间无敌", phase.entry_invulnerable, R.setter(host, scope, "entry_invulnerable"))
	_event(host, transition, scope, phase, "entry_barrage_id", "entry_behavior_id", "转场期间调用")
	F.toggle(transition, "进入时清理旧攻击", phase.clear_on_enter, R.setter(host, scope, "clear_on_enter"))
	R.number(host, transition, scope, phase, "time_limit", "阶段限时 s（0 不限时）", 0, 600)
	F.select(transition, "限时结束后", phase.time_exit, ["next", "life_start", "finish"], ["进入下一阶段", "回到本血条首阶段", "Boss 结束"], R.setter(host, scope, "time_exit"))
	F.select(transition, "血条耗尽后", phase.depleted_exit, ["auto", "next", "finish"], ["进入下一条血 / 最后死亡", "进入下一阶段并补血", "真实死亡"], R.setter(host, scope, "depleted_exit"))
	R.number(host, transition, scope, phase, "depleted_refill", "同血条换阶段补血 %", 1, 100)
	F.note(transition, "编号相同共用血量；更大的编号代表新血条。限时会中断动作；血量阈值换阶段仍等待攻击收尾。")
	F.toggle(settings, "循环此阶段流程", phase.loop, R.setter(host, scope, "loop", true))
	if phase.loop:
		var ids = [""]
		var labels = ["从流程开头"]
		for node in phase.behavior_flow.nodes:
			ids.append(node.id)
			labels.append("%s · %s" % [node.title, STGFlowNode.LABELS[STGFlowNode.KINDS.find(node.kind)]])
		F.select(settings, "后续循环起点", phase.behavior_flow.loop_entry_id, ids, labels, R.setter(host, scope + ["behavior_flow"], "loop_entry_id"))
		F.note(settings, "第一轮从流程开头执行；后续循环从这里开始，可让入场与首轮准备只执行一次。")
	F.label(settings, "新血量阶段等待当前动作和旧阶段攻击收尾。")
	var operations = HFlowContainer.new(); settings.add_child(operations)
	var add_stage = F.button(operations, "＋ 阶段", func(): host.Commands.edit_list(host, ["phases"], "add", func():
		var next = Defaults.phase(host.session.project.barrages[0].id if not host.session.project.barrages.is_empty() else "")
		next.title = "新 Boss 阶段"; next.enter_hp = maxf(1, boss.phases[-1].enter_hp - 25)
		return next, host.phase_index))
	add_stage.disabled = boss.phases[-1].enter_hp <= 1
	add_stage.tooltip_text = "最后一个血量阶段已到 1%；先提高其进入阈值。" if add_stage.disabled else "添加一个血量更低的阶段。"
	var remove_stage = F.button(operations, "删除阶段", func(): host.Commands.edit_list(host, ["phases"], "remove", func(): return null, host.phase_index), "danger")
	remove_stage.disabled = boss.phases.size() <= 1
	remove_stage.tooltip_text = "至少保留一个血量阶段。" if remove_stage.disabled else "删除当前血量阶段；可以撤销。"

static func _node(host, box) -> void: NodeFields.build(host, box)

static func _appearance(host, box, boss: STGBossDefinition) -> void:
	var appearance = F.group(box, "Boss 表现与起点", "boss.appearance")
	R.asset(host, appearance, "visual_scene", "表现场景", boss.visual_scene)
	F.label(appearance, "可选 Node2D 场景，内含 Sprite2D / AnimatedSprite2D 与 AnimationPlayer。")
	R.asset(host, appearance, "texture", "备用贴图", boss.texture)
	R.vector(host, appearance, [], boss, "start_position", "出生位置")

static func _event(host, box, scope: Array, target, attack_key: String, behavior_key: String, title: String) -> void:
	var mode = "attack" if not str(target.get(attack_key)).is_empty() else ("behavior" if not str(target.get(behavior_key)).is_empty() else "none")
	F.select(box, title, mode, ["none", "attack", "behavior"], ["不调用", "招式", "行为子流程"], func(value):
		R.edit(host, scope, func(config, project):
			config.set(attack_key, project.barrages[0].id if value == "attack" and not project.barrages.is_empty() else "")
			config.set(behavior_key, project.behaviors[0].id if value == "behavior" and not project.behaviors.is_empty() else "")))
	if mode == "none": return
	var collection = "barrages" if mode == "attack" else "behaviors"
	var key = attack_key if mode == "attack" else behavior_key
	R.resource_reference(host, box, scope, key, target.get(key), collection, "调用内容")
	R.reference_editor(host, box, collection, target.get(key), "编辑调用内容 →")

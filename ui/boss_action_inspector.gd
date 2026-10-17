@tool
extends RefCounted
## 动作段表单接口 build：攻击 / 移动 / 表现 / 时序。默认只显示必要参数。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const MovementFields = preload("res://addons/stg_maker/ui/boss_movement_fields.gd")
const Presentation = preload("res://stg/definitions/scene_contract.gd")

static func build(host, box, card: STGBossAction) -> void:
	var custom = F.fold(box, "自定义敌人动作", card.extension != null, "action.extension")
	preload("res://addons/stg_maker/ui/extension_fields.gd").slot(host, custom, host.boss_action_scope(), "extension", "action", "动作模块")
	if card.extension != null:
		R.number(host, custom, host.boss_action_scope(), card, "duration", "动作执行上限 s", 0.01, 60)
		F.toggle(custom, "受击时中断", card.interrupt_on_hit, R.setter(host, host.boss_action_scope(), "interrupt_on_hit"))
		return
	if host.inspector_tab == 0:
		F.note(box, "前摇 %.2f 秒 → 执行 → 后摇 %.2f 秒" % [card.windup, card.recovery])
		F.button(box, "调整前后摇与动画 →", func(): host.select_inspector_tab(1))
		_attack(host, F.group(box, "攻击"), card)
		_movement(host, F.group(box, "移动"), card)
	else:
		_timing(host, F.group(box, "动作时序"), card)
		_presentation(host, F.group(box, "表现与动画", "boss.action.presentation"), card)

static func _attack(host, box, card: STGBossAction) -> void:
	var scope = host.boss_action_scope() + ["attack"]
	var attack = card.attack
	F.toggle(box, "使用弹幕招式", attack.enabled, func(value):
		R.edit(host, host.boss_action_scope(), func(action, project):
			action.attack.enabled = value
			if value:
				if action.attack.barrage_id.is_empty() and not project.barrages.is_empty(): action.attack.barrage_id = project.barrages[0].id
				action.end_when = "attack"
			else:
				action.end_when = "movement" if action.movement.mode != "none" else "time"
				if action.movement_start in ["attack_start", "attack_end"]: action.movement_start = "active"))
	if not attack.enabled: return
	var parameters = F.group(box, "招式参数")
	F.select(parameters, "调用类型", "behavior" if not attack.behavior_id.is_empty() else "attack", ["attack", "behavior"], ["招式", "行为子流程"], func(value):
		R.edit(host, scope, func(target, project):
			target.barrage_id = project.barrages[0].id if value == "attack" and not project.barrages.is_empty() else ""
			target.behavior_id = project.behaviors[0].id if value == "behavior" and not project.behaviors.is_empty() else ""))
	var collection = "behaviors" if not attack.behavior_id.is_empty() else "barrages"
	var field = "behavior_id" if collection == "behaviors" else "barrage_id"
	R.resource_reference(host, parameters, scope, field, attack.get(field), collection, "调用内容")
	R.reference_editor(host, parameters, collection, attack.get(field), "编辑调用内容 →")
	F.select(parameters, "攻击结束时机", attack.finish_event, ["immediate", "emission", "cleared", "duration"], ["释放后立即继续", "发射完成", "相关子弹全部结束", "指定持续时长"], R.setter(host, scope, "finish_event", true))
	var advanced = F.fold(parameters, "发射位置与收尾", false, "boss.attack.advanced")
	F.select(advanced, "发射原点", attack.origin_mode, ["boss", "player", "world"], ["Boss 当前坐标 + 偏移", "玩家坐标 + 偏移", "固定战斗坐标"], R.setter(host, scope, "origin_mode", true))
	if attack.origin_mode == "boss": F.toggle(advanced, "后续发射跟随 Boss", attack.follow_boss, R.setter(host, scope, "follow_boss"))
	R.vector(host, advanced, scope, attack, "origin_offset", "发射偏移 / 坐标")
	F.toggle(advanced, "收尾时清除本次子弹", attack.clear_on_end, R.setter(host, scope, "clear_on_end"))
	F.label(advanced, "默认停止未来发射，已生成的子弹与尾迹继续收尾。")

static func _movement(host, box, card: STGBossAction) -> void:
	MovementFields.build(host, box, card.movement, host.boss_action_scope() + ["movement"], func(value):
		R.edit(host, host.boss_action_scope(), func(action, _project):
			var adding: bool = action.movement.mode == "none" and value != "none"
			action.movement.mode = value
			if value in ["teleport", "ballistic"] and action.movement.aiming == "track": action.movement.aiming = "snapshot"
			if not action.attack.enabled: action.end_when = "time" if value == "none" else "movement"
			elif adding: action.movement_start = "attack_start"))

static func _presentation(host, box, card: STGBossAction) -> void:
	var names: Array = [""]
	var scene: PackedScene = host.current().visual_scene if host.current() is STGBossDefinition else null
	if scene != null:
		var visual = scene.instantiate()
		var player = Presentation.find_player(visual)
		if player != null:
			for name in player.get_animation_list():
				if name != "RESET": names.append(str(name))
		visual.free()
	var titles = names.map(func(name): return "不播放动画" if name.is_empty() else name)
	var scope = host.boss_action_scope() + ["presentation"]
	for pair in [["windup_animation", "前摇动画"], ["active_animation", "执行动画"], ["recovery_animation", "后摇动画"]]:
		var current: String = card.presentation.get(pair[0])
		var available = names.duplicate(); var labels = titles.duplicate()
		if not current in available: available.append(current); labels.append("未找到：" + current)
		F.select(box, pair[1], current, available, labels, R.setter(host, scope, pair[0]))
	F.label(box, "在 Boss 表现与起点中选择场景。前后摇动画自动适配逻辑时长；执行动画循环播放或停留末帧。")

static func _timing(host, box, card: STGBossAction) -> void:
	var scope = host.boss_action_scope()
	var move = card.movement
	R.number(host, box, scope, card, "windup", "前摇 s", 0, 30)
	if card.end_when == "time" or (card.attack.enabled and card.attack.finish_event == "duration"): R.number(host, box, scope, card, "duration", "持续时长 s", 0.01, 60)
	R.number(host, box, scope, card, "recovery", "后摇 s", 0, 30)
	var endings = ["time"]; var ending_labels = ["指定持续时长"]
	if card.attack.enabled: endings.push_front("attack"); ending_labels.push_front("攻击结束")
	if move.mode != "none": endings.append("movement"); ending_labels.append("移动结束")
	if card.attack.enabled and move.mode != "none": endings.append("both"); ending_labels.append("攻击与移动都结束")
	F.select(box, "进入后摇的时机", card.end_when, endings, ending_labels, R.setter(host, scope, "end_when", true))
	var advanced = F.fold(box, "开始关系与中断", false, "boss.action.timing")
	if card.attack.enabled:
		F.select(advanced, "攻击开始", card.attack_start, ["active", "movement_end"], ["前摇结束", "移动结束后"], R.setter(host, scope, "attack_start"))
		R.number(host, advanced, scope, card, "attack_delay", "攻击额外延迟 s", 0, 30)
	if move.mode != "none":
		F.select(advanced, "移动开始", card.movement_start, ["windup", "active", "attack_start", "attack_end"], ["前摇开始", "前摇结束", "攻击开始时", "攻击结束后"], R.setter(host, scope, "movement_start"))
		R.number(host, advanced, scope, card, "movement_delay", "移动额外延迟 s", 0, 30)
	F.toggle(advanced, "受击时中断当前动作", card.interrupt_on_hit, R.setter(host, scope, "interrupt_on_hit"))
	F.label(box, "收尾时停止移动并进入后摇；后摇完成才走下一条连线。")

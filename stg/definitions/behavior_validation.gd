@tool
extends RefCounted
## 预览/导出共用的流程校验。分支可以汇合；循环由阶段 loop 控制。
const Locations = preload("res://stg/definitions/validation_locations.gd")
const Presentation = preload("res://stg/definitions/scene_contract.gd")
const MovementValidation = preload("res://stg/definitions/movement_validation.gd")

static func check(flow: STGBehaviorFlow, project, issues: PackedStringArray, title: String, locations: Variant = null, boss_id: String = "", phase_index: int = 0, parents: Array = [], scope: Array = []) -> void:
	if flow != null and (flow in parents or parents.size() >= 32):
		issues.append(title + "：内嵌行为形成循环或超过32层")
		return
	if flow == null or flow.nodes.is_empty():
		issues.append(title + "：需要行为流程")
		return
	if flow.nodes.size() > 128:
		issues.append(title + "：流程最多 128 个节点")
		return
	var ids = {}
	var flow_scope = scope if not parents.is_empty() or phase_index < 0 else ["phases", phase_index, "behavior_flow"]
	for node_index in flow.nodes.size():
		var node = flow.nodes[node_index]
		var start = issues.size()
		if node == null:
			issues.append(title + "：空流程节点")
			continue
		if node.id.is_empty() or ids.has(node.id) or STGFlowNode.is_terminal(node.id):
			issues.append(title + "：节点 ID 无效或重复")
		ids[node.id] = true
		if node.kind not in STGFlowNode.KINDS:
			issues.append(title + "：未知节点类型")
		if not node.editor_position.is_finite():
			issues.append(title + "：节点画布坐标无效")
		for target in node.outputs():
			if not STGFlowNode.is_terminal(target) and flow.find(target) == null:
				issues.append(title + "：连接目标不存在")
		if node.kind == "action":
			check_action(node.action, project, issues, title + " / " + node.title)
		elif node.kind == "condition":
			if node.condition not in ["hp", "distance", "cooldown", "recent_hit", "extension"] or node.comparison not in ["less_equal", "greater_equal"]:
				issues.append(title + "：判断类型无效")
			if not is_finite(node.threshold) or node.threshold < 0 or (node.condition == "hp" and node.threshold > 100):
				issues.append(title + "：判断阈值无效")
			if node.condition == "extension":
				if node.extension == null: issues.append(title + "：请选择自定义条件")
				else:
					for issue in node.extension.validate("condition"): issues.append(title + "：" + issue)
			if node.condition == "cooldown":
				var referenced = flow.find(node.reference_id)
				if referenced == null or referenced.kind != "action":
					issues.append(title + "：冷却判断需要引用动作段")
		elif node.kind == "random" and node.choices.is_empty():
			issues.append(title + "：随机节点至少需要一个分支")
		if node.kind == "attack":
			if project.find("barrages", node.barrage_id) == null: issues.append(title + "：节点招式引用不存在")
			if node.wait_mode not in ["immediate", "emission", "cleared"]: issues.append(title + "：等待方式无效")
		elif node.kind == "call":
			if project.find("behaviors", node.behavior_id) == null: issues.append(title + "：行为引用不存在")
		elif node.kind == "wait":
			if not is_finite(node.delay) or node.delay < 0: issues.append(title + "：等待时间无效")
		elif node.kind == "parallel":
			if node.children.is_empty(): issues.append(title + "：并行节点至少需要一个分支")
			for child_index in node.children.size():
				var child = node.children[child_index]
				if child is STGBehaviorFlow: check(child, project, issues, title + " / 并行", locations, boss_id, phase_index, parents + [flow], flow_scope + ["nodes", node_index, "children", child_index])
				else: issues.append(title + "：并行分支必须是行为流程")
		Locations.mark(issues, start, locations, "behaviors" if phase_index < 0 else "bosses", boss_id, flow_scope + ["nodes", node_index])
	if flow.find(flow.entry_id) == null:
		issues.append(title + "：开始节点未连接")
		return
	if not flow.loop_entry_id.is_empty() and flow.find(flow.loop_entry_id) == null:
		issues.append(title + "：循环起点不存在")
	var visited = {}
	_walk(flow, flow.entry_id, [], visited, issues, title)
	if visited.size() != ids.size():
		issues.append(title + "：存在未接入流程的节点")

static func _walk(flow, id: String, ancestors: Array, visited: Dictionary, issues: PackedStringArray, title: String) -> void:
	if STGFlowNode.is_terminal(id):
		return
	if id in ancestors:
		issues.append(title + "：连接形成循环，请使用阶段的循环开关")
		return
	if visited.has(id):
		return
	var node = flow.find(id)
	if node == null:
		return
	visited[id] = true
	var next = ancestors.duplicate()
	next.append(id)
	for target in node.outputs():
		_walk(flow, target, next, visited, issues, title)

static func check_action(card: STGBossAction, project, issues: PackedStringArray, title: String) -> void:
	if card != null and card.extension != null:
		for issue in card.extension.validate("action"): issues.append(title + "：" + issue)
		if not is_finite(card.duration) or card.duration <= 0 or card.duration > 60: issues.append(title + "：自定义动作上限需为 0–60 秒")
		return
	if card == null or card.attack == null or card.movement == null or card.presentation == null:
		issues.append(title + "：动作段缺少攻击 / 移动 / 表现配置")
		return
	var attack = card.attack
	var move = card.movement
	MovementValidation.check(move, issues, title)
	for value in [card.windup, card.duration, card.recovery, card.attack_delay, card.movement_delay]:
		if not is_finite(value) or value < 0:
			issues.append(title + "：时间 / 移动参数必须是非负有限数值")
	if card.duration <= 0:
		issues.append(title + "：持续时长必须大于零")
	if not attack.origin_offset.is_finite():
		issues.append(title + "：发射原点坐标无效")
	if attack.enabled and (project.find("behaviors", attack.behavior_id) == null if not attack.behavior_id.is_empty() else project.find("barrages", attack.barrage_id) == null):
		issues.append(title + "：弹幕招式引用不存在")
	if attack.finish_event not in ["immediate", "emission", "cleared", "duration"] or attack.origin_mode not in ["boss", "player", "world"]:
		issues.append(title + "：攻击结束事件 / 原点无效")
	if card.end_when not in ["attack", "movement", "both", "time"] or card.attack_start not in ["active", "movement_end"] or card.movement_start not in ["windup", "active", "attack_start", "attack_end"]:
		issues.append(title + "：动作时序无效")
	if card.end_when == "attack" and not attack.enabled:
		issues.append(title + "：未启用攻击，不能等待攻击结束")
	if card.end_when == "movement" and move.mode == "none":
		issues.append(title + "：未启用移动，不能等待移动结束")
	if move.mode != "none":
		if card.movement_start in ["attack_start", "attack_end"] and not attack.enabled:
			issues.append(title + "：移动等待攻击，但未启用攻击")
		if card.movement_start == "windup" and card.movement_delay > card.windup:
			issues.append(title + "：移动延迟超过前摇，无法开始")
		if attack.enabled and card.attack_start == "movement_end" and card.movement_start in ["attack_start", "attack_end"]:
			issues.append(title + "：攻击与移动互相等待，无法执行")
		if card.end_when == "attack" and card.movement_start == "attack_end":
			issues.append(title + "：攻击后移动需等待双方完成，或指定持续时长")
		if attack.enabled and card.end_when == "movement" and card.attack_start == "movement_end":
			issues.append(title + "：移动后攻击需等待双方完成，或指定持续时长")

static func check_presentation(boss: STGBossDefinition, issues: PackedStringArray) -> void:
	var visual: Node
	var player: AnimationPlayer
	if boss.visual_scene != null:
		visual = boss.visual_scene.instantiate()
		if not visual is Node2D:
			issues.append(boss.title + "：表现场景根节点必须是 Node2D")
		player = Presentation.find_player(visual)
	for phase in boss.phases:
		if phase == null or phase.behavior_flow == null:
			continue
		for node in phase.behavior_flow.nodes:
			if node == null or node.action == null or node.action.extension != null or node.action.presentation == null:
				continue
			var config = node.action.presentation
			for key in ["windup_animation", "active_animation", "recovery_animation"]:
				var name: String = config.get(key)
				if name.is_empty():
					continue
				if player == null or not player.has_animation(name):
					issues.append(boss.title + " / " + node.title + "：动画不存在：" + name)
				elif key != "active_animation" and player.get_animation(name).loop_mode != Animation.LOOP_NONE:
					issues.append(boss.title + "：前摇 / 后摇动画不能循环")
	if visual != null:
		visual.free()

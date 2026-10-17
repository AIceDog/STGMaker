@tool
extends RefCounted
## 敌人与子流程共用节点编辑入口，递归分支只改变编辑路径。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const D = preload("res://stg/definitions/definition_factory.gd")
const Actions = preload("res://addons/stg_maker/ui/boss_action_inspector.gd")

static func build(host, parent) -> void:
	if not host.flow_path.is_empty(): F.button(parent, "← 返回上级流程", host.leave_flow_branch, "link")
	var node = host.boss_node()
	if node == null: F.note(parent, "在流程图中选择节点。"); return
	var scope = host.boss_node_scope()
	F.note(parent, "选中节点 · " + STGFlowNode.LABELS[STGFlowNode.KINDS.find(node.kind)])
	if host.inspector_tab == 0: F.text(parent, "节点名称", node.title, R.setter(host, scope, "title"))
	match node.kind:
		"action": Actions.build(host, parent, node.action)
		"attack", "call":
			var collection = "barrages" if node.kind == "attack" else "behaviors"
			var field = "barrage_id" if node.kind == "attack" else "behavior_id"
			R.resource_reference(host, parent, scope, field, node.get(field), collection, "调用内容")
			R.reference_editor(host, parent, collection, node.get(field), "编辑调用内容 →")
			F.select(parent, "继续流程的时机", node.wait_mode, ["immediate", "emission", "cleared"], ["释放后立即继续", "等待发射完成", "等待攻击全部结束"], R.setter(host, scope, "wait_mode"))
			F.note(parent, "继续流程不会自动清除已经发出的子弹。")
		"wait": R.number(host, parent, scope, node, "delay", "等待时间 s", 0, 600, 0.001)
		"parallel":
			F.note(parent, "所有分支同时开始，全部完成后走下一条连线。")
			for index in node.children.size():
				var row = HBoxContainer.new()
				parent.add_child(row)
				F.button(row, "编辑分支 %d →" % (index + 1), func(): host.enter_flow_branch(index))
				F.button(row, "删除分支", func(): R.edit(host, scope, func(target, _project): target.children.remove_at(index)), "danger")
			F.button(parent, "＋ 并行分支", func(): R.edit(host, scope, func(target, _project): target.children.append(D.flow())))
		"condition": _condition(host, parent, node, scope)
		"random": F.note(parent, "每轮随机尝试一个分支，完成或失败后沿对应连线继续。")

static func _condition(host, parent, node: STGFlowNode, scope: Array) -> void:
	F.select(parent, "判断内容", node.condition, ["distance", "hp", "cooldown", "recent_hit", "extension"], ["与玩家距离", "敌人血量 %", "动作冷却", "最近受击", "自定义条件"], R.setter(host, scope, "condition", true))
	if node.condition == "extension":
		preload("res://addons/stg_maker/ui/extension_fields.gd").slot(host, parent, scope, "extension", "condition", "条件模块", false)
		return
	F.select(parent, "比较", node.comparison, ["less_equal", "greater_equal"], ["小于等于", "大于等于"], R.setter(host, scope, "comparison"))
	R.number(host, parent, scope, node, "threshold", "判断阈值", 0, 4000)
	if node.condition == "cooldown":
		var actions = host.boss_flow().nodes.filter(func(item): return item.kind == "action")
		F.select(parent, "检查动作段", node.reference_id, actions.map(func(item): return item.id), actions.map(func(item): return item.title), R.setter(host, scope, "reference_id"))

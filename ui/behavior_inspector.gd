@tool
extends RefCounted
## 可复用行为使用与敌人相同的图编辑器和节点表单。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const Nodes = preload("res://addons/stg_maker/ui/behavior_node_fields.gd")

static func build(host, parent, flow: STGBehaviorFlow) -> void:
	if host.inspector_tab == 2:
		F.text(parent, "流程名称", flow.title, R.setter(host, [], "title"))
		F.note(parent, "其他敌人、命中效果和流程可以引用此资产，修改后所有引用处同步。")
	else: Nodes.build(host, parent)

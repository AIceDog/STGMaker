@tool
extends RefCounted
## 只读选择上下文：中间画布选择什么，右侧就说明正在修改什么。
## 这里只读取工作台选择，不触发刷新、运行重置或制作快照。
const Library = preload("res://addons/stg_maker/ui/library_ui.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")

static func update(host) -> void:
	var resource = host.current()
	host.inspector_context.visible = not host.navigation.parents.is_empty()
	var path: Array[String] = []
	for parent in host.navigation.parents:
		var caller = host.session.project.find(parent.collection, parent.id)
		if caller != null:
			path.append(caller.title)
	if resource == null:
		host.inspector_caption.text = "尚未选择资源"
		host.inspector_context.text = "在左侧选择资源或新建模板"
		host.workspace_caption.text = "预览工作区"
		return
	if not host.Structure.issue(resource).is_empty():
		host.inspector_caption.text = resource.title + " · 结构待补齐"
		host.workspace_caption.text = resource.title
		host.inspector_context.text = "在属性栏补齐结构后继续编辑；不会自动改写草稿。"
		return
	path.append(resource.title)
	var target = Library.TITLES[host.collection]
	if resource is STGLevelDefinition:
		var segment = host.level_segment()
		if host.inspector_tab < 2:
			path.append(segment.title)
		if host.inspector_tab == 0:
			var event = host.level_event()
			target = "出场事件 · " + (event.title if event != null else "尚未选择")
			if event != null:
				path.append(event.title)
		elif host.inspector_tab == 1:
			target = "关卡阶段 · " + segment.title
		else:
			target = "整关背景 / 音乐"
	elif resource is STGBossDefinition:
		if host.inspector_tab < 3:
			path.append(host.boss_phase().title)
		if host.inspector_tab < 2:
			var node = host.boss_node()
			target = "行为节点 · " + (node.title if node != null else "尚未选择")
			if node != null:
				path.append(node.title)
		elif host.inspector_tab == 2:
			target = "血量阶段 / 美术"
		else:
			target = "实体移动 / 离场"
	elif resource is STGBehaviorFlow:
		var node = host.boss_node()
		target = "行为节点 · " + (node.title if node != null else "尚未选择")
		if node != null: path.append(node.title)
	host.inspector_caption.text = target
	F.help(host.inspector_caption, "当前正在修改：" + target + "\n下方显示它的参数；作用范围以具体设置为准。")
	host.inspector_context.text = " › ".join(path)
	F.help(host.inspector_context, "编辑关系：" + " → ".join(path) + "\n从左侧返回调用它的招式、敌人或关卡。\n进入共享素材页修改后，所有使用处同步。")
	if (resource is STGBossDefinition or resource is STGBehaviorFlow) and host.boss_view == "flow":
		host.workspace_caption.text = "行为 · " + resource.title
		host.workspace_caption.tooltip_text = "点选流程节点，在右侧修改当前节点；连线表示行为的下一步。"
	elif resource is STGLevelDefinition:
		host.workspace_caption.text = "关卡 · " + resource.title
		host.workspace_caption.tooltip_text = "下方时间轴安排阶段与出场；点选条目后在右侧修改对应属性。"
	else:
		host.workspace_caption.text = resource.title
		host.workspace_caption.tooltip_text = "预览左侧选中的资源；参数在右侧修改。开始测试后可点击画面控制玩家。"

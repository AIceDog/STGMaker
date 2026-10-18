@tool
extends RefCounted
## 时间轴制作工具与条件调试展示；调度结论和对象统计均查询真实运行器。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const REASONS = {"": "存活", "died": "已击败", "escaped": "越界离场", "timeout": "超时离场", "phase_end": "阶段结束离场"}

static func build(host, parent: Node) -> Control:
	# 和现有工具处于同一个流式容器，避免嵌套容器只分到一个按钮的宽度。
	var row = parent
	F.label(row, "吸附")
	var snap = OptionButton.new()
	snap.name = "TimelineSnap"
	var values = [0.0, 0.1, 0.5, 1.0]
	for text in ["关闭", "0.1 秒", "0.5 秒", "1 秒"]: snap.add_item(text)
	snap.select(values.find(host.level_timeline.snap_interval))
	snap.item_selected.connect(func(index): host.level_timeline.set_snap_interval(values[index]))
	row.add_child(snap)
	F.help(snap, "拖动出场条、阶段右缘和拖入素材时对齐时间格。\n关闭时保留百分之一秒精度。\n多选时以拖动的条对齐，其他条保留相对间距。")
	var selection = F.note(row, "")
	selection.name = "TimelineSelection"
	var update = func(count): selection.text = "已选 %d 条 · 一起移动" % count if count > 1 else "Ctrl 点选 / 拖框多选"
	update.call(host.level_timeline.selected_event_ids.size())
	host.level_timeline.selection_changed.connect(update)
	F.help(selection, "Ctrl 或 Shift 点击可加入 / 取消选中。\n从空白处拖动框选，按住 Ctrl / Shift 可追加。\n拖动已选条一起移动，只产生一次撤销；\n整批到关卡边界时停止，保留各条的时间间距。\n跨阶段会重新计算阶段内时间；击败目标不可跨段。\n右侧属性仍编辑最后点击的单个对象。")
	F.help(F.button(row, "清除选择", func(): host.level_timeline.clear_selection()), "取消时间轴的多选；Esc 也可清除，并取消尚未提交的拖动。")
	return row

static func build_debug(parent: Node) -> Control:
	var panel = VBoxContainer.new()
	parent.add_child(panel)
	panel.name = "LevelConditionDebug"
	var summary = F.note(panel, "")
	panel.set_meta("summary", summary)
	var body = F.fold(panel, "阶段推进调试 · 查看目标对象", false, "level.condition_debug")
	panel.set_meta("body", panel.get_child(panel.get_child_count() - 1))
	var tree = Tree.new()
	tree.columns = 2
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.set_column_title(0, "条件目标 / 实例")
	tree.set_column_title(1, "真实运行状态")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 190)
	tree.custom_minimum_size.y = 150
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tree)
	F.help(tree, "此列表只读，来自当前测试中的生成任务和死亡 / 离场记录。\n待生成成员同样阻止提前清场；离场不等于击败。\n实例编号只用于定位本次测试，重测后会重置。")
	panel.set_meta("tree", tree)
	return panel

static func update_debug(panel: Control, world) -> void:
	var active = world is STGLevelSimulation and world.definition != null and not world.completed
	panel.visible = active
	if not active: return
	var snapshot: Dictionary = world.goals.inspect(world)
	panel.get_meta("body").visible = snapshot.has_condition
	var summary: Label = panel.get_meta("summary")
	var tree: Tree = panel.get_meta("tree")
	var totals = "待生成 %d · 存活 %d · 离场 %d · 击败 %d" % [snapshot.pending, snapshot.alive, snapshot.departed, snapshot.defeated]
	var state: String = snapshot.blocked if not snapshot.blocked.is_empty() else snapshot.failed
	if state.is_empty(): state = "是否可推进由当前阶段的结束规则判定。"
	summary.text = totals + (" · 攻击 %d / 收尾来源 %d" % [snapshot.remaining_attacks, snapshot.finishing] if world.segment().exit_rule.wait_attacks else "")
	if not snapshot.has_condition: summary.text = "本阶段按时间推进，无需等待清场或击败目标。"
	F.help(summary, state + "\n" + world.status())
	# 状态相同不重建，保留树节点展开状态，避免每个预览帧重新分配控件。
	var signature = var_to_str(snapshot)
	if panel.get_meta("snapshot", "") == signature: return
	panel.set_meta("snapshot", signature)
	var collapsed: Dictionary = {}
	var old_root = tree.get_root()
	if old_root != null:
		for child in old_root.get_children(): collapsed[child.get_metadata(0)] = child.collapsed
	tree.clear()
	var root = tree.create_item()
	for event in snapshot.events:
		var item = tree.create_item(root)
		item.set_metadata(0, event.id)
		item.collapsed = collapsed.get(event.id, true)
		item.set_text(0, event.title)
		item.set_tooltip_text(0, event.title)
		item.set_text(1, "待生成 %d · 存活 %d · 离场 %d · 击败 %d" % [event.pending, event.alive, event.departed, event.defeated])
		if event.finishing > 0: item.set_text(1, item.get_text(1) + " · 收尾 %d" % event.finishing)
		item.set_tooltip_text(1, item.get_text(1))
		if event.pending > 0:
			var pending = tree.create_item(item)
			pending.set_text(0, "尚未生成的编队成员")
			pending.set_text(1, "%d 个" % event.pending)
		for instance in event.instances:
			var child = tree.create_item(item)
			child.set_text(0, "实例 #%d" % instance.id)
			child.set_text(1, REASONS.get(instance.reason, "离场（%s）" % instance.reason) + (" · 攻击收尾中" if instance.finishing else ""))

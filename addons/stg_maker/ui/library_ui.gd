@tool
extends RefCounted
## 资源列表接口 build/refresh：搜索仅过滤显示，不修改项目和当前资源。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Palette = preload("res://addons/stg_maker/ui/level_palette.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
const FlyTiger = preload("res://addons/stg_maker/authoring/templates/flytiger_enemy_library.gd")
const FlyTigerBosses = preload("res://addons/stg_maker/authoring/templates/flytiger_boss_library.gd")
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
static var _flytiger_source: STGProject
static var _flytiger_boss_source: STGProject
const TEMPLATES = {
	"behaviors": [["空白行为子流程", "behavior"]],
	"bullets": [["子弹", "moving"], ["激光", "laser"], ["拖尾", "trail"], ["区域", "area"]],
	"barrages": [["扇形连射", "fan"], ["圆环齐射", "ring"], ["螺旋发射", "spiral"], ["瞄准连射", "aim"], ["交叉激光", "cross"], ["区域预警", "area"], ["持续路径尾迹", "trail"]],
	"bosses": [["普通卷轴敌人", "enemy"], ["顺序攻击 Boss", "boss"], ["根据玩家距离选择攻击", "conditional_boss"], ["动画时序示例 Boss", "animated_boss"], ["缩圈尾迹 Boss", "shrinking_trail_boss"]],
	"levels": [["空白关卡", "empty_level"], ["敌人巡航关卡", "level"], ["巡航 → 障碍 → Boss", "three_section"]],
	"waves": [["敌人编队", "enemy_wave"], ["障碍编队", "obstacle_wave"]],
	"obstacles": [["滚动岩石", "obstacle"]],
}
const TITLES = References.LABELS
const GUIDES = {
	"bullets": "子弹、激光、拖尾、区域是并列素材；各自保存外观、碰撞和动画粒子表现。",
	"behaviors": "可复用行为流程：组合招式、等待与并行分支。",
	"barrages": "一份招式定义一套发射、运动与生命周期；组合交给敌人行为流程。",
	"bosses": "连接动作顺序，再点击节点编辑攻击与移动。",
	"levels": "拖入时间轴安排出场。\n双击素材编辑定义。",
	"waves": "编队只配置出场和排列；\n敌人的攻击和 AI 仍在敌人定义中编辑。",
	"obstacles": "障碍复用实体生命周期；通过编队安排出场。",
}
const TEMPLATE_HINTS = {
	"moving": "可移动的弹丸素材；在招式中设置发射与飞行。",
	"laser": "激光素材，用长度、宽度或曲线路径定义攻击范围。",
	"area": "区域外观与碰撞；预警、伤害和持续时间在招式中配置。",
	"trail": "路径尾迹外观与采样；生成时长、命中和淡出在招式中配置。",
	"behavior": "连接招式、等待、并行和子流程；可供多个敌人或生命周期事件调用。",
	"fan": "多颗弹向一片扇面发射，可调整数量、展开角度与连发节奏。",
	"ring": "沿圆周生成并向外发射，可调整数量、生成半径与飞行过程。",
	"spiral": "多轮连续旋转发射方向，形成螺旋；可调每轮转角与发射间隔。",
	"aim": "朝玩家位置发射，可调整瞄准方式、数量与连发节奏。",
	"cross": "从同一位置向多个方向发射激光，可调整方向与范围。",
	"enemy": "普通卷轴敌人的起点模板；攻击、移动与离场由敌人自身设置负责。",
	"boss": "按顺序执行动作的 Boss；进入行为流程后配置攻击与移动。",
	"conditional_boss": "通过条件分支根据玩家距离选择动作，适合查看分支用法。",
	"animated_boss": "用同一个动作时钟组织动画、前摇、攻击和后摇。",
	"shrinking_trail_boss": "行为动作让敌人绕玩家缩圈，同时释放尾迹招式。",
	"empty_level": "从空白阶段开始，在时间轴上安排出场与结束条件。",
	"level": "带敌人巡航出场的关卡起点，可继续调整阶段和编队事件。",
	"three_section": "包含巡航、障碍与 Boss 阶段，适合查看完整关卡推进。",
	"enemy_wave": "安排敌人数量、排列和生成间隔；敌人行为仍复用敌人定义。",
	"obstacle_wave": "安排障碍的数量、排列和生成间隔，再拖入关卡时间轴。",
	"obstacle": "随卷轴进入战斗的岩石障碍，可调整外观、碰撞和离场规则。",
}

static func build(host, parent: Node) -> void:
	host.library_panel = Style.surface(parent)
	host.library_panel.get_parent().size_flags_horizontal = Control.SIZE_FILL
	Workspaces.build_library(host, host.library_panel)
	# 引用返回入口靠近资源列表，不再为整张画布额外占一行。
	host.context_row.reparent(host.library_panel)
	host.subtitle.visible = false
	host.library_title = F.note(host.library_panel, "")
	host.library_title.mouse_filter = Control.MOUSE_FILTER_PASS
	var types = HFlowContainer.new()
	host.library_panel.add_child(types)
	host.set_meta("material_types", types)
	for pair in [["全部", "all"], ["子弹", "moving"], ["激光", "laser"], ["拖尾", "trail"], ["区域", "area"]]:
		var filter = F.button(types, pair[0], func():
			host.material_filter = pair[1]
			refresh(host), "navigation")
		filter.toggle_mode = true
		filter.set_meta("material_form", pair[1])
		filter.tooltip_text = "筛选当前素材库中的" + pair[0] + "类型；不修改素材或招式引用。"
	host.library_search = LineEdit.new() # Godot 内置控件：只使用 text_changed 过滤列表。
	host.library_search.placeholder_text = "搜索名称…"
	host.library_search.clear_button_enabled = true
	F.help(host.library_search, "只按名称筛选当前分类的列表，不删除资源或改变引用；清空搜索可重新看到全部。")
	host.library_search.text_changed.connect(func(_text): refresh(host))
	host.library_panel.add_child(host.library_search)
	host.asset_list = ItemList.new()
	host.asset_list.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host.asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	F.help(host.asset_list, "单击选择资源，中央预览、右侧属性同步切换。这里是资源库；关卡出场请从下方“出场素材”拖入时间轴。")
	host.asset_list.item_selected.connect(func(index): host.select_resource(host.asset_list.get_item_metadata(index)))
	host.library_panel.add_child(host.asset_list)
	host.library_empty = F.label(host.library_panel, "")
	host.palette_panel = VBoxContainer.new()
	host.library_panel.add_child(host.palette_panel)
	F.label(host.palette_panel, "出场素材")
	F.note(host.palette_panel, "拖入时间轴，双击编辑")
	var palette_types = HFlowContainer.new(); host.palette_panel.add_child(palette_types)
	for entry in [["编队库", "waves"], ["障碍库", "obstacles"]]:
		F.help(F.button(palette_types, entry[0], func(): host.edit_reference(entry[1], host.session.project.get(entry[1])[0].id) if not host.session.project.get(entry[1]).is_empty() else host.switch_collection(entry[1]), "link"), "进入%s编辑可复用定义；随后可返回关卡，并从出场素材拖入时间轴。" % entry[0])
	host.level_palette = Palette.new()
	host.level_palette.host = host
	F.help(host.level_palette, "拖到时间轴安排所选阶段的出场时间；拖到战斗画面设置该阶段的出生位置。双击素材可进入它的定义编辑。")
	host.palette_panel.add_child(host.level_palette)
	host.create_button = MenuButton.new(); host.create_button.text = "＋ 从模板新建"
	Style.button(host.create_button)
	host.create_button.get_popup().id_pressed.connect(func(index):
		# 创建后清空筛选，避免新资源被旧搜索词藏起来。
		host.library_search.set_text("")
		if host.collection == "bullets": host.material_filter = "all"
		host.Commands.add(host, TEMPLATES[host.collection][index][1]))
	host.create_button.tooltip_text = "新建一份可独立修改的模板；FlyTiger 模板会一起复制它需要的子弹与招式。"
	host.library_panel.add_child(host.create_button)
	var operations = HBoxContainer.new(); host.library_panel.add_child(operations)
	host.copy_button = F.button(operations, "复制", func(): host.Commands.duplicate(host))
	host.delete_button = F.button(operations, "删除", func(): host.Commands.remove(host), "danger")
	host.delete_button.tooltip_text = "被其他资源引用时无法删除；删除后可以撤销。"
	host.library_help = F.note(host.library_panel, "")

static func refresh(host) -> void:
	var query = host.library_search.text.strip_edges().to_lower()
	var entries = host.session.project.get(host.collection)
	var types = host.get_meta("material_types")
	types.visible = host.collection == "bullets"
	for filter in types.get_children(): filter.set_pressed_no_signal(filter.get_meta("material_form") == host.material_filter)
	host.asset_list.clear()
	for item in entries:
		if item == null: continue
		if host.collection == "bullets" and host.material_filter != "all" and item.form != host.material_filter: continue
		if not query.is_empty() and not query in item.title.to_lower(): continue
		host.asset_list.add_item(item.title)
		var index = host.asset_list.item_count - 1
		host.asset_list.set_item_metadata(index, item.id)
		host.asset_list.set_item_tooltip(index, _resource_hint(host.collection, item))
		if item.id == host.selected_id: host.asset_list.select(index)
	var labels = {"bullets": "子弹素材", "barrages": "招式库", "bosses": "敌人 / Boss", "behaviors": "行为子流程", "levels": "关卡库", "waves": "编队", "obstacles": "障碍"}
	host.library_title.text = "%s · %d" % [labels[host.collection], entries.size()]
	host.library_title.tooltip_text = GUIDES[host.collection]
	host.library_help.text = GUIDES[host.collection]
	# 关卡拖放说明已经紧挨素材列表显示，不在底部重复占用高度。
	host.library_help.visible = false
	host.library_empty.visible = host.asset_list.item_count == 0
	host.library_empty.text = "当前类型或名称没有匹配素材。" if not entries.is_empty() else "还没有资源，从下面选择模板开始。"
	for button in [host.copy_button, host.delete_button]: button.disabled = host.current() == null
	var removal_issue = host.Commands.removal_issue(host.session.project, host.collection, host.selected_id) if host.current() != null else "先选择要删除的资源。"
	host.delete_button.disabled = host.current() == null or not removal_issue.is_empty()
	host.delete_button.tooltip_text = removal_issue if not removal_issue.is_empty() else "删除当前资源；可以撤销。"
	host.copy_button.tooltip_text = "复制当前资源的配置，创建新条目；\n它引用的子弹、招式等素材继续复用。\n复制操作可以撤销。" if host.current() != null else "先选择要复制的资源。"
	Workspaces.refresh(host)
	host.palette_panel.visible = host.collection == "levels"
	if host.palette_panel.visible: host.level_palette.refresh()
	var popup = host.create_button.get_popup(); popup.clear()
	# PopupMenu.clear 只删除菜单项；子菜单节点也要移出，避免每次刷新累积节点。
	for child in popup.get_children():
		popup.remove_child(child); child.queue_free()
	for pair in TEMPLATES[host.collection]:
		popup.add_item(pair[0])
		popup.set_item_tooltip(popup.item_count - 1, TEMPLATE_HINTS.get(pair[1], "创建这个起点模板。") + "\n添加到当前资源库并选中编辑，不替换已有条目；创建可以撤销。")
	if host.collection in ["barrages", "bosses"]:
		_flytiger_menu(host, popup)
		_flytiger_boss_menu(host, popup)

static func _resource_hint(collection: String, item: Resource) -> String:
	var result = item.title + "\n" + GUIDES[collection]
	return result + "\n单击选择，在中央预览和右侧编辑。"

static func flytiger_source() -> STGProject:
	if _flytiger_source == null: _flytiger_source = FlyTiger.new().build()
	return _flytiger_source

static func _flytiger_menu(host, popup: PopupMenu) -> void:
	var source = flytiger_source()
	popup.add_separator()
	_template_menu(host, popup, source, source.get(host.collection), "FlyTiger 小怪模板", "FlyTigerTemplates", func(item):
		return item.title.get_slice(" · ", 0) if host.collection == "barrages" else _enemy_group(item.id))

static func _enemy_group(id: String) -> String:
	if "dragon" in id: return "龙系与分裂召唤体"
	if "flowerball" in id.to_lower(): return "Boss 机关"
	for kind in ["javelinSlave", "ramFighter", "shieldSlave", "puppet", "bombPrisoner", "axeMinion", "archer", "cannoneer"]:
		if kind.to_lower() in id.to_lower(): return "地面小怪"
	for kind in ["spikebird", "eyefly", "stonebeetle", "floatflower", "stormfish", "twinsnake", "owl"]:
		if kind in id: return "进阶飞行小怪"
	return "常规飞行小怪"

static func flytiger_boss_source() -> STGProject:
	if _flytiger_boss_source == null: _flytiger_boss_source = FlyTigerBosses.new().build()
	return _flytiger_boss_source

static func _flytiger_boss_menu(host, popup: PopupMenu) -> void:
	var source = flytiger_boss_source()
	var entries = source.get(host.collection).filter(func(item):
		return item.id.begins_with("ft_boss_") and (host.collection == "bosses" or item.id.length() == "ft_boss_skill_001".length()))
	_template_menu(host, popup, source, entries, "FlyTiger Boss 模板", "FlyTigerBossTemplates", func(item):
		return item.title.get_slice(" · ", 0) if host.collection == "barrages" else "全部 Boss（%d）" % entries.size())

## 两个模板库只提供来源与分组规则；菜单、说明、依赖导入统一实现。
static func _template_menu(host, popup: PopupMenu, source: STGProject, entries: Array, title: String, node_name: String, group_for: Callable) -> void:
	var groups = {}
	for item in entries:
		var group: String = group_for.call(item)
		if not groups.has(group): groups[group] = []
		groups[group].append(item)
	var library = PopupMenu.new(); library.name = node_name; popup.add_child(library)
	popup.add_submenu_item("%s（%d）" % [title, entries.size()], library.name)
	popup.set_item_tooltip(popup.item_count - 1, "浏览%s；选择具体模板后，连同所需子弹与招式复制到当前资源库。" % title)
	for group in groups:
		var menu = PopupMenu.new(); menu.name = "Group%d" % library.get_child_count(); library.add_child(menu)
		library.add_submenu_item(group, menu.name)
		library.set_item_tooltip(library.item_count - 1, "展开这组模板；选择具体条目才会新建，不会切换当前资源库。")
		for item in groups[group]:
			menu.add_item(item.title)
			menu.set_item_metadata(menu.item_count - 1, item.id)
			menu.set_item_tooltip(menu.item_count - 1, item.title + "\n" + item.description + "\n复制此模板与所需定义到当前库，创建后可独立调整；导入可以撤销。")
		menu.id_pressed.connect(func(index):
			host.library_search.set_text("")
			host.Commands.add_template(host, source, menu.get_item_metadata(menu.get_item_index(index))))

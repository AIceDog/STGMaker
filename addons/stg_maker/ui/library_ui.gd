@tool
extends RefCounted
## 资源列表接口 build/refresh：搜索仅过滤显示，不修改项目和当前资源。
const Palette = preload("res://addons/stg_maker/ui/level_palette.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
const TEMPLATES = {
    "behaviors": [["空白行为子流程", "behavior"]],
    "bullets": [["子弹", "moving"], ["激光", "laser"], ["拖尾", "trail"], ["区域", "area"]],
    "barrages": [],
    "bosses": [["空白敌人 / Boss", "boss"]],
    "levels": [["空白关卡", "empty_level"]],
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
    "laser": "激光素材，用独立长度与宽度定义攻击范围。",
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

static func bind(host) -> void:
    var layout = host.Layout
    host.set_meta("material_types", layout.node(host, "material_types"))
    for form in ["all", "moving", "laser", "trail", "area"]:
        layout.press(host, "filter_" + form, func(): host.material_filter = form; refresh(host))
    host.library_search.text_changed.connect(func(_text): refresh(host))
    host.asset_list.item_selected.connect(func(index): host.select_resource(host.asset_list.get_item_metadata(index)))
    for entry in [["palette_waves_button", "waves"], ["palette_obstacles_button", "obstacles"]]:
        layout.press(host, entry[0], func(): host.edit_reference(entry[1], host.session.project.get(entry[1])[0].id) if not host.session.project.get(entry[1]).is_empty() else host.switch_collection(entry[1]))
    host.level_palette = layout.mount(host, "level_palette", Palette.new())
    host.create_button.get_popup().id_pressed.connect(func(index):
        host.library_search.set_text("")
        if host.collection == "bullets": host.material_filter = "all"
        if index == 10000: host.open_attack_presets()
        elif index >= 10001:
            var preset_id = str(host.create_button.get_popup().get_item_metadata(host.create_button.get_popup().get_item_index(index)))
            host.add_program_attack(preset_id)
        else: host.Commands.add(host, TEMPLATES[host.collection][index][1]))
    layout.press(host, "copy_button", func(): host.Commands.duplicate(host))
    layout.press(host, "delete_button", func(): host.Commands.remove(host))

static func refresh(host) -> void:
    var query = host.library_search.text.strip_edges().to_lower()
    var entries = host.session.project.get(host.collection)
    var preset_key = host.session.project.attack_presets.map(func(p): return [p.id,p.title,p.category])
    var signature: Array = [host.collection, query, host.material_filter, preset_key if host.collection=="barrages" else []]
    for item in entries:
        signature.append([item.id, item.title, item.form if item is STGBulletDefinition else ""] if item != null else [])
    if host.get_meta("library_signature", []) == signature:
        for index in host.asset_list.item_count:
            if host.asset_list.get_item_metadata(index) == host.selected_id: host.asset_list.select(index)
        _refresh_actions(host)
        Workspaces.refresh(host)
        return
    host.set_meta("library_signature", signature)
    host.set_meta("library_rebuild_count", int(host.get_meta("library_rebuild_count", 0)) + 1)
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
    _refresh_actions(host)
    Workspaces.refresh(host)
    host.palette_panel.visible = host.collection == "levels"
    if host.palette_panel.visible: host.level_palette.refresh()
    var menu_key = [host.collection, preset_key]
    if host.get_meta("template_collection", []) == menu_key: return
    host.set_meta("template_collection", menu_key)
    var popup = host.create_button.get_popup(); popup.clear()
    # PopupMenu.clear 只删除菜单项；子菜单节点也要移出，避免每次刷新累积节点。
    for child in popup.get_children():
        popup.remove_child(child); child.queue_free()
    for pair in TEMPLATES[host.collection]:
        popup.add_item(pair[0])
        popup.set_item_tooltip(popup.item_count - 1, TEMPLATE_HINTS.get(pair[1], "创建这个起点模板。") + "\n添加到当前资源库并选中编辑，不替换已有条目；创建可以撤销。")
    if host.collection == "barrages":
        popup.add_separator()
        popup.add_item("制作 / 管理程序预设…",10000)
        var available=[]
        for program in preload("res://addons/stg_maker/authoring/attack_presets.gd").definitions():available.append(preload("res://addons/stg_maker/authoring/attack_presets.gd").preset(program))
        available.append_array(host.session.project.attack_presets)
        for index in available.size():
            var preset=available[index]
            popup.add_item("预设 · "+preset.title,10001+index)
            popup.set_item_metadata(popup.item_count-1,preset.id)


static func _resource_hint(collection: String, item: Resource) -> String:
    var result = item.title + "\n" + GUIDES[collection]
    return result + "\n单击选择，在中央预览和右侧编辑。"


static func _refresh_actions(host) -> void:
    var selection = [host.collection, host.selected_id]
    var detail: Dictionary = host.session.last_change
    if host.get_meta("library_action_selection", []) == selection and not detail.get("structure", true) and not str(detail.get("field", "")).ends_with("_id"): return
    host.set_meta("library_action_selection", selection)
    for button in [host.copy_button, host.delete_button]: button.disabled = host.current() == null
    var removal_issue = host.Commands.removal_issue(host.session.project, host.collection, host.selected_id) if host.current() != null else "先选择要删除的资源。"
    host.delete_button.disabled = host.current() == null or not removal_issue.is_empty()
    host.delete_button.tooltip_text = removal_issue if not removal_issue.is_empty() else "删除当前资源；可以撤销。"
    host.copy_button.tooltip_text = "复制当前资源的配置，创建新条目；\n它引用的子弹、招式等素材继续复用。\n复制操作可以撤销。" if host.current() != null else "先选择要复制的资源。"

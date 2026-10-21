@tool
extends RefCounted
## 使用位置和校验问题共用稳定路径导航；不根据中文报错文本猜测所属对象。
const Locations = preload("res://addons/stg_maker/authoring/resource_locations.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Sections = preload("res://addons/stg_maker/ui/form_section.gd")

static func show_usages(host, collection: String = "", id: String = "") -> void:
    if collection.is_empty(): collection = host.collection
    if id.is_empty(): id = host.selected_id
    var target = host.session.project.find(collection, id)
    if target == null: return
    var entries = Locations.usages(host.session.project, collection, id)
    var panel = _panel(host, "使用位置 · " + target.title)
    F.note(panel.body, "%d 个直接使用位置；点击定位可查看调用它的招式、敌人或关卡。" % entries.size())
    if entries.is_empty(): F.note(panel.body, "当前资源库中没有其他位置直接使用这个素材。")
    for entry in entries:
        _row(host, panel, entry, Locations.caption(host.session.project, entry))
    panel.dialog.popup_centered(Vector2i(720, 520))

static func show_issues(host) -> void:
    var entries = Locations.diagnostics(host.session.project)
    var panel = _panel(host, "配置检查 · 点击问题定位")
    F.note(panel.body, "草稿可以保留未完成内容；试玩和导出前需要修复相关问题。")
    if entries.is_empty():
        F.note(panel.body, "当前资源库的配置检查已通过。")
        if not host.canvas.world.issue.is_empty(): F.note(panel.body, host.canvas.world.issue)
    for entry in entries:
        _row(host, panel, entry, Locations.caption(host.session.project, entry) + "\n" + entry.message)
    panel.dialog.popup_centered(Vector2i(760, 560))

static func _panel(host, title: String) -> Dictionary:
    var dialog = AcceptDialog.new()
    dialog.title = title
    dialog.dialog_hide_on_ok = true
    dialog.min_size = Vector2i(520, 300)
    host.add_child(dialog)
    dialog.confirmed.connect(dialog.queue_free)
    dialog.canceled.connect(dialog.queue_free)
    var scroll = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(680, 380)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    dialog.add_child(scroll)
    var body = VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 12)
    scroll.add_child(body)
    return {"dialog": dialog, "body": body}

static func _row(host, panel: Dictionary, location: Dictionary, text: String) -> void:
    var row = HBoxContainer.new()
    panel.body.add_child(row)
    var caption = F.label(row, text)
    caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var button = F.button(row, "定位 →", func():
        panel.dialog.hide()
        panel.dialog.queue_free()
        navigate(host, location))
    button.disabled = host.session.project.find(location.get("collection", ""), location.get("id", "")) == null
    F.help(button, "选择对应资源和内部步骤，并展开相关属性；不会修改配置。" if not button.disabled else "该问题属于项目整体或已缺失的资源，无法跳转。")

static func navigate(host, location: Dictionary) -> bool:
    var collection: String = location.get("collection", "")
    var id: String = location.get("id", "")
    if host.session.project.find(collection, id) == null: return false
    if host.collection != collection or host.selected_id != id:
        host.edit_reference(collection, id)
    var scope: Array = location.get("scope", [])
    var tab = 0
    if collection == "barrages":
        tab=0
    elif collection == "bullets":
        if location.get("field", "") in ["spawn_particles", "run_particles", "hit_particles"]: tab = 1
    elif collection == "behaviors":
        _locate_flow(host, scope, [])
    elif collection == "bosses":
        tab = 2
        if scope.size() >= 2 and scope[0] == "phases":
            host.phase_index = scope[1]
            if scope.size() >= 5 and scope[2] == "behavior_flow" and scope[3] == "nodes":
                _locate_flow(host, scope, ["phases", host.phase_index, "behavior_flow"])
                tab = 0
        elif not scope.is_empty() and scope[0] == "entity_settings": tab = 3
    elif collection == "levels":
        tab = 2
        if scope.size() >= 2 and scope[0] == "segments":
            host.segment_index = scope[1]
            tab = 1
            if scope.size() >= 4 and scope[2] == "events":
                var events = host.current().segments[host.segment_index].events
                if scope[3] < events.size(): host.event_id = events[scope[3]].id
                tab = 0
    host.inspector_tab = tab
    host.refresh(true)
    _reveal.call_deferred(host, scope, location.get("field", ""))
    return true

static func _locate_flow(host, scope: Array, base: Array) -> void:
    var paths = preload("res://addons/stg_maker/authoring/config_path.gd")
    for index in range(scope.size() - 1, base.size() - 1, -1):
        if not scope[index] is String or scope[index] != "nodes" or index + 1 >= scope.size(): continue
        var node = paths.resolve(host.current(), scope.slice(0, index + 2))
        if node is STGFlowNode:
            host.flow_path = scope.slice(base.size(), index)
            host.flow_node_id = node.id
        return

static func _reveal(host, scope: Array, field: String) -> void:
    if not is_instance_valid(host): return
    var target = _find_control(host.inspector, scope, field)
    if target == null:
        # 资源级错误也可能位于默认收起区，展开当前页方便直接修复。
        set_expanded(host.inspector, true)
        return
    var node = target.get_parent()
    while node != null and node != host.inspector:
        if node.get_script() == Sections and node.collapsible: node.heading.button_pressed = true
        node = node.get_parent()
    host.inspector_scroll.ensure_control_visible.call_deferred(target)
    if target.focus_mode != Control.FOCUS_NONE: target.grab_focus()

static func _find_control(node: Node, scope: Array, field: String) -> Control:
    if node.has_meta("config_scope") and node.get_meta("config_scope") == scope:
        if field.is_empty() or node.get_meta("config_field", "") == field: return node
    for child in node.get_children():
        var result = _find_control(child, scope, field)
        if result != null: return result
    return null

static func set_expanded(node: Node, opened: bool) -> void:
    if node.get_script() == Sections and node.collapsible: node.heading.button_pressed = opened
    for child in node.get_children(): set_expanded(child, opened)

@tool
extends RefCounted
## 配置表单接口：字段定位、资源引用和贴图选择；没有 Boss 或子弹运行规则。
const F = preload("res://addons/stg_maker/ui/fields.gd")
static func setter(host, scope: Array, key: String, rebuild: bool = false) -> Callable:
    return _set_value.bind(host, scope.duplicate(), key, rebuild)

static func _set_value(value, host, scope: Array, key: String, rebuild: bool) -> void:
    host.edit_path(scope, key, value, rebuild)

static func edit(host, scope: Array, change: Callable) -> void:
    # 多个相互关联的字段在同一快照中修改，减少重复定位代码和撤销步骤。
    host.inspector_dirty = true
    host.edit_configuration(scope, change)

static func number(host, box, scope: Array, resource, key: String, title: String, minimum: float = 0, maximum: float = 1000, step: float = -1) -> void:
    # 秒数保留百分之一秒，避免 0.12 秒的预警在控件里被显示成 0.1 秒。
    var increment = step if step > 0 else (0.01 if title.ends_with(" s") else 0.1)
    var control = F.number(box, title, resource.get(key), setter(host, scope, key), minimum, maximum, increment)
    locate(control, scope, key)

static func vector_inline(host, box, scope: Array, resource, key: String, title: String, minimum: float = -2000, maximum: float = 2000, step: float = 0.1) -> void:
    var controls = F.vector_inline(box, title, resource.get(key), func(axis, value):
        # 提交时读取当前快照，连续修改 X/Y 不覆盖另一个分量。
        var next: Vector2 = host.config_at(scope).get(key)
        next[axis] = value
        host.edit_path(scope, key, next), minimum, maximum, step)
    for axis in controls.size():
        locate(controls[axis], scope, key)
        controls[axis].set_meta("config_axis", axis)

static func vector(host, box, scope: Array, resource, key: String, title: String) -> void:
    var coordinates = F.group(box, title)
    for axis in [0, 1]:
        var control = F.number(coordinates, "X" if axis == 0 else "Y", resource.get(key)[axis], func(value):
            # 控件可能跨越一次撤销：提交时读取当前快照，保留另一个轴的最新值。
            var target = host.config_at(scope)
            var next: Vector2 = target.get(key)
            next[axis] = value
            host.edit_path(scope, key, next), -2000, 2000)
        locate(control, scope, key)
        control.set_meta("config_axis", axis)
        var description = F.Help.text(title)
        if not description.is_empty():
            description += "\n当前编辑 " + ("X" if axis == 0 else "Y") + " 分量。"
            F.help(control, description)

static func resource_reference(host, box, scope: Array, key: String, value: String, collection: String, title: String, filter: Callable = Callable()) -> void:
    var ids = []
    var names = []
    for item in host.session.project.get(collection):
        if filter.is_valid() and not filter.call(item):
            continue
        ids.append(item.id)
        names.append(item.title)
    var selector = F.select(box, title, value, ids, names, setter(host, scope, key, true))
    locate(selector, scope, key)
    var description = F.Help.text(title)
    F.help(selector, description + ("\n" if not description.is_empty() else "") + "选择要使用的素材；这里只更换引用。\n修改素材内容请使用对应的编辑按钮。")
    if not ids.is_empty() and not ids.has(value):
        selector.text = "引用已丢失，请重新选择"
        selector.add_theme_color_override("font_color", Color("ff9aab"))

static func reference_editor(host, box, collection: String, id: String, title: String) -> Button:
    # 打开引用是页面导航，不是本地复制；无效引用必须先从下拉框修复。
    var target = host.session.project.find(collection, id)
    var button = F.button(box, title, func(): host.edit_reference(collection, id), "link")
    button.disabled = target == null
    button.tooltip_text = "先选择有效的引用。" if target == null else "打开素材「%s」的编辑页。\n在该页修改会影响所有使用处。\n完成后可从左侧返回当前对象。" % target.title
    return button

static func optional_reference(host, box, key: String, value: String, collection: String, title: String) -> void:
    var entries: Array = host.session.project.get(collection)
    var enabled = not value.is_empty()
    var toggle = F.toggle(box, title, enabled, func(next):
        host.edit_path([], key, entries[0].id if next and not entries.is_empty() else "", true))
    toggle.disabled = entries.is_empty() and not enabled
    if toggle.disabled: toggle.tooltip_text = "先在弹幕招式库中创建招式，再启用这个事件。"
    if enabled:
        resource_reference(host, box, [], key, value, collection, "调用招式")
        reference_editor(host, box, collection, value, "编辑事件招式 →")

static func asset(host, box, key: String, title: String, resource, scope: Array = [], stacked: bool = false) -> void:
    var row = F.field(box, "asset", title, "asset_field")
    var caption = F.Form.part(row, "caption")
    if not F.authored(box): caption.text = title
    caption.visible = stacked
    var text = F.Form.part(row, "status")
    text.text = ("" if stacked else title + "：") + ("未设置" if resource == null else (resource.resource_name if resource is SpriteFrames and not resource.resource_name.is_empty() else resource.resource_path.get_file()))
    F.help(text, F.Help.text(title) + "\n当前" + title + "：" + ("未设置" if resource == null else resource.resource_path))
    var choose = F.Form.part(row, "choose")
    choose.pressed.connect(func(): host.request_asset(key, scope))
    choose.tooltip_text = "从当前 Godot 项目中选择" + title + "文件。\n选好后绑定到当前编辑对象，不会移动源文件。"
    locate(choose, scope, key)
    var clear = F.Form.part(row, "clear")
    clear.pressed.connect(func(): host.edit_path(scope, key, null, true))
    clear.disabled = resource == null
    clear.tooltip_text = "移除当前引用，不删除资源文件。" if resource != null else "尚未设置资源。"


static func list_buttons(host, box, path: Array, index: int, factory: Callable, title: String) -> void:
    var row = F.Form.lookup(box, "list", title) if F.authored(box) else F.Form.fragment("flow_row", box)
    var entries = host.config_at(path)
    var kind = _list_kind(path)
    var can_remove_last = path[-1] in ["events", "background_layers", "hit_effects"]
    for pair in [[title, "add"], ["复制", "copy"], ["删除", "remove"]]:
        var button = F.button(row, pair[0], func(): host.Commands.edit_list(host, path, pair[1], factory, index), "danger" if pair[1] == "remove" else "default")
        F.help(button, {"add": "添加一个%s，之后可单独调整参数。", "copy": "复制当前%s及其参数。\n原有项目保留，副本成为当前选择。", "remove": "删除当前%s，不删除它引用的素材。"}[pair[1]] % kind)
        if pair[1] == "copy": button.disabled = entries.is_empty()
        if pair[1] == "remove": button.disabled = entries.is_empty() or (entries.size() <= 1 and not can_remove_last)
        if button.disabled:
            button.tooltip_text = "当前列表为空。" if entries.is_empty() else "至少保留一项；不能删除最后一项。"
        elif pair[1] == "remove" and str(path[-1]) == "events":
            var owner_segment = host.config_at(path.slice(0, path.size() - 1))
            var rule = owner_segment.exit_rule
            button.disabled = rule.mode != "time" and rule.condition == "defeat_target" and rule.target_event_id == entries[index].id
            if button.disabled:
                button.tooltip_text = "这个出场是阶段的击败目标；先在当前阶段页更换目标。"
    var up = F.button(row, "上移", func(): host.Commands.edit_list(host, path, "move", factory, index, index - 1))
    up.disabled = index <= 0
    up.tooltip_text = "已经是第一项。" if up.disabled else "将当前%s在列表中前移一项。\n%s" % [kind, _order_help(path)]
    var down = F.button(row, "下移", func(): host.Commands.edit_list(host, path, "move", factory, index, index + 1))
    down.disabled = index >= entries.size() - 1
    down.tooltip_text = "已经是最后一项。" if down.disabled else "将当前%s在列表中后移一项。\n%s" % [kind, _order_help(path)]

static func _list_kind(path: Array) -> String:
    return {"phases": "血量阶段", "segments": "关卡阶段", "events": "出场事件", "background_layers": "背景层"}.get(str(path[-1]), "项目")

static func _order_help(path: Array) -> String:
    if path == ["segments"]: return "该阶段的出场事件会随阶段整体移动。"
    return "调整列表顺序，原有参数不变。"

static func locate(control: Control, scope: Array, field: String) -> void:
    control.set_meta("config_scope", scope.duplicate())
    control.set_meta("config_field", field)

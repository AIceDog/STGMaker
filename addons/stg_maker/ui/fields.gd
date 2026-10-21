@tool
extends RefCounted
## 通用表单接口：绑定保存的字段，或实例化共用组件；不承担子弹、Boss 或文档规则。
const Form = preload("res://addons/stg_maker/ui/form_scene.gd")
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
const Help = preload("res://addons/stg_maker/ui/control_help.gd")

static func help(control: Control, description: String) -> Control:
	# Label 默认忽略鼠标，不能显示原生提示；PASS 只允许悬停，仍不接收键盘焦点。
	if description.is_empty(): return control
	control.tooltip_text = description
	if control is Label: control.mouse_filter = Control.MOUSE_FILTER_PASS
	if control is SpinBox: control.get_line_edit().tooltip_text = description
	# 元数据生成的扩展参数也走这里，标题和真实输入区域显示同一份说明。
	if control is SpinBox or control is LineEdit or control is OptionButton:
		var parent = control.get_parent()
		if parent != null and control.get_index() > 0:
			var caption = parent.get_child(control.get_index() - 1)
			if caption is Label:
				caption.tooltip_text = description
				caption.mouse_filter = Control.MOUSE_FILTER_PASS
	return control

static func authored(parent: Node) -> bool:
	return Form.root_of(parent) != null

static func field(parent: Node, kind: String, title: String, component: String) -> Control:
	var control = Form.lookup(parent, kind, title) if authored(parent) else Form.fragment(component, parent)
	if kind in ["text", "number", "select", "vector", "asset", "color"]: help(Form.part(control, "caption"), Help.text(title))
	if control.get_meta("form_dynamic_caption", false): Form.part(control, "caption").text = title
	return control

static func label(parent: Node, text: String) -> Label:
	var control: Label
	if authored(parent): control = Form.lookup(parent, "label", text)
	else:
		control = Label.new(); control.text = text; parent.add_child(control)
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if parent is VBoxContainer: control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.set_meta("display_only", true)
	help(control, Help.text(text))
	return control

static func note(parent: Node, text: String, binding_id: String = "") -> Label:
	if authored(parent):
		var control: Label = Form.lookup(parent, "note", binding_id if not binding_id.is_empty() else text)
		if not binding_id.is_empty(): control.text = text
		return control
	var control = label(parent, text)
	control.theme_type_variation = "STGMutedLabel"
	return control

static func button(parent: Node, text: String, action: Callable, role: String = "default") -> Button:
	var control: Button
	if authored(parent): control = Form.lookup(parent, "button", text)
	else:
		control = Form.fragment("action_button", parent)
		control.text = text
		Style.button(control, role)
	control.pressed.connect(action)
	help(control, Help.text(text))
	return control

static func text(parent: Node, title: String, value: String, change: Callable) -> LineEdit:
	var row = field(parent, "text", title, "text_field")
	var control: LineEdit = Form.part(row, "input")
	if not authored(parent): Form.part(row, "caption").text = title
	control.text = value
	_bind_configuration(control, change)
	control.set_meta("help_title", title)
	control.set_meta("committed", value)
	var commit = func(next):
		if next != control.get_meta("committed"):
			control.set_meta("committed", next)
			change.call(next)
	control.text_submitted.connect(commit)
	control.focus_exited.connect(func(): commit.call(control.text))
	help(control, Help.text(title))
	return control

static func setup_number(control: SpinBox, title: String, value: float, change: Callable, minimum: float, maximum: float, step: float) -> void:
	control.set_meta("help_title", title)
	control.min_value = minf(minimum, value) if is_finite(value) else minimum
	control.max_value = maxf(maximum, value) if is_finite(value) else maximum
	control.step = step
	control.value = value
	control.value_changed.connect(change)
	_bind_configuration(control, change)
	help(control, Help.text(title))

static func number(parent: Node, title: String, value: float, change: Callable, minimum: float = 0, maximum: float = 1000, step: float = 0.1) -> SpinBox:
	var row = field(parent, "number", title, "number_field")
	if not authored(parent): Form.part(row, "caption").text = title
	var control: SpinBox = Form.part(row, "input")
	setup_number(control, title, value, change, minimum, maximum, step)
	help(row, Help.text(title))
	return control

static func select(parent: Node, title: String, value: String, keys: Array, names: Array, change: Callable, component: String = "select_field") -> OptionButton:
	var row = field(parent, "select", title, component)
	if not authored(parent): Form.part(row, "caption").text = title
	var control: OptionButton = Form.part(row, "input")
	control.set_meta("help_title", title)
	control.clear()
	for index in names.size():
		control.add_item(str(names[index]))
		control.get_popup().set_item_tooltip(index, Help.option(title, str(keys[index])))
	if keys.is_empty(): control.add_item("没有可选资源")
	control.disabled = keys.is_empty()
	control.select(keys.find(value))
	control.set_meta("config_keys", keys.duplicate())
	_bind_configuration(control, change)
	control.item_selected.connect(func(index):
		help(control, _selection_help(title, str(keys[index]), str(names[index])))
		change.call(keys[index]))
	help(control, _selection_help(title, value, str(names[keys.find(value)]) if keys.has(value) else ""))
	return control

static func _selection_help(title: String, key: String, selected: String) -> String:
	var description = Help.text(title)
	var option = Help.option(title, key)
	if not option.is_empty():
		description += ("\n" if not description.is_empty() else "") + "当前：" + selected + "\n" + option
	return description

static func toggle(parent: Node, title: String, value: bool, change: Callable) -> CheckButton:
	var control: CheckButton = field(parent, "toggle", title, "toggle_field")
	if not authored(parent): control.text = title
	control.set_meta("help_title", title)
	control.button_pressed = value
	control.toggled.connect(change)
	_bind_configuration(control, change)
	help(control, Help.text(title))
	return control

static func select_inline(parent: Node, title: String, value: String, keys: Array, names: Array, change: Callable) -> OptionButton:
	# 横排与否由组件场景决定，绑定接口与普通选择框相同。
	return select(parent, title, value, keys, names, change, "select_inline_field")

static func color(parent: Node, title: String, value: Color, change: Callable) -> ColorPickerButton:
	var row = field(parent, "color", title, "color_field")
	if not authored(parent): Form.part(row, "caption").text = title
	var control: ColorPickerButton = Form.part(row, "input")
	control.color = value
	control.color_changed.connect(change)
	_bind_configuration(control, change)
	return control

static func dynamic(parent: Node, key: String) -> Node:
	return Form.lookup(parent, "zone", key) if authored(parent) else parent

static func fold(parent: Node, title: String, open: bool = false, key: String = "") -> VBoxContainer:
	return _section(parent, title, true, open, key)

static func group(parent: Node, title: String, key: String = "") -> VBoxContainer:
	# 普通父分组也可收起，默认展开；展开状态只属于界面，不进入配置历史。
	return _section(parent, title, true, true, key)

static func section(parent: Node, title: String) -> VBoxContainer:
	# 基础属性始终可见；不读取或保存折叠状态。
	return _section(parent, title, false, true, "")

static func vector_inline(parent: Node, title: String, value: Vector2, change: Callable, minimum: float = -2000, maximum: float = 2000, step: float = 0.1) -> Array[SpinBox]:
	var row = field(parent, "vector", title, "vector_field")
	row.set_meta("vector_row", true)
	if not authored(parent): Form.part(row, "caption").text = title
	var controls: Array[SpinBox] = []
	for axis in 2:
		var control: SpinBox = Form.part(row, "x" if axis == 0 else "y")
		setup_number(control, title, value[axis], func(next): change.call(axis, next), minimum, maximum, step)
		help(control, Help.text(title) + "\n" + ("X" if axis == 0 else "Y") + " 分量。")
		controls.append(control)
	return controls

static func _section(parent: Node, title: String, collapsible: bool, opened: bool, key: String) -> VBoxContainer:
	# 展开状态沿父容器找到工作台的 UI 状态表；它不属于制作资源或撤销快照。
	var owner = parent
	while owner != null and not owner.has_meta("section_states"):
		owner = owner.get_parent()
	var path: String = key if not key.is_empty() else str(parent.get_meta("section_path", "")) + "/" + title
	var section = Form.lookup(parent, "section", title) if authored(parent) else Form.fragment("form_section_nested" if int(parent.get_meta("section_depth", -1)) >= 0 else "form_section", parent)
	if owner != null:
		section.states = owner.get_meta("section_states")
		section.state_key = str(owner.get_meta("section_context")) + "/" + path
		if collapsible:
			opened = section.states.get(section.state_key, opened)
	if not authored(parent): section.configure(title, int(parent.get_meta("section_depth", -1)) + 1, collapsible, opened)
	else:
		section.collapsible = collapsible
		section.expanded = opened
		if section.get_meta("form_dynamic_title", false): section.title = title
		section._update_heading()
	section.set_help(Help.text(title))
	section.content.set_meta("section_depth", section.depth)
	section.content.set_meta("section_path", path)
	if authored(parent): section.content.set_meta("form_scope", section.get_meta("form_scope"))
	return section.content

static func _bind_configuration(control: Control, change: Callable) -> void:
	var args = change.get_bound_arguments()
	if args.size() != 4 or not args[0] is Object or not args[0].has_method("edit_path"): return
	control.set_meta("config_scope", args[1])
	control.set_meta("config_field", args[2])

static func close_popups(node: Node) -> void:
	# OptionButton / ColorPickerButton 的窗口可能是内部节点，必须在脱离树前关闭。
	for child in node.get_children(true): close_popups(child)
	if node is Window and node.visible: node.hide()

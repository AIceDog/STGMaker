@tool
extends RefCounted
## 通用表单接口；只创建 Godot 控件并发出值，不知道子弹、Boss 或文档。
const FormSection = preload("res://addons/stg_maker/ui/form_section.gd")
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

static func label(parent: Node, text: String) -> Label:
	var control = Label.new()
	control.text = text
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.set_meta("display_only", true)
	if parent is VBoxContainer:
		control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(control)
	help(control, Help.text(text))
	return control

static func note(parent: Node, text: String) -> Label:
	var control = label(parent, text)
	control.add_theme_color_override("font_color", Color("a4b7ca"))
	return control

static func button(parent: Node, text: String, action: Callable, role: String = "default") -> Button:
	var control = Button.new()
	control.text = text
	control.pressed.connect(action)
	Style.button(control, role)
	parent.add_child(control)
	help(control, Help.text(text))
	return control

static func text(parent: Node, title: String, value: String, change: Callable) -> LineEdit:
	label(parent, title)
	var control = LineEdit.new()
	control.text = value
	control.set_meta("help_title", title)
	control.set_meta("committed", value)
	# 按 Enter 与失去焦点都提交；committed 防止同一次输入产生两个撤销步骤。
	var commit = func(next):
		if next != control.get_meta("committed"):
			control.set_meta("committed", next)
			change.call(next)
	control.text_submitted.connect(commit)
	control.focus_exited.connect(func(): commit.call(control.text))
	parent.add_child(control)
	help(control, Help.text(title))
	return control

static func number(parent: Node, title: String, value: float, change: Callable, minimum: float = 0, maximum: float = 1000, step: float = 0.1) -> SpinBox:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var caption = label(row, title)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 40
	caption.set_meta("numeric_caption", true)
	var control = SpinBox.new()
	control.set_meta("help_title", title)
	control.custom_minimum_size.x = 115
	control.min_value = minimum
	control.max_value = maximum
	# 草稿可能暂时超出合法范围，忠实显示原值，不能只夹显示值而悄悄掩盖问题。
	if is_finite(value):
		control.min_value = minf(minimum, value)
		control.max_value = maxf(maximum, value)
	control.step = step
	control.value = value
	control.value_changed.connect(change)
	row.add_child(control)
	help(row, Help.text(title))
	help(control, Help.text(title))
	return control

static func select(parent: Node, title: String, value: String, keys: Array, names: Array, change: Callable) -> OptionButton:
	# names 给策划看，keys 写入配置；Godot 控件的数字索引不作为游戏资源 ID。
	label(parent, title)
	var control = OptionButton.new()
	control.set_meta("help_title", title)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.fit_to_longest_item = false
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for index in names.size():
		control.add_item(str(names[index]))
		control.get_popup().set_item_tooltip(index, Help.option(title, str(keys[index])))
	if keys.is_empty():
		control.add_item("没有可选资源")
		control.disabled = true
	control.select(keys.find(value))
	control.item_selected.connect(func(index):
		help(control, _selection_help(title, str(keys[index]), str(names[index])))
		change.call(keys[index]))
	parent.add_child(control)
	help(control, _selection_help(title, value, str(names[keys.find(value)]) if keys.has(value) else ""))
	return control

static func _selection_help(title: String, key: String, selected: String) -> String:
	var description = Help.text(title)
	var option = Help.option(title, key)
	if not option.is_empty():
		description += ("\n" if not description.is_empty() else "") + "当前：" + selected + "\n" + option
	return description

static func toggle(parent: Node, title: String, value: bool, change: Callable) -> CheckButton:
	var control = CheckButton.new()
	control.set_meta("help_title", title)
	control.text = title
	control.clip_text = parent is VBoxContainer
	control.tooltip_text = title
	control.button_pressed = value
	control.toggled.connect(change)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(control)
	help(control, Help.text(title))
	return control

static func select_inline(parent: Node, title: String, value: String, keys: Array, names: Array, change: Callable) -> OptionButton:
	# 常用参数一行完成，保留原生下拉框的焦点、键盘和不可用状态。
	var row = HBoxContainer.new()
	parent.add_child(row)
	var selector = select(row, title, value, keys, names, change)
	row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.size_flags_horizontal = Control.SIZE_SHRINK_END
	selector.custom_minimum_size.x = 145
	return selector

static func fold(parent: Node, title: String, open: bool = false, key: String = "") -> VBoxContainer:
	return _section(parent, title, true, open, key)

static func group(parent: Node, title: String, key: String = "") -> VBoxContainer:
	# 普通父分组也可收起，默认展开；展开状态只属于界面，不进入配置历史。
	return _section(parent, title, true, true, key)

static func section(parent: Node, title: String) -> VBoxContainer:
	# 基础属性始终可见；不读取或保存折叠状态。
	return _section(parent, title, false, true, "")

static func vector_inline(parent: Node, title: String, value: Vector2, change: Callable, minimum: float = -2000, maximum: float = 2000, step: float = 0.1) -> Array[SpinBox]:
	# 空间不足时把完整标签换到上一行；XY 作为整体同行，禁止中文逐字换行。
	var row = HFlowContainer.new()
	row.set_meta("vector_row", true)
	parent.add_child(row)
	var caption = label(row, title)
	# 标签按字体自然宽度占位；固定 80px 在大字号下会把中文逐字挤成竖排。
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var axes = HBoxContainer.new()
	axes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(axes)
	var controls: Array[SpinBox] = []
	for axis in 2:
		label(axes, "X:" if axis == 0 else "Y:")
		var control = SpinBox.new()
		control.set_meta("inline_axis", true)
		control.set_meta("help_title", title)
		control.custom_minimum_size.x = 76
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.min_value = minf(minimum, value[axis]) if is_finite(value[axis]) else minimum
		control.max_value = maxf(maximum, value[axis]) if is_finite(value[axis]) else maximum
		control.step = step
		control.value = value[axis]
		control.value_changed.connect(func(next): change.call(axis, next))
		axes.add_child(control)
		help(control, Help.text(title) + "\n" + ("X" if axis == 0 else "Y") + " 分量。")
		controls.append(control)
	return controls

static func _section(parent: Node, title: String, collapsible: bool, opened: bool, key: String) -> VBoxContainer:
	# 展开状态沿父容器找到工作台的 UI 状态表；它不属于制作资源或撤销快照。
	var owner = parent
	while owner != null and not owner.has_meta("section_states"):
		owner = owner.get_parent()
	var path: String = key if not key.is_empty() else str(parent.get_meta("section_path", "")) + "/" + title
	var section = FormSection.new()
	if owner != null:
		section.states = owner.get_meta("section_states")
		section.state_key = str(owner.get_meta("section_context")) + "/" + path
		if collapsible:
			opened = section.states.get(section.state_key, opened)
	parent.add_child(section)
	section.configure(title, int(parent.get_meta("section_depth", -1)) + 1, collapsible, opened)
	section.set_help(Help.text(title))
	section.content.set_meta("section_path", path)
	return section.content

@tool
extends VBoxContainer
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
## 属性分组组件：标题属于父层，带边框的内容属于子层；仅保存显示状态。
## configure / apply_display 是自定义接口，PanelContainer / StyleBoxFlat 是 Godot 控件与样式。
var content: VBoxContainer
var heading: Control
var indent: MarginContainer
var panel: PanelContainer
var title: String = ""
var depth: int = 0
var collapsible: bool = false
var expanded: bool = true
var state_key: String = ""
var states: Dictionary = {}

func configure(label: String, level: int, can_fold: bool, opened: bool) -> void:
	title = label
	depth = level
	collapsible = can_fold
	expanded = opened
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if collapsible:
		var button = Button.new()
		button.toggle_mode = true
		button.button_pressed = expanded
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.tooltip_text = "点击展开 / 收起「" + title + "」；仅改变显示，不修改配置。"
		Style.button(button)
		button.toggled.connect(_toggle)
		heading = button
	else:
		var caption = Label.new()
		caption.text = title
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.tooltip_text = title
		heading = caption
	add_child(heading)
	indent = MarginContainer.new()
	add_child(indent)
	panel = PanelContainer.new()
	indent.add_child(panel)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.set_meta("section_depth", depth)
	panel.add_child(content)
	_update_heading()
	apply_display(get_theme_default_font_size() / 18.0)

func _toggle(value: bool) -> void:
	expanded = value
	states[state_key] = value
	_update_heading()

func set_help(description: String) -> void:
	if description.is_empty(): return
	heading.tooltip_text = description + ("\n点击标题可展开或收起；不会修改游戏内容。" if collapsible else "")
	if heading is Label: heading.mouse_filter = Control.MOUSE_FILTER_PASS

func _update_heading() -> void:
	indent.visible = expanded
	if collapsible: heading.text = ("▾  " if expanded else "▸  ") + title

func apply_display(unit: float) -> void:
	# 深层分组使用较小缩进，保留右侧属性面板的可用宽度。
	var padding = 12 if depth == 0 else 9
	indent.add_theme_constant_override("margin_left", roundi((12 if depth == 0 else 7) * unit))
	add_theme_constant_override("separation", roundi(5 * unit))
	content.add_theme_constant_override("separation", roundi(8 * unit))
	var body_style = _style(Color("1c2b3b") if depth == 0 else Color("223548"), Color("506b83"), padding, unit)
	body_style.border_width_left = roundi(3 * unit)
	body_style.border_color = Color("557f99") if depth == 0 else Color("7598ac")
	panel.add_theme_stylebox_override("panel", body_style)
	heading.add_theme_color_override("font_color", Color("e4f2fc"))
	if collapsible:
		heading.custom_minimum_size.y = roundi(34 * unit)
		heading.add_theme_stylebox_override("normal", _style(Color("263b50"), Color("48667f"), 9, unit))
		heading.add_theme_stylebox_override("hover", _style(Color("314d64"), Color("7ab4c7"), 9, unit))
		heading.add_theme_stylebox_override("pressed", _style(Color("29465a"), Color("7ab4c7"), 9, unit))
	else:
		heading.add_theme_font_size_override("font_size", roundi(19 * unit))

func _style(background: Color, border: Color, padding: int, unit: float) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(maxi(1, roundi(unit)))
	style.set_corner_radius_all(roundi(5 * unit))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_content_margin(side, padding * unit)
	return style

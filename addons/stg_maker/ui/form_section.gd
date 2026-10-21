@tool
extends VBoxContainer
## 属性分组组件：标题属于父层，带边框的内容属于子层；仅保存显示状态。
## configure / apply_display 是自定义接口，PanelContainer / StyleBoxFlat 是 Godot 控件与样式。
var content: VBoxContainer
var heading: Control
var indent: MarginContainer
var panel: PanelContainer
@export var title: String = "属性分组":
	set(value):
		title = value
		_update_heading()
@export var depth: int = 0
@export var collapsible: bool = false:
	set(value):
		collapsible = value
		_update_heading()
@export var expanded: bool = true:
	set(value):
		expanded = value
		_update_heading()
var state_key: String = ""
var states: Dictionary = {}

func _ready() -> void:
	heading = get_node("Heading") if collapsible else get_node("Caption")
	indent = get_node("Indent")
	panel = get_node("Indent/Panel")
	content = get_node("Indent/Panel/Content")
	get_node("Heading").toggled.connect(_toggle)
	_update_heading()
	apply_display(1.0)

func configure(label: String, level: int, can_fold: bool, opened: bool) -> void:
	title = label
	depth = level
	collapsible = can_fold
	expanded = opened
	content.set_meta("section_depth", depth)
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
	if not is_instance_valid(indent): return
	get_node("Heading").visible = collapsible
	get_node("Caption").visible = not collapsible
	heading = get_node("Heading") if collapsible else get_node("Caption")
	indent.visible = expanded
	heading.text = ("▾  " if expanded else "▸  ") + title if collapsible else title
	if heading is BaseButton: heading.set_pressed_no_signal(expanded)

func apply_display(_unit: float) -> void:
	# 固定分组的间距、缩进与样式均由场景和 Theme 提供。
	panel.theme_type_variation = "STGFormPanel" if depth == 0 else "STGNestedFormPanel"

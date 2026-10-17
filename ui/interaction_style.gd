@tool
extends RefCounted
## 交互语义集中在 UI 层：按钮有边框、悬停与焦点，信息使用平面文字。
## Theme 的类型变体随字号一起生成；控件角色不写入策划资源。
const TEXT = Color("d7e3ee")
const MUTED = Color("99afc4")
const ACCENT = Color("66dec2")
const AMBER = Color("ffc785")
const ROLES = {
	"default": "STGActionButton", "primary": "STGPrimaryButton",
	"navigation": "STGNavigationButton", "link": "STGLinkButton",
	"danger": "STGDangerButton",
}

static func box(background: Color, border: Color, unit: float, horizontal: float = 10, vertical: float = 6) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(maxi(1, roundi(unit)))
	style.set_corner_radius_all(roundi(6 * unit))
	style.content_margin_left = horizontal * unit
	style.content_margin_right = horizontal * unit
	style.content_margin_top = vertical * unit
	style.content_margin_bottom = vertical * unit
	return style

static func button(control: BaseButton, role: String = "default") -> void:
	control.set_meta("interaction_role", role)
	control.theme_type_variation = ROLES.get(role, ROLES.default)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.focus_mode = Control.FOCUS_ALL
	if control is MenuButton:
		control.flat = false
		control.icon = control.get_theme_icon("arrow", "OptionButton")
		control.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT

static func surface(parent: Node, kind: String = "workspace", expand: bool = true) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.set_meta("surface_kind", kind)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(body)
	return body

static func controls(parent: Node) -> HFlowContainer:
	var panel = PanelContainer.new()
	panel.set_meta("surface_kind", "controls")
	parent.add_child(panel)
	var row = HFlowContainer.new()
	panel.add_child(row)
	return row

static func populate(theme: Theme, unit: float) -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	_action(theme, "Button", unit, Color("26394d"), Color("486079"))
	for role in ROLES:
		var type: String = ROLES[role]
		theme.set_type_variation(type, "Button")
		match role:
			"primary": _action(theme, type, unit, Color("226759"), Color("57bfa5"))
			"link": _action(theme, type, unit, Color("1b3446"), Color("598fac"))
			"danger": _action(theme, type, unit, Color("3d2c36"), Color("805262"))
			_: _action(theme, type, unit, Color("26394d"), Color("486079"))
	_action(theme, "OptionButton", unit, Color("101f2e"), Color("3c556d"))
	theme.set_stylebox("normal", "LineEdit", box(Color("101f2e"), Color("3c556d"), unit))
	theme.set_stylebox("focus", "LineEdit", _focus(unit))
	theme.set_stylebox("read_only", "LineEdit", box(Color("182536"), Color("2d4054"), unit))
	for type in ["CheckButton", "CheckBox"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("687d91"))
		theme.set_stylebox("focus", type, _focus(unit))
	_tabs(theme, unit)
	_lists(theme, unit)
	theme.set_stylebox("panel", "PopupMenu", box(Color("1a293b"), Color("536c86"), unit))
	theme.set_stylebox("hover", "PopupMenu", box(Color("294c59"), Color("416b79"), unit))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", Color("687d91"))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", box(Color("22354a"), Color("6b879f"), unit))
	# 流程节点是可选中、可拖动的对象；橙色边框和属性面板的选中上下文对应。
	theme.set_stylebox("panel", "GraphNode", box(Color("223548"), Color("52718a"), unit, 12, 8))
	theme.set_stylebox("panel_selected", "GraphNode", box(Color("2c3d4b"), AMBER, unit, 12, 8))
	theme.set_stylebox("titlebar", "GraphNode", box(Color("2d485a"), Color("52718a"), unit, 10, 6))
	theme.set_stylebox("titlebar_selected", "GraphNode", box(Color("534738"), AMBER, unit, 10, 6))

static func _action(theme: Theme, type: String, unit: float, background: Color, border: Color) -> void:
	theme.set_stylebox("normal", type, box(background, border, unit))
	theme.set_stylebox("hover", type, box(background.lightened(0.14), border.lightened(0.3), unit))
	theme.set_stylebox("pressed", type, box(Color("244f53"), ACCENT, unit))
	theme.set_stylebox("hover_pressed", type, box(Color("2e6261"), Color("95f2da"), unit))
	theme.set_stylebox("disabled", type, box(Color("192737"), Color("2b3b4b"), unit))
	theme.set_stylebox("focus", type, _focus(unit))
	theme.set_color("font_color", type, Color("e6eff7"))
	theme.set_color("font_hover_color", type, Color.WHITE)
	theme.set_color("font_pressed_color", type, Color("c5fff1"))
	theme.set_color("font_hover_pressed_color", type, Color.WHITE)
	theme.set_color("font_disabled_color", type, Color("708498"))

static func _focus(unit: float) -> StyleBoxFlat:
	var style = box(Color.TRANSPARENT, Color("93edda"), unit)
	style.draw_center = false
	style.set_border_width_all(maxi(2, roundi(2 * unit)))
	return style

static func _tabs(theme: Theme, unit: float) -> void:
	var selected = box(Color("234c53"), Color("4d8d8b"), unit)
	selected.border_width_top = maxi(2, roundi(3 * unit))
	selected.border_color = ACCENT
	theme.set_stylebox("tab_selected", "TabBar", selected)
	theme.set_stylebox("tab_unselected", "TabBar", box(Color("202f41"), Color("3b5268"), unit))
	theme.set_stylebox("tab_hovered", "TabBar", box(Color("30495d"), Color("7693aa"), unit))
	theme.set_stylebox("tab_disabled", "TabBar", box(Color("192737"), Color("2b3b4b"), unit))
	theme.set_stylebox("tab_focus", "TabBar", _focus(unit))
	theme.set_color("font_selected_color", "TabBar", Color("c5fff1"))
	theme.set_color("font_unselected_color", "TabBar", TEXT)
	theme.set_color("font_disabled_color", "TabBar", Color("708498"))

static func _lists(theme: Theme, unit: float) -> void:
	theme.set_stylebox("panel", "ItemList", box(Color("101d2b"), Color("324a60"), unit, 6, 6))
	theme.set_stylebox("selected", "ItemList", box(Color("28554f"), ACCENT, unit, 6, 5))
	theme.set_stylebox("selected_focus", "ItemList", box(Color("28554f"), ACCENT, unit, 6, 5))
	theme.set_stylebox("hovered", "ItemList", box(Color("263e52"), Color("59859d"), unit, 6, 5))
	theme.set_stylebox("focus", "ItemList", _focus(unit))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", Color("cbfff1"))
	theme.set_color("guide_color", "ItemList", Color("263b4d"))

static func apply_controls(node: Node, unit: float) -> void:
	if node is PanelContainer and node.has_meta("surface_kind"):
		var kind: String = node.get_meta("surface_kind")
		var background = Color("172638") if kind == "header" else Color("121f2d")
		var padding = 8 if kind in ["controls", "header"] else 10
		node.add_theme_stylebox_override("panel", box(background, Color("2e465b"), unit, padding, padding))
	elif node is BaseButton and node.has_meta("interaction_role"):
		node.custom_minimum_size.y = roundi(34 * unit)
		node.mouse_default_cursor_shape = Control.CURSOR_ARROW if node.disabled else Control.CURSOR_POINTING_HAND
	elif node is OptionButton:
		node.custom_minimum_size.y = roundi(34 * unit)
		node.mouse_default_cursor_shape = Control.CURSOR_ARROW if node.disabled else Control.CURSOR_POINTING_HAND
	elif node is CheckButton or node is CheckBox:
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for child in node.get_children():
		apply_controls(child, unit)

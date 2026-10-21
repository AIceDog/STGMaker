@tool
extends RefCounted
## 交互语义集中在 UI 层：按钮有边框、悬停与焦点，信息使用平面文字。
## 样式保存在 studio_theme.tres；控件角色不写入策划资源。
const ROLES = {
	"default": "STGActionButton", "primary": "STGPrimaryButton",
	"navigation": "STGNavigationButton", "link": "STGLinkButton",
	"danger": "STGDangerButton",
}

static func button(control: BaseButton, role: String = "default") -> void:
	control.set_meta("interaction_role", role)
	control.theme_type_variation = ROLES.get(role, ROLES.default)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.focus_mode = Control.FOCUS_ALL
	if control is MenuButton:
		control.flat = false
		control.icon = control.get_theme_icon("arrow", "OptionButton")
		control.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT

static func apply_controls(node: Node, unit: float, host: Node) -> void:
	# 静态控件保留场景设计。动态内容继承相同 Theme，不另生成一套配色。
	if node.owner != host and not node.get_meta("authored_control", false):
		if node is PanelContainer and node.has_meta("surface_kind"):
			node.theme_type_variation = "STG" + str(node.get_meta("surface_kind")).capitalize() + "Panel"
		elif node is BaseButton and (node.has_meta("interaction_role") or node is OptionButton):
			node.custom_minimum_size.y = node.get_theme_constant("button_height", "STGMetrics")
	if node is BaseButton:
		node.mouse_default_cursor_shape = Control.CURSOR_ARROW if node.disabled else Control.CURSOR_POINTING_HAND
	for child in node.get_children(): apply_controls(child, unit, host)

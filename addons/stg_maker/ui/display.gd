@tool
extends RefCounted
## 显示接口 apply(host)：重新布局、设置实际字体尺寸；不缩放整个 UI 或低分辨率视口截图。
const REFERENCE_SIZE = Vector2(1440, 900)
const FormSection = preload("res://addons/stg_maker/ui/form_section.gd")
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
const SCALE_OPTIONS = [0, 100, 125, 150, 175, 200]
const FONT_OPTIONS = [0, 16, 18, 20, 24]
const FONT_TYPES = ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "TabBar", "TooltipLabel"]

static func editor_scale() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0 # Godot 内置：编辑器 DPI/缩放

static func factor(host) -> float:
	if host.ui_scale_percent > 0: return host.ui_scale_percent / 100.0
	var reference = REFERENCE_SIZE * editor_scale()
	return clampf(minf(host.size.x / reference.x, host.size.y / reference.y), 1, 2)

static func apply(host) -> void:
	var density = editor_scale()
	var base_font = 18.0 * density
	if Engine.is_editor_hint(): base_font = maxf(base_font, EditorInterface.get_editor_theme().get_font_size("font_size", "Label"))
	if host.font_size > 0: base_font = host.font_size * density
	var pixels = maxi(14, roundi(base_font * factor(host)))
	var unit = pixels / 18.0
	if host.theme == null or host.theme.default_font_size != pixels:
		var theme = Theme.new() # Godot 内置 Theme：字体按实际像素重绘，避免父主题覆盖默认字号。
		theme.default_font_size = pixels
		for type in FONT_TYPES: theme.set_font_size("font_size", type, pixels)
		theme.set_font_size("normal_font_size", "RichTextLabel", pixels)
		theme.set_font_size("bold_font_size", "RichTextLabel", pixels)
		theme.set_constant("v_separation", "ItemList", roundi(6 * unit))
		theme.set_constant("separation", "HBoxContainer", roundi(6 * unit))
		theme.set_constant("separation", "VBoxContainer", roundi(9 * unit))
		Style.populate(theme, unit)
		host.theme = theme
	# PopupMenu / FileDialog 是独立 Window；显式设置主题，菜单字号也跟随界面。
	for child in host.get_children():
		if child is Window: child.theme = host.theme
	if not is_instance_valid(host.layout_margin): return
	for side in ["left", "top", "right", "bottom"]: host.layout_margin.add_theme_constant_override("margin_" + side, roundi(14 * unit))
	host.layout_outer.add_theme_constant_override("separation", roundi(10 * unit))
	host.brand.add_theme_font_size_override("font_size", roundi(22 * unit))
	host.back_button.custom_minimum_size.x = roundi(140 * unit)
	host.library_panel.custom_minimum_size.x = clampf(host.size.x * 0.145, 185 * unit, 280 * unit)
	host.inspector_scroll.custom_minimum_size.x = clampf(host.size.x * 0.255, 325 * unit, 460 * unit)
	var canvas_height = 220 if host.collection == "levels" and host.canvas.edit_mode != "none" else 260
	host.canvas.custom_minimum_size = Vector2(320, canvas_height) * unit
	host.flow_editor.custom_minimum_size = Vector2(320, 260) * unit
	host.flow_editor.apply_display(unit)
	host.curve_editor.custom_minimum_size.y = roundi(160 * unit)
	host.timeline_scroll.custom_minimum_size.y = roundi(230 * unit)
	host.level_palette.custom_minimum_size.y = roundi(180 * unit)
	host.asset_list.custom_minimum_size.y = roundi(90 * unit) if host.collection == "levels" else 0
	host.inspector.add_theme_constant_override("separation", roundi(9 * unit))
	host.asset_list.fixed_icon_size = Vector2i(Vector2.ONE * roundi(24 * unit))
	_apply_controls(host.inspector, unit)
	_apply_controls(host.toolbar, unit)
	Style.apply_controls(host, unit)
	host.canvas.world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if host.pixel_art else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	host.canvas.update_screen_transform() # 字号改变会影响屏幕上下提示的留白，同步刷新裁剪矩形和坐标变换。
	host.curve_editor.queue_redraw()
	host.display_menu.text = "界面"
	host.display_menu.tooltip_text = "当前界面大小：" + ("自适应" if host.ui_scale_percent == 0 else "%d%%" % host.ui_scale_percent) + "。调整布局、字号或预览采样；专注模式可暂时隐藏左右侧栏。只影响编辑界面。"
	_update_menu(host)

static func _apply_controls(node: Node, unit: float) -> void:
	if node is FormSection: node.apply_display(unit)
	elif node is Label and node.has_meta("numeric_caption"): node.custom_minimum_size.x = roundi(40 * unit)
	elif node is SpinBox: node.custom_minimum_size.x = roundi((76 if node.has_meta("inline_axis") else 115) * unit)
	elif (node is Button or node is LineEdit) and not node.has_meta("custom_control_height"): node.custom_minimum_size.y = roundi(30 * unit)
	for child in node.get_children(): _apply_controls(child, unit)

static func build_menu(host, parent: Node) -> void:
	host.display_menu = MenuButton.new()
	Style.button(host.display_menu)
	host.display_menu.tooltip_text = "调整界面大小、基础字号与预览贴图采样；不改变游戏数据。"
	parent.add_child(host.display_menu)
	var popup = host.display_menu.get_popup()
	var scales = PopupMenu.new(); scales.name = "Sizes"; popup.add_child(scales)
	for value in SCALE_OPTIONS:
		scales.add_radio_check_item("自动适配窗口" if value == 0 else "%d%%" % value, value)
		scales.set_item_tooltip(scales.item_count - 1, "根据窗口自动调整工作台尺寸；不改变游戏分辨率。" if value == 0 else "把工作台控件与文字按 %d%% 显示；小窗口可能出现滚动，不改变游戏画面尺寸。" % value)
	scales.id_pressed.connect(host.set_ui_scale)
	popup.add_submenu_item("整体大小", "Sizes")
	popup.set_item_tooltip(popup.item_count - 1, "调整编辑控件和文字的整体显示比例；不缩放游戏数据或设计坐标。")
	var fonts = PopupMenu.new(); fonts.name = "Fonts"; popup.add_child(fonts)
	for value in FONT_OPTIONS:
		fonts.add_radio_check_item("跟随 Godot（至少 18）" if value == 0 else "%d 号基础字" % value, value)
		fonts.set_item_tooltip(fonts.item_count - 1, "使用 Godot 编辑器的字号，并保证基础文字至少 18 号；仍受整体大小影响。" if value == 0 else "使用 %d 号基础文字，仍受整体大小影响；只改变编辑界面的可读性。" % value)
	fonts.id_pressed.connect(host.set_font_size)
	popup.add_submenu_item("基础字号", "Fonts")
	popup.set_item_tooltip(popup.item_count - 1, "选择工作台的基础文字大小；不会修改游戏中的字体或 UI。")
	var sampling = PopupMenu.new(); sampling.name = "Sampling"; popup.add_child(sampling)
	sampling.add_radio_check_item("普通贴图：平滑", 0)
	sampling.add_radio_check_item("像素风：最近邻", 1)
	sampling.set_item_tooltip(0, "预览中平滑缩放贴图，适合普通绘制素材；不修改原图或导入设置。")
	sampling.set_item_tooltip(1, "预览中保持像素边缘，适合像素画；不修改原图或导出游戏的资源设置。")
	sampling.id_pressed.connect(func(id): host.set_pixel_art(id == 1))
	popup.add_submenu_item("预览贴图", "Sampling")
	popup.set_item_tooltip(popup.item_count - 1, "切换预览贴图的平滑 / 像素采样，只影响当前编辑测试。")
	popup.add_separator()
	popup.add_check_item("专注工作区（隐藏左右侧栏）", 200)
	popup.set_item_tooltip(popup.get_item_index(200), "暂时隐藏素材库与属性栏，把空间留给中央预览或流程图；再次点击恢复，不影响资源。")
	popup.id_pressed.connect(func(id):
		if id == 200: Workspaces.toggle_focus(host))

static func _update_menu(host) -> void:
	var popup = host.display_menu.get_popup()
	popup.theme = host.theme
	popup.set_item_checked(popup.get_item_index(200), host.get_meta("focused_workspace", false))
	for pair in [["Sizes", host.ui_scale_percent], ["Fonts", host.font_size], ["Sampling", 1 if host.pixel_art else 0]]:
		var menu: PopupMenu = popup.get_node(pair[0])
		menu.theme = host.theme
		for i in menu.item_count: menu.set_item_checked(i, menu.get_item_id(i) == pair[1])

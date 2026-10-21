@tool
extends RefCounted
## 显示接口 apply(host)：重新布局、设置实际字体尺寸；不缩放整个 UI 或低分辨率视口截图。
const REFERENCE_SIZE = Vector2(1440, 900)
const Form = preload("res://addons/stg_maker/ui/form_scene.gd")
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

static func capture_design(host) -> void:
	# 只读取保存的设计；动态表单不属于场景，也不会进入这个快照。
	var controls = []
	for control in host.find_children("*", "Control", true, false):
		if control.owner != host: continue
		var overrides = {}
		for property in control.get_property_list():
			var key = str(property.name)
			if key.begins_with("theme_override_constants/") or key.begins_with("theme_override_font_sizes/") or key.begins_with("theme_override_styles/"):
				var value = control.get(key)
				if value != null: overrides[key] = value.duplicate(true) if value is Resource else value
		controls.append({"node": control, "minimum": control.custom_minimum_size, "overrides": overrides, "split": control.split_offset if control is SplitContainer else 0})
	host.set_meta("studio_design", {"theme": host.theme.duplicate(true), "controls": controls})

static func scale_style(source: StyleBox, unit: float) -> StyleBox:
	var result: StyleBox = source.duplicate(true)
	for property in source.get_property_list():
		var key = str(property.name)
		if key.begins_with("content_margin_") or key.begins_with("expand_margin_") or key.begins_with("border_width_") or key.begins_with("corner_radius_") or key in ["shadow_size", "shadow_offset", "corner_detail"]:
			if key == "corner_detail": continue
			var value = source.get(key)
			if value is Vector2: result.set(key, value * unit)
			elif value >= 0: result.set(key, roundi(value * unit) if value is int else value * unit)
	return result

static func scaled_theme(source: Theme, unit: float) -> Theme:
	var result: Theme = source.duplicate(true)
	result.default_font_size = maxi(1, roundi(source.default_font_size * unit))
	# 补齐基准字号，防止 Godot 外层编辑器主题的小字号透入；显式设计字号仍优先。
	for type in FONT_TYPES:
		if not source.has_font_size("font_size", type): result.set_font_size("font_size", type, result.default_font_size)
	for key in ["normal_font_size", "bold_font_size"]:
		if not source.has_font_size(key, "RichTextLabel"): result.set_font_size(key, "RichTextLabel", result.default_font_size)
	for type in source.get_type_list():
		for key in source.get_font_size_list(type): result.set_font_size(key, type, maxi(1, roundi(source.get_font_size(key, type) * unit)))
		for key in source.get_constant_list(type):
			var value = source.get_constant(key, type)
			result.set_constant(key, type, roundi(value * unit) if value >= 0 else value)
		for key in source.get_stylebox_list(type): result.set_stylebox(key, type, scale_style(source.get_stylebox(key, type), unit))
	return result

static func apply(host) -> void:
	if not host.workspace_active or not host.has_meta("studio_design"): return
	var design: Dictionary = host.get_meta("studio_design")
	var source: Theme = design.theme
	var base = maxi(1, source.default_font_size)
	var font = host.font_size if host.font_size > 0 else base
	var pixels = maxi(1, roundi(font * editor_scale() * factor(host)))
	var unit = float(pixels) / base
	if not is_equal_approx(host.get_meta("display_unit", -1.0), unit):
		host.theme = scaled_theme(source, unit)
		host.set_meta("display_unit", unit)
		for entry in design.controls:
			if not is_instance_valid(entry.node): continue
			var control: Control = entry.node
			control.custom_minimum_size = entry.minimum * unit
			if control is SplitContainer: control.split_offset = roundi(entry.split * unit)
			for key in entry.overrides:
				var value = entry.overrides[key]
				control.set(key, scale_style(value, unit) if value is StyleBox else roundi(value * unit))
	# PopupMenu / FileDialog 是独立 Window，需要显式继承工坊主题。
	for child in host.get_children():
		if child is Window:
			child.theme = host.theme
			if child.has_method("apply_workspace_display"): child.apply_workspace_display(unit)
	# 动态渲染器的占位容器保存设计尺寸，运行内容使用同一份尺寸。
	for key in ["canvas", "flow_editor", "curve_editor", "level_palette"]:
		var control: Control = host.get(key)
		control.custom_minimum_size = host.Layout.node(host, key + "_slot").custom_minimum_size
	host.flow_editor.apply_display(unit)
	_apply_controls(host.inspector, unit)
	_apply_controls(host.toolbar, unit)
	Style.apply_controls(host, unit, host)
	host.canvas.world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if host.pixel_art else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	host.canvas.update_screen_transform()
	host.curve_editor.queue_redraw()
	host.display_menu.text = "界面"
	host.display_menu.tooltip_text = "当前界面大小：" + ("自适应" if host.ui_scale_percent == 0 else "%d%%" % host.ui_scale_percent) + "。调整布局、字号或预览采样；专注模式可暂时隐藏左右侧栏。只影响编辑界面。"
	_update_menu(host)

static func _apply_controls(node: Node, unit: float) -> void:
	if node.get_meta("form_root", false) or node.get_meta("form_fragment", false): Form.apply_display(node, unit, load("res://addons/stg_maker/ui/display.gd"))
	if node.owner == null and not node.get_meta("authored_control", false):
		if node is FormSection: node.apply_display(unit)
		elif node is Label and node.has_meta("numeric_caption"): node.custom_minimum_size.x = roundi(40 * unit)
		elif node is SpinBox: node.custom_minimum_size.x = roundi((76 if node.has_meta("inline_axis") else 115) * unit)
		elif (node is Button or node is LineEdit) and not node.has_meta("custom_control_height"): node.custom_minimum_size.y = node.get_theme_constant("control_height", "STGMetrics")
	for child in node.get_children(): _apply_controls(child, unit)

static func bind_menu(host) -> void:
	var popup = host.display_menu.get_popup()
	popup.clear()
	for child in popup.get_children():
		popup.remove_child(child)
		child.queue_free()
	var scales = PopupMenu.new(); scales.name = "Sizes"; popup.add_child(scales)
	for value in SCALE_OPTIONS:
		scales.add_radio_check_item("自动适配窗口" if value == 0 else "%d%%" % value, value)
		scales.set_item_tooltip(scales.item_count - 1, "根据窗口自动调整工作台尺寸；不改变游戏分辨率。" if value == 0 else "把工作台控件与文字按 %d%% 显示；小窗口可能出现滚动，不改变游戏画面尺寸。" % value)
	scales.id_pressed.connect(host.set_ui_scale)
	popup.add_submenu_item("整体大小", "Sizes")
	popup.set_item_tooltip(popup.item_count - 1, "调整编辑控件和文字的整体显示比例；不缩放游戏数据或设计坐标。")
	var fonts = PopupMenu.new(); fonts.name = "Fonts"; popup.add_child(fonts)
	for value in FONT_OPTIONS:
		fonts.add_radio_check_item("跟随工坊主题" if value == 0 else "%d 号基础字" % value, value)
		fonts.set_item_tooltip(fonts.item_count - 1, "使用 studio_theme.tres 的基础字号；仍受整体大小与编辑器 DPI 影响。" if value == 0 else "使用 %d 号基础文字，仍受整体大小影响；只改变编辑界面的可读性。" % value)
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

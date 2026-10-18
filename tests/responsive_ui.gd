extends SceneTree
## 在与 Godot 主工作区相同的 VBoxContainer 中检查挂载、缩放和坐标交互。
var checks = 0
var failures = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func settle() -> void:
	for i in 8: await process_frame
func run() -> void:
	root.size = Vector2i(1440, 900)
	var parent = VBoxContainer.new()
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(parent)
	# 模拟编辑器父主题提供更小字号，插件应明确覆盖，而不是只设 default_font_size。
	parent.theme = Theme.new(); parent.theme.set_font_size("font_size", "Label", 11)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://responsive_ui_checks.cfg"
	parent.add_child(studio)
	studio.set_font_size(0, false); studio.set_ui_scale(0, false)
	await settle()
	check(studio.size.is_equal_approx(parent.size), "工作台占满 VBox 主工作区")
	check(studio.size_flags_vertical == Control.SIZE_EXPAND_FILL, "容器分配完整高度")
	check(studio.theme.default_font_size == 18 and studio.bullet_button.get_theme_font_size("font_size") == 18, "默认更大字号且覆盖父主题")
	check(studio.scale == Vector2.ONE, "不缩放整个 UI 位图")
	var small_canvas = studio.canvas.size
	root.size = Vector2i(2560, 1440); await settle()
	check(studio.size.is_equal_approx(parent.size), "大窗口仍占满主工作区")
	check(studio.canvas.size.x > small_canvas.x and studio.canvas.size.y > small_canvas.y, "预览跟随窗口变大")
	check(studio.theme.default_font_size > 18, "字号自动随可用窗口增大")
	check(is_equal_approx(studio.canvas.world.scale.x, studio.canvas.world.scale.y), "预览使用等比缩放")
	var point = Vector2(42, -65)
	check(studio.canvas.value(studio.canvas.screen(point)).is_equal_approx(point), "大窗口鼠标坐标换算仍准确")
	check(studio.library_panel.size.x > 205 and studio.inspector_scroll.size.x > 345, "侧栏同步调整尺寸")
	studio.set_ui_scale(150, false); studio.set_font_size(20, false); await settle()
	check(studio.theme.default_font_size == 30, "手动缩放与基础字号组合")
	var menu = studio.display_menu.get_popup().get_node("Sizes")
	check(menu.get_theme_font_size("font_size") == 30, "独立弹出菜单也使用放大字号")
	studio.set_pixel_art(true, false)
	check(studio.canvas.world.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "像素风预览保留像素边缘")
	studio.set_pixel_art(false, false)
	check(studio.canvas.world.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "普通贴图使用平滑采样")
	root.size = Vector2i(1100, 760); studio.set_ui_scale(0, false); studio.set_font_size(0, false); await settle()
	check(studio.size.is_equal_approx(parent.size), "较小窗口不改变工作台挂载范围")
	check(studio.canvas.size.x >= 320 and studio.canvas.size.y >= 260, "小窗口保留可用编辑画布")
	check(studio.layout_margin.size.x <= studio.size.x + 1, "小窗口基本布局不溢出宽度")
	var control = studio.hp_row.get_child(0)
	check(control.autowrap_mode == TextServer.AUTOWRAP_OFF, "血量滑条标签不会挤成纵排")
	studio.queue_free(); parent.queue_free(); await settle()
	print("RESPONSIVE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

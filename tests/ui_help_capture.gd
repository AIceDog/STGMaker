extends SceneTree
## 真实渲染与原生悬停窗口截图；向 Godot 视口投递鼠标事件，不移动系统鼠标。
const Helpers = preload("res://addons/stg_maker/ui/form_section.gd")
var studio
var images = 0
var tooltip_checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for i in 10: await process_frame

func find(node: Node, predicate: Callable):
	if predicate.call(node): return node
	for child in node.get_children(true):
		var found = find(child, predicate)
		if found != null: return found
	return null

func control(caption: String):
	var label = find(studio.inspector, func(node): return node is Label and node.text == caption)
	if label == null: return null
	return label.get_parent().get_child(label.get_index() + 1)

func reveal(target: Control) -> void:
	var parent = target.get_parent()
	while parent != null:
		if parent.get_script() == Helpers and parent.collapsible: parent.heading.button_pressed = true
		parent = parent.get_parent()

func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/ui_help_" + name + "_actual.png")
	images += 1

func motion(at: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func tooltip(target: Control, name: String) -> void:
	reveal(target)
	await settle()
	studio.inspector_scroll.ensure_control_visible(target)
	await settle()
	motion(Vector2(10, 10))
	await process_frame
	motion(target.get_global_rect().get_center())
	await create_timer(0.75).timeout
	await settle()
	var expected = target.get_tooltip()
	var native = find(root, func(node): return node is Label and node.text == expected and node.is_visible_in_tree())
	tooltip_checks += 1
	if native == null or expected.is_empty():
		failures += 1
		push_error("原生悬停说明未显示：" + name)
	await shot(name)
	motion(Vector2(10, 10))
	await settle()

func run() -> void:
	root.size = Vector2i(1440, 1000)
	root.gui_embed_subwindows = true
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://ui_help_capture.cfg"
	studio.show_trajectories = false
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	studio.set_ui_scale(0, false)
	studio.set_font_size(0, false)
	await shot("overview")
	for title in ["弹丸外形", "怎么发射", "怎么飞 / 生效过程"]:
		var section = find(studio.inspector, func(node): return node.get_script() == Helpers and node.title == title)
		if section != null: section.heading.button_pressed = false
	await shot("folded")
	var spin: SpinBox = control("每轮数量")
	if spin != null:
		reveal(spin)
		await settle()
		await tooltip(spin.get_parent().get_child(spin.get_index() - 1), "number_title_tooltip")
		await tooltip(spin.get_line_edit(), "number_input_tooltip")
	var create = find(studio.inspector, func(node): return node is Button and node.text == "＋ 新建子弹素材（圆形）")
	if create != null: await tooltip(create, "material_tooltip")
	var scope: OptionButton = control("修改范围")
	if scope != null:
		reveal(scope)
		scope.select(1)
		scope.item_selected.emit(1)
		await settle()
		await tooltip(control("修改范围"), "shared_scope_tooltip")
	studio.queue_free()
	for i in 12: await process_frame
	print("UI HELP CAPTURE RESULT: %d images, %d tooltip checks, %d failures" % [images, tooltip_checks, failures])
	quit(1 if failures else 0)

extends SceneTree
## 原生悬停说明、折叠状态与素材职责边界，不写入制作配置。
const Section = preload("res://addons/stg_maker/ui/form_section.gd")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func settle() -> void:
	for i in 6: await process_frame
func find(node: Node, predicate: Callable):
	if predicate.call(node): return node
	for child in node.get_children():
		var found = find(child, predicate)
		if found != null: return found
	return null
func section(studio, title: String):
	return find(studio.inspector, func(node): return node.get_script() == Section and node.title == title)
func control(studio, caption: String):
	var label = find(studio.inspector, func(node): return node is Label and node.text == caption)
	if label == null: return null
	var parent = label.get_parent()
	return parent.get_child(label.get_index() + 1) if label.get_index() + 1 < parent.get_child_count() else null
func reveal(target: Control) -> void:
	var parent = target.get_parent()
	while parent != null:
		if parent.get_script() == Section and parent.collapsible: parent.heading.button_pressed = true
		parent = parent.get_parent()

func run() -> void:
	root.size = Vector2i(1440, 1000)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://ui_help_checks.cfg"
	studio.show_trajectories = false
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	await _test_sections(studio)
	await _test_tooltip_targets(studio)
	await _test_material_boundary(studio)
	studio.queue_free()
	for i in 12: await process_frame
	print("UI HELP RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_sections(studio) -> void:
	var project: STGProject = studio.session.project
	var history: int = studio.session.undo_stack.size()
	for title in ["招式类型与引用", "发射节奏", "弹道"]:
		var item = section(studio, title)
		check(item != null, "存在当前职责下的参数分组：" + title)
		if item == null: continue
		check(item.collapsible and item.expanded and item.heading is Button, "主分组默认展开且可折叠：" + title)
		check(item.heading.tooltip_text.length() > title.length() + 10, "分组悬停解释具体内容：" + title)
		item.heading.button_pressed = false
		check(not item.indent.visible, "折叠隐藏整个分组：" + title)
	check(studio.session.project == project and studio.session.undo_stack.size() == history, "折叠不修改资源或撤销历史")
	studio.refresh(true)
	await settle()
	var folded = section(studio, "弹道")
	check(folded != null and not folded.expanded, "表单重建仍记住当前招式的折叠状态")
	var selected_id: String = studio.selected_id
	studio.select_resource(project.barrages[1].id)
	await settle()
	check(section(studio, "弹道").expanded, "不同招式使用独立折叠状态")
	studio.select_resource(selected_id)
	await settle()
	check(not section(studio, "弹道").expanded and studio.session.undo_stack.size() == history, "切回恢复状态且没有配置历史")
	for title in ["招式类型与引用", "发射节奏", "弹道"]:
		var item = section(studio, title)
		if item != null: item.heading.button_pressed = true

func _test_tooltip_targets(studio) -> void:
	var spin = control(studio, "每轮数量")
	check(spin is SpinBox, "每轮数量使用原生数值控件")
	if not spin is SpinBox: return
	reveal(spin)
	var caption: Label = spin.get_parent().get_child(spin.get_index() - 1)
	var help: String = spin.get_tooltip()
	check(help.length() > caption.text.length() + 10 and help.contains("子弹"), "数量悬停说明解释实际发射内容")
	check(caption.get_tooltip() == help and caption.mouse_filter == Control.MOUSE_FILTER_PASS and caption.focus_mode == Control.FOCUS_NONE, "标题触发相同说明但不抢焦点")
	check(spin.get_line_edit().get_tooltip() == help, "内部数值输入框也显示悬停说明")
	var picker = control(studio, "子弹素材")
	check(picker is OptionButton and picker.get_tooltip().contains("这里只更换引用"), "选择器明确只更换素材引用")
	var editor = find(studio.inspector, func(node): return node is Button and node.text == "编辑子弹素材 →")
	check(editor != null and editor.get_tooltip().contains("所有使用处"), "跳转入口明确修改影响所有素材引用处")
	var project = studio.session.project
	var history: int = studio.session.undo_stack.size()
	caption.get_tooltip()
	spin.get_line_edit().get_tooltip()
	check(studio.session.project == project and studio.session.undo_stack.size() == history, "读取帮助不修改配置或历史")

func _test_material_boundary(studio) -> void:
	check(section(studio, "外观") == null, "招式页不内联编辑素材外观")
	check(section(studio, "组合多个发射组") == null and control(studio, "修改范围") == null, "招式页没有发射组和隐式复制范围")
	check(find(studio.inspector, func(node): return node is Button and node.text.contains("新建子弹素材")) == null, "招式页没有素材创建按钮")
	var old_id: String = studio.current().projectile.bullet_id
	var count: int = studio.session.project.bullets.size()
	var editor = find(studio.inspector, func(node): return node is Button and node.text == "编辑子弹素材 →")
	if editor == null: return
	editor.pressed.emit()
	await settle()
	check(studio.collection == "bullets" and studio.selected_id == old_id, "素材编辑入口进入共享素材页")
	check(studio.session.project.bullets.size() == count, "打开素材不产生隐式副本")
	check(section(studio, "外观") != null, "外观编辑统一出现在子弹素材页")

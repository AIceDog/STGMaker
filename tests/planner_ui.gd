extends SceneTree
## 策划制作流程集成：搜索、上下级返回、参数页、测试状态与独立 UI 历史。
var checks = 0
var failures = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func settle() -> void:
	for i in 5: await process_frame
func find_button(node: Node, title: String):
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found = find_button(child, title)
		if found != null: return found
	return null
func find_number(node: Node, caption: String):
	if node is HBoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label and node.get_child(0).text == caption and node.get_child(1) is SpinBox: return node.get_child(1)
	for child in node.get_children():
		var found = find_number(child, caption)
		if found != null: return found
	return null
func search(studio, text: String) -> void:
	studio.library_search.text = text; studio.library_search.text_changed.emit(text)
func run() -> void:
	root.size = Vector2i(1440, 900)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false; studio.settings_path = "user://planner_ui_checks.cfg"
	root.add_child(studio); await settle(); studio.set_process(false)
	check(studio.library_button.button_pressed and studio.inspector_tabs.tab_count == 3, "启动直接进入招式与发射参数页")
	check(studio.undo_button.disabled and studio.redo_button.disabled and not studio.edit_bar.visible, "无历史时撤销禁用，未编辑画布时隐藏结束按钮")
	var selected: String = studio.selected_id; var project = studio.session.project
	search(studio, "圆环")
	check(studio.asset_list.item_count == 1 and studio.asset_list.get_item_text(0) == "圆环齐射", "搜索按资源名称过滤")
	search(studio, "no_matches")
	check(studio.library_empty.visible and studio.selected_id == selected and studio.session.project == project, "无匹配搜索不清空当前选择、不修改资源")
	search(studio, "")
	check(studio.asset_list.item_count == project.barrages.size(), "清空搜索恢复全部资源")
	studio.switch_collection("bosses"); await settle()
	studio.phase_index = 1; studio.flow_node_id = ""; studio.refresh(true)
	studio.select_flow_node(studio.boss_flow().nodes[1].id); await settle()
	var boss_id: String = studio.selected_id; var node_id: String = studio.flow_node_id
	var skill_id: String = studio.boss_action().attack.barrage_id
	var history = studio.session.undo_stack.size()
	find_button(studio.inspector, "编辑调用内容 →").pressed.emit(); await settle()
	check(studio.collection == "barrages" and studio.selected_id == skill_id and studio.back_button.visible, "从 Boss 打开招式有明确返回入口")
	var bullet_id: String = studio.current().projectile.bullet_id
	find_button(studio.inspector, "编辑子弹素材 →").pressed.emit(); await settle()
	check(studio.collection == "bullets" and studio.selected_id == bullet_id and studio.navigation.parents.size() == 2, "招式到子弹保留两层编辑导航")
	studio.select_inspector_tab(1); await settle()
	check(studio.session.undo_stack.size() == history, "切页与引用导航不产生撤销记录")
	check(studio.current() is STGBulletDefinition and studio.inspector_tab == 1, "素材表现页只编辑动画和粒子引用")
	studio.edit_path([], "title", "策划修改的激光"); await settle()
	check(studio.inspector_tab == 1 and not studio.undo_button.disabled, "编辑参数保持所在页并启用撤销")
	studio.navigation.go_back(studio); await settle()
	check(studio.collection == "barrages" and studio.selected_id == skill_id and studio.session.project.find("bullets", bullet_id).title == "策划修改的激光", "返回招式保留子弹修改")
	studio.navigation.go_back(studio); await settle()
	check(studio.collection == "bosses" and studio.selected_id == boss_id and studio.phase_index == 1 and studio.flow_node_id == node_id and not studio.back_button.visible, "返回 Boss 恢复原阶段与节点")
	studio.undo_edit(); await settle()
	check(studio.session.project.find("bullets", bullet_id).title != "策划修改的激光" and not studio.redo_button.disabled, "导航后仍能撤销资源修改")
	studio.select_inspector_tab(1); await settle()
	studio.select_flow_node(node_id); await settle()
	check(studio.inspector_tab == 0, "点击流程节点自动回到当前节点页")
	studio.switch_collection("barrages", skill_id); studio.select_inspector_tab(0); studio.set_tool("flight_path"); await settle()
	check(studio.edit_bar.visible and not studio.playing, "路径编辑有明确的暂停状态与完成入口")
	find_button(studio.edit_bar, "完成编辑").pressed.emit(); await settle()
	check(studio.canvas.edit_mode == "none" and not studio.edit_bar.visible and studio.canvas.has_focus(), "完成编辑释放控制点并恢复玩家测试焦点")
	studio.canvas.world.completed = true; studio.canvas.world.time = 20; studio.toggle_play()
	check(studio.playing and studio.canvas.world.time < 1 and not studio.canvas.world.completed, "攻击结束后开始测试会自动从头播放")
	studio.canvas.world.time = 0.8; studio.canvas.world.player = Vector2(80, 30)
	check(studio.session.save("user://planner_preview_save.tres").is_empty(), "测试中的项目可以保存")
	await settle()
	check(studio.playing and studio.canvas.world.time == 0.8 and studio.canvas.world.player == Vector2(80, 30), "保存项目不会打断测试或重置玩家位置")
	studio.playing = false; studio.edit_path(["projectile", "motion_stages", 0], "duration", -1); await settle()
	check(studio.validation_button.visible and studio.play_button.disabled, "无效配置显示查看原因入口并禁用测试")
	studio.undo_edit(); await settle()
	check(not studio.validation_button.visible and not studio.play_button.disabled, "撤销损坏参数后恢复可测试状态")
	studio.switch_collection("barrages", studio.session.project.barrages[-1].id); studio.select_inspector_tab(0); await settle()
	var warning = find_number(studio.inspector, "前摇时间 s")
	check(warning != null and is_equal_approx(warning.value, 0.12) and warning.step == 0.01, "生命周期时间控件保留0.12秒精度")
	studio.edit_reference("bullets", studio.current().projectile.bullet_id); await settle()
	studio.switch_collection("bosses"); await settle()
	check(studio.navigation.parents.is_empty() and not studio.back_button.visible, "主动切换制作类别结束旧返回链")
	studio.Commands.add(studio, "conditional_boss"); await settle()
	check(studio.inspector_tabs.is_tab_disabled(1), "条件节点不显示可编辑的动作时序")
	studio.queue_free(); for i in 12: await process_frame
	print("PLANNER UI RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

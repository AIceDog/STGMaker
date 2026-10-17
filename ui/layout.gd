@tool
extends RefCounted
## 工作台布局接口 build。这里只创建控件并绑定回调，不处理玩法或编辑快照。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Library = preload("res://addons/stg_maker/ui/library_ui.gd")
const Canvas = preload("res://addons/stg_maker/ui/battle_canvas.gd")
const FlowEditor = preload("res://addons/stg_maker/ui/flow_editor.gd")
const CurveEditor = preload("res://addons/stg_maker/ui/curve_editor.gd")
const LevelTimeline = preload("res://addons/stg_maker/ui/level_timeline.gd")
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
const ResourceTools = preload("res://addons/stg_maker/ui/resource_tools.gd")
const TimelineTools = preload("res://addons/stg_maker/ui/timeline_tools.gd")
const PreviewTransport = preload("res://addons/stg_maker/ui/preview_transport.gd")

static func build(host) -> void:
	var background = ColorRect.new(); background.color = Color("0b1420")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host.add_child(background)
	var workspace = ScrollContainer.new() # Godot 内置容器：小窗口或大字号时允许滚动。
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host.add_child(workspace)
	host.layout_margin = MarginContainer.new()
	host.layout_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.layout_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(host.layout_margin)
	host.layout_outer = VBoxContainer.new(); host.layout_margin.add_child(host.layout_outer)
	_header(host, host.layout_outer)
	var split = HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.layout_outer.add_child(split); Library.build(host, split)
	var body = HSplitContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; split.add_child(body)
	_center(host, body); _inspector(host, body); _curves(host, host.layout_outer)
	host.file_status = F.label(host.layout_outer, "")
	host.file_status.add_theme_color_override("font_color", Style.MUTED)
	host.file_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.file_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	host.file_status.mouse_filter = Control.MOUSE_FILTER_PASS
	_dialogs(host)

static func _header(host, parent: Node) -> void:
	var header = Style.surface(parent, "header", false)
	var project_row = HBoxContainer.new()
	header.add_child(project_row)
	host.brand = F.label(project_row, "STGMAKER")
	host.brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.brand.add_theme_color_override("font_color", Color("55dfbc"))
	var space = Control.new()
	space.custom_minimum_size.x = 10
	project_row.add_child(space)
	Workspaces.build_main(host, project_row)
	host.toolbar = HFlowContainer.new()
	host.toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.toolbar.alignment = FlowContainer.ALIGNMENT_END
	project_row.add_child(host.toolbar)
	var files = MenuButton.new(); files.text = "项目"; host.toolbar.add_child(files)
	Style.button(files)
	files.tooltip_text = "打开、另存整个资源库，或导出当前选中的场景。"
	# 菜单 ID 与显示顺序分开，移除示例入口后保留已有操作的绑定。
	for entry in [["打开项目…", 0], ["另存项目…", 1], ["导出当前场景…", 2], ["打开游戏资源库…", 8], ["打开10个敌人示例…", 3], ["打开 FlyTiger 小怪攻击模板库…", 6], ["打开 FlyTiger Boss 模板库…", 7]]:
		files.get_popup().add_item(entry[0], entry[1])
	var file_hints = {
		0: "载入一个制作资源库，切换当前工作台正在编辑的项目。",
		1: "把整个制作资源库保存为新的 .tres 文件；包含子弹、招式、角色和关卡。",
		2: "导出当前选中的资源及运行依赖，\n得到可实例化的 Godot 场景；\n完整游戏请在“游戏”中出包。",
		8: "打开当前游戏配置引用的制作资源库，继续编辑游戏使用的角色与关卡。",
		3: "切换到十个敌人的示例库，用于查看动作流程；\n需要加入现有项目时可从模板新建。",
		6: "切换到 FlyTiger 小怪完整模板库；\n只添加某个模板时，请使用左侧“从模板新建”。",
		7: "切换到 FlyTiger Boss 完整模板库；\n只添加某个 Boss 时，请使用左侧“从模板新建”。",
	}
	for id in file_hints:
		files.get_popup().set_item_tooltip(files.get_popup().get_item_index(id), file_hints[id])
	files.get_popup().add_item("恢复本机草稿…", 11)
	files.get_popup().set_item_tooltip(files.get_popup().get_item_index(11), "选择本机自动备份的资源库草稿；恢复后另存，不自动覆盖原文件。")
	files.get_popup().add_item("检查所有配置…", 10)
	files.get_popup().set_item_tooltip(files.get_popup().get_item_index(10), "检查当前资源库，点击问题定位到对应的资源和内部步骤。草稿可以保留未完成内容。")
	files.get_popup().add_separator()
	files.get_popup().add_item("当前模板说明…", 9)
	files.get_popup().set_item_tooltip(files.get_popup().get_item_index(9), "查看当前资源已有的设计说明；只阅读，不修改配置。没有说明时不可用。")
	var navigation_ui: Dictionary = host.get_meta(Workspaces.UI_KEY)
	navigation_ui.project_menu = files
	files.get_popup().id_pressed.connect(func(id):
		match id:
			11: host.show_recovery_drafts()
			10: host.show_configuration_issues()
			9: host.show_template_description()
			8: host.open_game_library()
			7:
				if host.open_project("res://presets/flytiger_bosses.tres"): host.switch_collection("bosses")
			6:
				if host.open_project("res://presets/flytiger_enemies.tres"): host.switch_collection("bosses")
			3:
				if host.open_project("res://presets/enemy_library.tres"): host.switch_collection("bosses")
			0: host.open_dialog.popup_centered_ratio(0.65)
			1: host.save_dialog.popup_centered_ratio(0.65)
			2: host.request_export()
	)
	host.save_button = F.button(host.toolbar, "保存项目", host.save_project, "primary")
	host.save_button.tooltip_text = "保存整个资源库，也允许未完成配置。
试玩和导出前仍会检查配置；单个场景从项目菜单导出。"
	host.undo_button = F.button(host.toolbar, "撤销", host.undo_edit)
	host.redo_button = F.button(host.toolbar, "重做", host.redo_edit)
	host.undo_button.tooltip_text = "撤销上一次配置修改；切换页面和测试不计入修改。"
	host.redo_button.tooltip_text = "恢复上一次撤销的配置修改。"
	host.Display.build_menu(host, host.toolbar)
	var context = HBoxContainer.new(); parent.add_child(context)
	host.context_row = context
	host.back_button = F.button(context, "← 返回上一级", func(): host.navigation.go_back(host), "link")
	host.back_button.clip_text = true
	host.back_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	F.help(host.back_button, "返回打开这个引用前的页面，继续编辑原来的招式、角色或关卡。")
	host.subtitle = F.label(context, "")
	host.subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	host.subtitle.add_theme_color_override("font_color", Color("a4b7ca"))

static func _center(host, parent: Node) -> void:
	var center = Style.surface(parent)
	var title_row = HBoxContainer.new()
	center.add_child(title_row)
	host.workspace_caption = F.label(title_row, "战斗预览")
	host.workspace_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.workspace_caption.clip_text = true
	host.workspace_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# PASS 允许悬停读取完整提示，但 Label 不处理点击或获取键盘焦点。
	host.workspace_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	host.workspace_caption.add_theme_color_override("font_color", Color("ecf5fc"))
	host.boss_view_row = HBoxContainer.new(); center.add_child(host.boss_view_row)
	host.flow_view_button = F.button(host.boss_view_row, "行为流程", func(): host.set_boss_view("flow"), "navigation")
	host.battle_view_button = F.button(host.boss_view_row, "战斗预览 / 路径编辑", func(): host.set_boss_view("battle"), "navigation")
	F.help(host.flow_view_button, "查看当前敌人 / Boss 血量阶段的动作顺序和分支；点选节点后在右侧编辑。")
	F.help(host.battle_view_button, "查看角色实际执行效果，并用控制点编辑移动或出生位置；切换视图不修改配置。")
	for button in [host.flow_view_button, host.battle_view_button]: button.toggle_mode = true
	host.play_button = F.button(title_row, "开始测试", host.toggle_play, "primary")
	var replay = F.button(title_row, "重测", host.replay_preview)
	replay.tooltip_text = "从当前测试起点重新运行；不修改制作数据。"
	var trajectory = F.button(title_row, "轨迹", func():
		host.show_trajectories = not host.show_trajectories
		host.canvas.set_trajectories_visible(host.show_trajectories)
		Workspaces.update_preview_tools(host), "navigation")
	trajectory.toggle_mode = true
	trajectory.tooltip_text = "显示当前招式的整段飞行轨迹：\n淡实线是已运行部分，虚线是未来预估。\n按当前玩家位置和固定随机种子计算，\n最多 8 秒 / 48 条；拖动玩家会重新预估。\n激光、区域和尾迹以实际范围为准。"
	Workspaces.build_preview_tools(host, title_row)
	var advanced_panel = VBoxContainer.new()
	center.add_child(advanced_panel)
	advanced_panel.visible = false
	var ui: Dictionary = host.get_meta(Workspaces.UI_KEY)
	ui.advanced_panel = advanced_panel
	ui.trajectory_button = trajectory
	var controls = HFlowContainer.new()
	advanced_panel.add_child(controls)
	F.help(controls, "这些选项只影响当前测试。播放状态用于观察；\n单步、倍速、判定和声音均不会写入游戏配置。")
	host.mode_status = F.note(controls, "已暂停")
	host.mode_status.mouse_filter = Control.MOUSE_FILTER_IGNORE # 状态不阻挡测试工具；说明由外层 controls 承接。
	host.mode_status.tooltip_text = "当前预览状态"
	var step = F.button(controls, "单步", host.step_preview)
	step.tooltip_text = "暂停并前进一个模拟帧，适合检查前摇与攻击生效时机。"
	host.preview_actions.append_array([replay, step])
	F.help(F.note(controls, "速度"), "改变测试播放倍速，便于放慢观察；不会改变招式中保存的时间参数。")
	var speeds = OptionButton.new(); controls.add_child(speeds)
	for label in ["0.25×", "0.5×", "1×", "2×"]:
		speeds.add_item(label)
		speeds.get_popup().set_item_tooltip(speeds.item_count - 1, "以 %s 倍速播放当前测试；玩家和攻击共用该测试时钟，不修改资源中的持续时间。" % label.trim_suffix("×"))
	speeds.select(2); speeds.tooltip_text = "测试速度；玩家与攻击使用相同的模拟时间。"
	speeds.item_selected.connect(func(index): host.playback_speed = [0.25, 0.5, 1.0, 2.0][index])
	host.test_menu = MenuButton.new(); host.test_menu.text = "测试选项"; controls.add_child(host.test_menu)
	Style.button(host.test_menu)
	var popup = host.test_menu.get_popup()
	popup.add_check_item("显示攻击判定", 0); popup.add_check_item("播放声音", 1)
	F.help(host.test_menu, "切换当前预览的碰撞判定显示和声音；不修改攻击范围或音效资源。")
	popup.set_item_tooltip(popup.get_item_index(0), "在实际攻击外形上显示判定范围，检查视觉与碰撞是否一致；只改变测试显示。")
	popup.set_item_tooltip(popup.get_item_index(1), "在测试中播放已配置的音效；关闭时静音，音效资源仍然保留。")
	popup.id_pressed.connect(func(id):
		if id == 0: host.show_collision = not host.show_collision; host.canvas.world.show_collision = host.show_collision
		else: host.sound_enabled = not host.sound_enabled; host.canvas.world.muted = not host.sound_enabled
		host.update_preview_ui())
	host.edit_bar = HBoxContainer.new(); center.add_child(host.edit_bar)
	host.edit_hint = F.label(host.edit_bar, ""); host.edit_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.edit_hint.add_theme_color_override("font_color", Style.AMBER)
	F.help(host.edit_hint, "当前画布编辑工具的操作提示。拖动控制点后释放鼠标，整次修改可一次撤销。")
	F.button(host.edit_bar, "完成编辑", host.finish_canvas_edit, "primary").tooltip_text = "退出控制点编辑，恢复玩家移动测试。"
	host.flow_editor = FlowEditor.new(); host.flow_editor.host = host
	host.flow_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL; center.add_child(host.flow_editor)
	host.canvas = Canvas.new(); host.canvas.host = host
	F.help(host.canvas, "先点击画面取得焦点，再用 WASD 移动测试玩家；\n也可拖动玩家点改变目标位置。\n关卡测试时按住空格射击。\n编辑控制点时请先“完成编辑”，再恢复玩家移动测试。")
	host.canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL; center.add_child(host.canvas)
	PreviewTransport.build(host, center)
	host.level_panel = VBoxContainer.new(); center.add_child(host.level_panel)
	var timeline_controls = HFlowContainer.new(); host.level_panel.add_child(timeline_controls)
	F.button(timeline_controls, "＋ 出场", func(): host.LevelCommands.add_event(host)).tooltip_text = "在选中阶段添加编队出场事件"
	F.help(F.button(timeline_controls, "＋ 阶段", func(): host.Commands.edit_list(host, ["segments"], "add", func(): return host.LevelCommands.D.level_segment(), host.segment_index)), "在当前关卡末尾新增一个阶段；阶段结束方式、计划长度和卷轴在右侧设置。可以撤销。")
	var test_from = MenuButton.new()
	test_from.text = "测试起点"
	test_from.tooltip_text = "选择从关卡开头或当前阶段重新测试"
	Style.button(test_from)
	timeline_controls.add_child(test_from)
	test_from.get_popup().add_item("从关卡开头测试", 0)
	test_from.get_popup().add_item("从本阶段测试", 1)
	test_from.get_popup().set_item_tooltip(0, "清除当前测试状态，从关卡第一个阶段重新运行。不会修改关卡内容。")
	test_from.get_popup().set_item_tooltip(1, "清除当前测试状态，从选中阶段开始，快速检查本段出场与结束条件；不重放前面阶段。")
	test_from.get_popup().id_pressed.connect(func(id): host.test_level(id == 1))
	host.preview_actions.append(test_from)
	F.button(timeline_controls, "整关", func(): host.level_timeline.fit_all()).tooltip_text = "显示完整关卡，复位缩放与滚动。"
	F.label(timeline_controls, "缩放")
	host.timeline_zoom = HSlider.new(); host.timeline_zoom.min_value = 1; host.timeline_zoom.max_value = 16; host.timeline_zoom.step = 0.25
	host.timeline_zoom.custom_minimum_size.x = 85
	host.timeline_zoom.tooltip_text = "只放大或缩小计划时间轴，\n不改变事件时间与阶段长度。\n也可在时间轴上按 Ctrl + 滚轮缩放；\n“整关”恢复完整视图。"
	host.timeline_zoom.value_changed.connect(func(value): host.level_timeline.set_zoom(value))
	timeline_controls.add_child(host.timeline_zoom)
	F.toggle(timeline_controls, "环境轨", true, func(value): host.level_timeline.environment_visible = value; host.level_timeline.queue_redraw()).tooltip_text = "展开或收起背景卷轴与音乐轨。"
	host.timeline_scroll = ScrollContainer.new()
	host.timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	host.timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	host.timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.level_panel.add_child(host.timeline_scroll)
	host.level_timeline = LevelTimeline.new(); host.level_timeline.host = host
	F.help(host.level_timeline, "这是整关的计划时间，不是实际战斗计时。\n点击阶段或出场条后在右侧编辑。\n拖动阶段中部调整顺序，拖动右边缘调整计划长度；\n出场条可跨阶段拖动。Ctrl + 滚轮缩放，中键平移。\n从左侧出场素材拖入可新增事件；\n等待清场或击败条件时，后续阶段会整体推迟。")
	host.level_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.timeline_scroll.add_child(host.level_timeline)
	TimelineTools.build(host, timeline_controls)
	host.condition_debug = TimelineTools.build_debug(host.level_panel)
	host.timeline_status = F.note(host.level_panel, "")
	F.help(host.timeline_status, "计划进度按阶段组织，实际战斗时间包含等待清场等耗时；后续阶段会等待当前阶段的结束条件。")
	host.preview_status = F.note(advanced_panel, "")
	F.help(host.preview_status, "当前测试的累计时间、存活攻击和命中情况，用于观察效果；不会修改资源中的伤害与时序。")
	host.validation_button = F.button(center, "查看需要调整的配置", host.show_configuration_issues, "danger")
	host.hp_row = HBoxContainer.new(); advanced_panel.add_child(host.hp_row)
	F.label(host.hp_row, "测试 Boss 血量")
	host.hp_slider = HSlider.new(); host.hp_slider.min_value = 0; host.hp_slider.max_value = 100; host.hp_slider.value = 100
	host.hp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL; host.hp_row.add_child(host.hp_slider)
	F.help(host.hp_slider, "调整当前测试中的 Boss 剩余血量百分比，\n检查不同血量阶段；不修改角色最大生命值或阶段阈值。")
	host.hp_slider.value_changed.connect(func(value): host.canvas.world.hp = value)

static func _inspector(host, parent: Node) -> void:
	var panel = Style.surface(parent)
	panel.get_parent().size_flags_horizontal = Control.SIZE_FILL
	host.inspector_caption = F.note(panel, "")
	host.inspector_caption.add_theme_color_override("font_color", Style.AMBER)
	host.inspector_context = F.note(panel, "")
	host.inspector_context.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.inspector_context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	host.inspector_context.mouse_filter = Control.MOUSE_FILTER_PASS
	host.inspector_context.visible = false
	var tools = HFlowContainer.new()
	panel.add_child(tools)
	F.help(F.button(tools, "全部收起", func(): ResourceTools.set_expanded(host.inspector, false)), "收起当前属性页的所有分组；不修改配置。")
	F.help(F.button(tools, "展开", func(): ResourceTools.set_expanded(host.inspector, true)), "展开当前属性页的所有分组；不修改配置。")
	F.help(F.button(tools, "使用位置", func(): ResourceTools.show_usages(host)), "查看当前资源被哪些招式、敌人或关卡直接使用，点击条目可定位。")
	host.inspector_tabs = TabBar.new() # Godot 内置页签；正文只构建当前页，避免隐藏控件占布局。
	F.help(host.inspector_tabs, "切换当前资源的设置页；保持选中资源不变，也不会新增一次配置修改。")
	host.inspector_tabs.tab_changed.connect(host.select_inspector_tab); panel.add_child(host.inspector_tabs)
	host.inspector_scroll = ScrollContainer.new()
	host.inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; panel.add_child(host.inspector_scroll)
	host.inspector = VBoxContainer.new(); host.inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.inspector_scroll.add_child(host.inspector)

static func _curves(host, parent: Node) -> void:
	host.curve_panel = VBoxContainer.new(); parent.add_child(host.curve_panel)
	var row = HBoxContainer.new(); host.curve_panel.add_child(row)
	F.label(row, "时间曲线编辑")
	host.curve_selector = OptionButton.new(); row.add_child(host.curve_selector)
	F.help(host.curve_selector, "选择当前运动步骤要编辑的时间曲线：\n外观大小、碰撞范围或路径进度。\n修改只作用于当前曲线所属配置。")
	host.curve_selector.item_selected.connect(func(index): host.open_curve(host.curve_scope, host.curve_keys[index]))
	host.curve_ceiling = SpinBox.new(); host.curve_ceiling.prefix = "显示上限 "
	host.curve_ceiling.min_value = 1; host.curve_ceiling.max_value = 10; host.curve_ceiling.value = 3; row.add_child(host.curve_ceiling)
	F.help(host.curve_ceiling, "只调整曲线画布纵轴的显示上限，\n方便查看大于 1 倍的数值；不会缩放或改写曲线。")
	host.curve_ceiling.value_changed.connect(func(value): host.curve_editor.ceiling = value; host.curve_editor.queue_redraw())
	F.help(F.button(row, "收起曲线", func(): host.curve_panel.hide()), "隐藏时间曲线编辑区，已提交的曲线修改继续保留。")
	host.curve_editor = CurveEditor.new()
	host.curve_editor.curve_changed.connect(func(curve): host.edit_path(host.curve_scope, host.curve_key, curve))
	host.curve_panel.add_child(host.curve_editor); host.curve_panel.hide()

static func _dialogs(host) -> void:
	for pair in [["open_dialog", FileDialog.FILE_MODE_OPEN_FILE], ["save_dialog", FileDialog.FILE_MODE_SAVE_FILE], ["export_dialog", FileDialog.FILE_MODE_SAVE_FILE], ["asset_dialog", FileDialog.FILE_MODE_OPEN_FILE]]:
		var dialog = FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = pair[1]
		host.add_child(dialog); host.set(pair[0], dialog)
	host.open_dialog.filters = PackedStringArray(["*.tres ; STGMaker 项目"])
	host.save_dialog.filters = PackedStringArray(["*.tres ; STGMaker 项目"])
	host.save_dialog.current_file = "project_v10.tres"
	host.export_dialog.filters = PackedStringArray(["*.tscn ; Godot 预制体场景"])
	host.open_dialog.file_selected.connect(host.open_project); host.save_dialog.file_selected.connect(host.save_to)
	host.export_dialog.file_selected.connect(func(path):
		var error = host.Commands.export_prefab(host, path)
		host.message("已导出可实例化场景：\n" + path if error.is_empty() else error))
	host.asset_dialog.file_selected.connect(host.assign_asset)
	host.message_dialog = AcceptDialog.new(); host.add_child(host.message_dialog); host.message_dialog.title = "STGMaker"

@tool
extends RefCounted
## 静态节点由 studio.tscn 保存；这里只连接行为和装配动态内容。
const Canvas = preload("res://addons/stg_maker/ui/battle_canvas.gd")
const FlowEditor = preload("res://addons/stg_maker/ui/flow_editor.gd")
const CurveEditor = preload("res://addons/stg_maker/ui/curve_editor.gd")
const LevelTimeline = preload("res://addons/stg_maker/ui/level_timeline.gd")
const Workspaces = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
const ResourceTools = preload("res://addons/stg_maker/ui/resource_tools.gd")
const TimelineTools = preload("res://addons/stg_maker/ui/timeline_tools.gd")
const PreviewTransport = preload("res://addons/stg_maker/ui/preview_transport.gd")

static func node(host, key: String) -> Node:
    return host.get_node("%" + key)

static func build(host) -> void:
    for key in STATIC_FIELDS:
        host.set(key, node(host, key))
    node(host, "inspector_placeholder").hide()
    Workspaces.bind(host)
    _header(host)
    host.Library.bind(host)
    _center(host)
    _inspector(host)
    _curves(host)
    _dialogs(host)

# 唯一名是行为接口；移动节点时不依赖它们的父路径。
const STATIC_FIELDS = [
    "boss_view_row", "flow_view_button", "battle_view_button", "level_button", "level_panel",
    "timeline_scroll", "timeline_zoom", "timeline_status", "palette_panel", "inspector",
    "asset_list", "bullet_button", "create_button", "library_button", "boss_button",
    "play_button", "hp_row", "hp_slider", "subtitle", "preview_status",
    "file_status", "curve_panel", "curve_selector", "curve_ceiling", "layout_margin",
    "layout_outer", "toolbar", "brand", "library_panel", "inspector_scroll",
    "library_help", "display_menu", "library_title", "library_search", "library_empty",
    "copy_button", "delete_button", "back_button", "undo_button", "redo_button",
    "inspector_caption", "inspector_tabs", "test_menu", "edit_bar", "edit_hint",
    "validation_button", "save_button", "workspace_caption", "mode_status", "inspector_context",
    "context_row",
]

static func mount(host, key: String, control: Control) -> Control:
    var slot: Control = node(host, key + "_slot")
    for child in slot.get_children(): child.hide()
    control.tooltip_text = slot.tooltip_text
    if key != "curve_editor": control.set("host", host)
    slot.add_child(control)
    if slot is Container:
        control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    else:
        control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    control.visibility_changed.connect(func(): slot.visible = control.visible)
    slot.visible = control.visible
    return control

static func press(host, key: String, action: Callable) -> void:
    node(host, key).pressed.connect(action)

static func _header(host) -> void:
    var files: MenuButton = node(host, "nav_project_menu")
    files.get_popup().clear()
    # 菜单 ID 与显示顺序分开，移除示例入口后保留已有操作的绑定。
    for entry in [["打开项目…", 0], ["另存项目…", 1], ["导出当前场景…", 2], ["打开游戏资源库…", 8]]:
        files.get_popup().add_item(entry[0], entry[1])
    var file_hints = {
        0: "载入一个制作资源库，切换当前工作台正在编辑的项目。",
        1: "把整个制作资源库保存为新的 .tres 文件；包含子弹、招式、角色和关卡。",
        2: "导出当前选中的资源及运行依赖，\n得到可实例化的 Godot 场景；\n完整游戏请在“游戏”中出包。",
        8: "打开当前游戏配置引用的制作资源库，继续编辑游戏使用的角色与关卡。",
        3: "切换到十个敌人的示例库，用于查看动作流程；\n需要加入现有项目时可从模板新建。",
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
            0: host.open_dialog.popup_centered_ratio(0.65)
            1: host.save_dialog.popup_centered_ratio(0.65)
            2: host.request_export()
    )
    press(host, "save_button", host.save_project)
    press(host, "undo_button", host.undo_edit)
    press(host, "redo_button", host.redo_edit)
    press(host, "back_button", func(): host.navigation.go_back(host))
    host.Display.bind_menu(host)

static func _center(host) -> void:
    press(host, "flow_view_button", func(): host.set_boss_view("flow"))
    press(host, "battle_view_button", func(): host.set_boss_view("battle"))
    press(host, "play_button", host.toggle_play)
    press(host, "replay_button", host.replay_preview)
    press(host, "nav_trajectory_button", func():
        host.show_trajectories = not host.show_trajectories
        host.canvas.set_trajectories_visible(host.show_trajectories)
        Workspaces.update_preview_tools(host))
    press(host, "step_button", host.step_preview)
    host.preview_actions.append_array([node(host, "replay_button"), node(host, "step_button")])
    node(host, "speed_selector").item_selected.connect(func(index): host.playback_speed = [0.25, 0.5, 1.0, 2.0][index])
    var popup = host.test_menu.get_popup()
    popup.id_pressed.connect(func(id):
        if id == 0: host.show_collision = not host.show_collision; host.canvas.world.show_collision = host.show_collision
        else: host.sound_enabled = not host.sound_enabled; host.canvas.world.muted = not host.sound_enabled
        host.update_preview_ui())
    press(host, "finish_edit_button", host.finish_canvas_edit)
    host.flow_editor = mount(host, "flow_editor", FlowEditor.new())
    host.canvas = mount(host, "canvas", Canvas.new())
    PreviewTransport.bind(host)
    press(host, "add_event_button", func(): host.LevelCommands.add_event(host))
    press(host, "add_segment_button", func(): host.Commands.edit_list(host, ["segments"], "add", func(): return host.LevelCommands.D.level_segment(), host.segment_index))
    var test_from = node(host, "test_from_menu")
    test_from.get_popup().id_pressed.connect(func(id): host.test_level(id == 1))
    host.preview_actions.append(test_from)
    press(host, "fit_timeline_button", func(): host.level_timeline.fit_all())
    host.timeline_zoom.value_changed.connect(func(value): host.level_timeline.set_zoom(value))
    node(host, "environment_toggle").toggled.connect(func(value): host.level_timeline.environment_visible = value; host.level_timeline.queue_redraw())
    host.level_timeline = mount(host, "level_timeline", LevelTimeline.new())
    TimelineTools.build(host, node(host, "timeline_controls"))
    host.condition_debug = TimelineTools.build_debug(host.level_panel)
    press(host, "validation_button", host.show_configuration_issues)
    host.hp_slider.value_changed.connect(func(value): host.canvas.world.hp = value)

static func _inspector(host) -> void:
    press(host, "collapse_button", func(): ResourceTools.set_expanded(host.inspector, false))
    press(host, "expand_button", func(): ResourceTools.set_expanded(host.inspector, true))
    press(host, "usages_button", func(): ResourceTools.show_usages(host))
    host.inspector_tabs.tab_changed.connect(host.select_inspector_tab)

static func _curves(host) -> void:
    host.curve_selector.item_selected.connect(func(index): host.open_curve(host.curve_scope, host.curve_keys[index]))
    host.curve_ceiling.value_changed.connect(func(value): host.curve_editor.ceiling = value; host.curve_editor.queue_redraw())
    press(host, "close_curve_button", func(): host.curve_panel.hide())
    host.curve_editor = mount(host, "curve_editor", CurveEditor.new())
    host.curve_editor.curve_changed.connect(func(curve): host.edit_path(host.curve_scope, host.curve_key, curve))
    host.curve_panel.hide()

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

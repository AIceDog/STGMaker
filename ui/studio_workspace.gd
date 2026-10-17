@tool
extends Control
## 工作台入口：只协调选择、会话和预览。布局、表单、编辑命令与运行规则分别在独立模块。
const ResourceTools = preload("res://addons/stg_maker/ui/resource_tools.gd")
const TimelineTools = preload("res://addons/stg_maker/ui/timeline_tools.gd")
const DraftRecovery = preload("res://addons/stg_maker/ui/draft_recovery.gd")
const Structure = preload("res://addons/stg_maker/authoring/document_structure.gd")
const Session = preload("res://addons/stg_maker/ui/session.gd")
const Layout = preload("res://addons/stg_maker/ui/layout.gd")
const Inspector = preload("res://addons/stg_maker/ui/inspector.gd")
const Fields = preload("res://addons/stg_maker/ui/fields.gd")
const Commands = preload("res://addons/stg_maker/ui/commands.gd")
const Display = preload("res://addons/stg_maker/ui/display.gd")
const Library = preload("res://addons/stg_maker/ui/library_ui.gd")
const Navigation = preload("res://addons/stg_maker/ui/editor_navigation.gd")
const LevelCommands = preload("res://addons/stg_maker/ui/level_commands.gd")
const LevelTiming = preload("res://stg/definitions/level_timing.gd")
const Context = preload("res://addons/stg_maker/ui/workspace_context.gd")
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
const GameProjectPanel = preload("res://addons/stg_maker/ui/game_project_panel.gd")
const GameDocument = preload("res://addons/stg_maker/authoring/game_document.gd")
const ConfigPath = preload("res://addons/stg_maker/authoring/config_path.gd")
const ConfigCopy = preload("res://stg/definitions/config_copy.gd")
const WorkspaceNavigation = preload("res://addons/stg_maker/ui/workspace_navigation.gd")
const SETTINGS_PATH = "user://stg_maker.cfg"
const EDIT_LABELS = {
	"path": "路径", "skill_path": "Boss 路径", "target": "目标点",
	"skill_target": "移动目标 / 圆心", "spawn": "出生排列",
	"level_spawn": "编队出生点",
	"flight_path": "子弹飞行路径",
}
var settings_path: String = SETTINGS_PATH # 测试可使用独立偏好文件，不改用户设置。
var session = Session.new()
var collection: String = "barrages"
var selected_id: String = ""
var material_filter: String = "all" # 素材类型筛选只属于界面。
var selection_memory: Dictionary = {}
var navigation = Navigation.new()
# 选择属于工作台，不写入制作资源；撤销后会按新快照修复失效的索引 / ID。
var inspector_tab: int = 0
var inspected_key: String = "" # 区分切换资源与刷新当前资源，避免改一个数值就跳回第一页。
var stage_index: int = 0
var phase_index: int = 0
var flow_path: Array = []
var flow_node_id: String = ""
var boss_view: String = "flow"
var flow_editor: Control
var boss_view_row: HBoxContainer
var flow_view_button: Button
var battle_view_button: Button
var section_states: Dictionary = {} # 只记录 UI 展开状态，不进入项目、历史和运行配置。
var edit_beam: bool = false
var inspector_dirty: bool = true
var refresh_queued: bool = false
var playing: bool = false
var preview_selection: String = ""
var accumulator: float = 0
var playback_speed: float = 1
var show_collision: bool = false
var show_trajectories: bool = true
var sound_enabled: bool = false
var font_size: int = 0
var ui_scale_percent: int = 0 # 0 = 结合窗口大小与 Godot 编辑器 DPI 自动适配。
var pixel_art: bool = false
var display_queued: bool = false
var restore_last_project: bool = true
var curve_scope: Array = []
var curve_keys: Array = []
var curve_key: String = "visual_scale_curve"
var asset_key: String = ""
var asset_scope: Array = []
var segment_index: int = 0
var event_id: String = ""
var background_index: int = 0
var level_test_from_selected: bool = false
var level_button: Button
var level_panel: VBoxContainer
var level_timeline: Control
var timeline_scroll: ScrollContainer
var timeline_zoom: HSlider
var condition_debug: Control
var timeline_status: Label
var palette_panel: VBoxContainer
var level_palette: ItemList
var canvas: Control
var inspector: VBoxContainer
var asset_list: ItemList
var bullet_button: Button
var create_button: MenuButton
var library_button: Button
var boss_button: Button
var play_button: Button
var hp_row: HBoxContainer
var hp_slider: HSlider
var subtitle: Label
var preview_status: Label
var file_status: Label
var curve_panel: VBoxContainer
var curve_editor: Control
var curve_selector: OptionButton
var curve_ceiling: SpinBox
var open_dialog: FileDialog
var save_dialog: FileDialog
var export_dialog: FileDialog
var asset_dialog: FileDialog
var message_dialog: AcceptDialog
var layout_margin: MarginContainer
var layout_outer: VBoxContainer
var toolbar: HFlowContainer
var brand: Label
var library_panel: VBoxContainer
var inspector_scroll: ScrollContainer
var library_help: Label
var display_menu: MenuButton
var library_title: Label
var library_search: LineEdit
var library_empty: Label
var copy_button: Button
var delete_button: Button
var back_button: Button
var undo_button: Button
var redo_button: Button
var inspector_caption: Label
var inspector_tabs: TabBar
var test_menu: MenuButton
var edit_bar: HBoxContainer
var edit_hint: Label
var validation_button: Button
var save_button: Button
var workspace_caption: Label
var mode_status: Label
var inspector_context: Label
var preview_actions: Array[Button] = []
var context_row: HBoxContainer
var game_project_panel: Window

func _ready() -> void: # Godot 回调
	# 独立工坊也需要重新保存已加载的帧素材，保留原生纹理的压缩源数据。
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	session.create()
	_restore_preferences()
	set_font_size(font_size, false)
	Layout.build(self)
	resized.connect(_request_display)
	session.changed.connect(_document_changed)
	DraftRecovery.setup(self)
	refresh(true)
	_request_display()

func _load_settings() -> ConfigFile:
	var config = ConfigFile.new()
	config.load(settings_path)
	return config

func _restore_preferences() -> void:
	# 首次布局前读偏好；恢复项目只改变会话，不弹出制作过程中使用的对话框。
	var config = _load_settings()
	if not config.get_sections().is_empty():
		font_size = config.get_value("display", "font_size", 0)
	ui_scale_percent = config.get_value("display", "ui_scale_percent", 0)
	pixel_art = config.get_value("display", "pixel_art", false)
	if ui_scale_percent not in Display.SCALE_OPTIONS:
		ui_scale_percent = 0
	var last_project = config.get_value("files", "last_project", "")
	if restore_last_project and last_project is String and not last_project.is_empty() and FileAccess.file_exists(last_project):
		session.open(last_project)
	if font_size not in [0, 16, 18, 20, 24]:
		font_size = 0

# 查询接口：返回制作配置。运行中的位置和年龄始终从 canvas.world 读取。
func current() -> Resource: return session.project.find(collection, selected_id) if session.project != null else null
func motion_stage() -> STGMotionStage: return config_at(motion_scope())
func motion_scope() -> Array: return ["projectile", "motion_stages", stage_index]

func config_at(scope: Array): return ConfigPath.resolve(current(), scope)

func edit_configuration(scope: Array, change: Callable, rebuild: bool = true) -> void:
	var kind = collection
	var identifier = selected_id
	inspector_dirty = inspector_dirty or rebuild
	session.edit(func(project): change.call(ConfigPath.resolve(project.find(kind, identifier), scope), project))

func fire_pattern() -> STGFirePattern: return current().fire_pattern if current() is STGBarrageSkill else null

func boss_phase() -> STGBossPhase:
	return current().phases[phase_index] if current() is STGBossDefinition and phase_index >= 0 and phase_index < current().phases.size() else null
func flow_scope() -> Array:
	return (["phases", phase_index, "behavior_flow"] if current() is STGBossDefinition else []) + flow_path

func boss_flow() -> STGBehaviorFlow: return ConfigPath.resolve(current(), flow_scope()) if current() is STGBossDefinition or current() is STGBehaviorFlow else null

func boss_node() -> STGFlowNode: return boss_flow().find(flow_node_id) if boss_flow() != null else null
func boss_action() -> STGBossAction:
	var node = boss_node()
	return node.action if node != null and node.kind == "action" else null
func boss_node_scope() -> Array: return flow_scope() + ["nodes", boss_flow().index_of(flow_node_id)]

func boss_action_scope() -> Array: return boss_node_scope() + ["action"]

func level_segment() -> STGLevelSegment:
	return current().segments[segment_index] if current() is STGLevelDefinition and segment_index >= 0 and segment_index < current().segments.size() else null
func level_event_index() -> int:
	if level_segment() == null: return -1
	for i in level_segment().events.size():
		if level_segment().events[i] != null and level_segment().events[i].id == event_id: return i
	return -1
func level_event() -> STGLevelEvent:
	var index = level_event_index()
	return level_segment().events[index] if index >= 0 else null
func level_event_scope() -> Array: return ["segments", segment_index, "events", level_event_index()]

func select_level_segment(index: int) -> void:
	segment_index = index
	event_id = ""
	inspector_tab = 1
	canvas.edit_mode = "none"
	refresh(true)

func select_level_event(id: String) -> void:
	event_id = id
	inspector_tab = 0
	playing = false
	canvas.release_player_controls()
	canvas.edit_mode = "level_spawn"
	Inspector.build(self)
	canvas.rebuild()
	level_timeline.queue_redraw()
	update_preview_ui()
	_request_display()

func test_level(from_selected: bool) -> void:
	level_test_from_selected = from_selected
	replay_preview()

func select_flow_node(id: String) -> void:
	flow_node_id = id
	inspector_tab = 0 # 点击流程节点立即显示节点参数，不把策划留在阶段设置页。
	flow_editor.select_node(id)
	Inspector.build(self)
	_request_display()
	if canvas.edit_mode != "none": canvas.rebuild()

func set_boss_view(value: String) -> void:
	boss_view = value
	_update_views()
	if boss_view == "flow": flow_editor.request_fit()

func _update_views() -> void:
	var editing_boss = collection in ["bosses", "behaviors"] and current() != null and Structure.issue(current()).is_empty()
	boss_view_row.visible = editing_boss
	flow_editor.visible = editing_boss and boss_view == "flow"
	canvas.visible = not editing_boss or boss_view == "battle"
	flow_view_button.button_pressed = boss_view == "flow"
	battle_view_button.button_pressed = boss_view == "battle"
	level_panel.visible = collection == "levels" and current() != null and Structure.issue(current()).is_empty()
	Context.update(self)
	update_preview_ui()

func reset_selection() -> void:
	# 换资源时清空资源内部选择；collection / selected_id 由调用者先设置。
	set_meta("shared_style_scopes", {}) # 联动修改只对当前明确选择生效，不带到另一项目或资源。
	stage_index = 0
	phase_index = 0
	flow_path.clear()
	flow_node_id = ""
	inspected_key = ""
	segment_index = 0
	event_id = ""
	background_index = 0
	level_test_from_selected = false
	asset_scope = []
	canvas.edit_mode = "none"
	canvas.release_player_controls()
	curve_panel.hide()

func switch_collection(next: String, id: String = "") -> void:
	navigation.parents.clear() # 顶部切页开始新的制作上下文，引用编辑才保留返回链。
	show_collection(next, id)

func show_collection(next: String, id: String = "") -> void:
	selection_memory[collection] = selected_id
	collection = next
	if next == "bullets": material_filter = "all"
	selected_id = id if not id.is_empty() else selection_memory.get(next, "")
	library_search.text = ""
	reset_selection()
	refresh(true)

func select_resource(id: String) -> void:
	selected_id = id
	reset_selection()
	refresh(true)

func edit_reference(next: String, id: String) -> void:
	navigation.open_reference(self, next, id)

func select_inspector_tab(index: int) -> void:
	inspector_tab = index
	Inspector.build(self)
	inspector_scroll.scroll_vertical = 0
	_request_display()

func _document_changed() -> void:
	# 一次编辑可能连续改多个关联字段。合并到下一轮消息处理，再读完整的新快照。
	if refresh_queued:
		return
	refresh_queued = true
	_refresh_deferred.call_deferred()

func _refresh_deferred() -> void:
	refresh_queued = false
	refresh(inspector_dirty)
	inspector_dirty = false

func refresh(rebuild_inspector: bool = true) -> void:
	if not is_instance_valid(canvas):
		return
	var resource = _repair_selection()
	Library.refresh(self)
	level_timeline.queue_redraw()
	_update_views()
	if collection in ["bosses", "behaviors"] and resource != null and Structure.issue(resource).is_empty():
		flow_editor.rebuild()
	if rebuild_inspector:
		Inspector.build(self)
	Inspector.update_context(self)
	navigation.refresh(self)
	undo_button.disabled = session.undo_stack.is_empty()
	redo_button.disabled = session.redo_stack.is_empty()
	undo_button.tooltip_text = "还没有可撤销的配置修改。" if undo_button.disabled else "撤销上一次配置修改；切换页面和测试不计入修改。"
	redo_button.tooltip_text = "还没有可恢复的撤销操作。" if redo_button.disabled else "恢复上一次撤销的配置修改。"
	_request_display()
	_sync_preview_after_refresh()
	_refresh_open_curve()
	_update_file_status()
	update_preview_ui()

func _repair_selection() -> Resource:
	var entries = session.project.get(collection)
	if current() == null: selected_id = entries[0].id if not entries.is_empty() else ""
	var resource = current()
	if not Structure.issue(resource).is_empty(): return resource
	if resource is STGBarrageSkill:
		stage_index = clampi(stage_index, 0, maxi(0, resource.projectile.motion_stages.size() - 1))
	elif resource is STGBossDefinition or resource is STGBehaviorFlow:
		if resource is STGBossDefinition: phase_index = clampi(phase_index, 0, resource.phases.size() - 1)
		if boss_flow() == null: flow_path.clear()
		if boss_node() == null and boss_flow() != null: flow_node_id = boss_flow().entry_id
	elif resource is STGLevelDefinition:
		segment_index = clampi(segment_index, 0, resource.segments.size() - 1)
		background_index = clampi(background_index, 0, maxi(0, resource.background_layers.size() - 1))
		if not event_id.is_empty() and level_event() == null: event_id = ""
	return resource

func _sync_preview_after_refresh() -> void:
	# 保存文件或刷新 UI 没有改变配置对象，不必打断正在测试的攻击。
	if canvas.world.project != session.project or preview_selection != _preview_selection_key():
		restart()
	else:
		canvas.rebuild()

func _refresh_open_curve() -> void:
	if not curve_panel.visible: return
	if collection == "barrages": curve_scope = motion_scope()
	open_curve(curve_scope, curve_key)

func _update_file_status() -> void:
	var state = "● 未保存  " if session.dirty() else "已保存  "
	var location = session.file_path if not session.file_path.is_empty() else "新项目 · 保存包含攻击、敌人和关卡"
	file_status.text = state + location
	Fields.help(file_status, file_status.text + "\n保存的是整个资源库，使用顶部“保存项目”。\n这行只显示文件位置和保存状态。")

func edit_path(scope: Array, key: String, value, rebuild: bool = false) -> void:
	Commands.set_field(self, scope, key, value, rebuild)

func set_tool(mode: String) -> void:
	playing = false
	canvas.release_player_controls()
	if collection in ["bosses", "behaviors"]: set_boss_view("battle")
	canvas.edit_mode = mode
	canvas.rebuild()
	update_preview_ui()

# 预览操作接口：只改变画布模式、时钟与调试位置，不产生制作资源历史。
func finish_canvas_edit() -> void:
	canvas.edit_mode = "none"
	canvas.rebuild()
	if canvas.visible: canvas.grab_focus()
	update_preview_ui()
	_request_display()

func replay_preview() -> void:
	finish_canvas_edit()
	restart()
	playing = canvas.world.issue.is_empty()
	if canvas.visible: canvas.grab_focus()

func step_preview() -> void:
	playing = false
	finish_canvas_edit()
	canvas.step_preview()
	update_preview_ui()

func undo_edit() -> void:
	inspector_dirty = true
	session.undo()

func redo_edit() -> void:
	inspector_dirty = true
	session.redo()

func restart() -> void:
	playing = false
	accumulator = 0
	canvas.reset_preview()
	preview_selection = _preview_selection_key()
	hp_slider.set_value_no_signal(canvas.world.hp)

func _preview_selection_key() -> String:
	return "%s/%s/%d/%d/%s" % [collection, selected_id, phase_index, segment_index, str(level_test_from_selected)]

func toggle_play() -> void:
	if not canvas.world.issue.is_empty(): message(canvas.world.issue); return
	if canvas.world.completed: restart()
	if canvas.edit_mode != "none": finish_canvas_edit()
	playing = not playing
	if canvas.visible: canvas.grab_focus()
	update_preview_ui()

func open_curve(scope: Array, key: String) -> void:
	if current() == null: curve_panel.hide(); return
	curve_scope = scope; curve_key = key
	var resource = config_at(scope)
	if resource == null or not resource.get(key) is Curve: curve_panel.hide(); return
	curve_keys = ["orbit_progress_curve"] if key == "orbit_progress_curve" else ["visual_scale_curve", "collision_scale_curve", "progress_curve"]
	curve_selector.clear()
	for name in curve_keys: curve_selector.add_item({"visual_scale_curve": "外观大小", "collision_scale_curve": "碰撞范围", "progress_curve": "路径进度", "orbit_progress_curve": "缩圈进度"}[name])
	curve_selector.select(curve_keys.find(key))
	curve_editor.configure(resource.get(key), 1 if key in ["progress_curve", "orbit_progress_curve"] else 3)
	curve_ceiling.visible = not curve_editor.progress_mode
	curve_ceiling.set_value_no_signal(curve_editor.ceiling)
	curve_editor.time_caption = "移动时间" if key == "orbit_progress_curve" else "阶段时间"
	curve_panel.show()

func request_asset(key: String, scope: Array = []) -> void:
	asset_key = key
	asset_scope = scope.duplicate()
	var filters = {"scene": "*.tscn,*.scn ; 运行场景", "texture": "*.png,*.jpg,*.webp,*.svg ; 贴图", "sound": "*.wav,*.ogg,*.mp3 ; 音频", "music": "*.wav,*.ogg,*.mp3 ; 背景音乐", "visual_scene": "*.tscn,*.scn ; 动画与粒子表现场景"}
	asset_dialog.filters = PackedStringArray(["*.wav,*.ogg,*.mp3 ; 音频" if key.ends_with("_sound") else ("*.tscn,*.scn ; 特效场景" if key.ends_with("_effect") else filters.get(key, "*.tres ; 资源"))])
	if key.ends_with("_clip") or key == "texture" and current() is STGBulletDefinition and current().form in ["moving", "laser"] and scope == ["visual"]:
		asset_dialog.filters = PackedStringArray(["*.gif,*.png,*.jpg,*.webp,*.svg,*.tres ; 贴图 / GIF / 帧动画"])
	elif key.ends_with("_particles"): asset_dialog.filters = PackedStringArray(["*.tscn,*.scn ; 粒子场景"])
	asset_dialog.popup_centered_ratio(0.65)

func assign_asset(path: String) -> void:
	var localized = ProjectSettings.localize_path(path)
	if not localized.begins_with("res://"):
		message("请先把资源放入当前 Godot 项目，并等待编辑器导入完成。")
		return
	if asset_key.ends_with("_clip") or asset_key == "texture" and current() is STGBulletDefinition and asset_scope == ["visual"]:
		_assign_texture_stage(localized)
		return
	var resource = load(localized)
	if resource == null:
		message("资源无法加载，请先把美术或音频放进项目目录。")
		return
	if not _asset_type_matches(resource):
		message("资源类型不符合当前字段。")
		return
	if asset_key == "visual_scene" and current() is STGBulletDefinition:
		inspector_dirty = true
		edit_configuration([], func(target, _project): target.visual_scene = resource; target.visual_animation = "")
		return
	edit_path(asset_scope, asset_key, resource, true)

func _assign_texture_stage(path: String) -> void:
	var resource: Resource
	if path.get_extension().to_lower() == "gif":
		var imported = load("res://addons/stg_maker/authoring/gif_import.gd").new().load_clip(path)
		if not imported.issue.is_empty(): message(imported.issue); return
		resource = imported.clip
	else: resource = load(path)
	if not resource is Texture2D and not resource is SpriteFrames: message("请选择静态贴图、GIF 或贴图帧动画资源。"); return
	if resource is SpriteFrames and not preload("res://stg/definitions/texture_frames.gd").validate(resource).is_empty(): message("动画帧或帧时长无效。"); return
	var key = asset_key
	inspector_dirty = true
	edit_configuration(asset_scope, func(target, _project):
		if key in ["texture", "run_clip"]:
			target.texture = resource if resource is Texture2D else null
			target.run_clip = resource if resource is SpriteFrames else null
		else:
			var clip = resource as SpriteFrames
			if clip == null:
				clip = SpriteFrames.new()
				clip.set_animation_speed(&"default", 1.0)
				clip.add_frame(&"default", resource, 0.1)
				clip.resource_name = path.get_file()
			target.set(key, clip))

func _asset_type_matches(resource: Resource) -> bool:
	if asset_key.ends_with("_sound"): return resource is AudioStream
	if asset_key.ends_with("_effect") or asset_key.ends_with("_particles"): return resource is PackedScene
	match asset_key:
		"texture": return resource is Texture2D
		"sound", "music": return resource is AudioStream
		"scene", "visual_scene": return resource is PackedScene
	return true

func open_project(path: String) -> bool:
	var error = session.open(path)
	if not error.is_empty():
		message(error)
		return false
	inspector_dirty = true
	navigation.parents.clear()
	library_search.text = ""
	reset_selection()
	if not session.notes.is_empty(): message("\n".join(session.notes))
	return true

func open_game_configuration() -> void:
	if not is_instance_valid(game_project_panel):
		game_project_panel = GameProjectPanel.new()
		add_child(game_project_panel)
		game_project_panel.open_for(self)
	else:
		game_project_panel.popup_centered(Vector2i(1050, 780))

func _exit_tree() -> void:
	session.save_recovery()
	if is_instance_valid(game_project_panel):
		game_project_panel.dispose()

func open_game_library() -> void:
	# 默认游戏引用的战斗库也使用普通项目编辑入口，保存后游戏读取同一资源。
	var game = GameDocument.load_definition(GameProjectPanel.DEFAULT_GAME)
	if not game is STGGameDefinition or game.library == null:
		message("首版游戏缺少资源库。")
		return
	if game.library.resource_path.is_empty() or "::" in game.library.resource_path:
		message("请先在游戏配置中保存，将战斗库保存为独立项目。")
		return
	if open_project(game.library.resource_path):
		switch_collection("levels")

func save_project() -> void:
	if session.file_path.is_empty(): save_dialog.popup_centered_ratio(0.65)
	else: save_to(session.file_path)

func save_to(path: String) -> void:
	var error = session.save(path)
	if not error.is_empty(): message(error)
	else:
		var config = _load_settings()
		config.set_value("files", "last_project", path)
		config.save(settings_path)

func request_export() -> void:
	if current() == null: message("请先选择要导出的资源。"); return
	export_dialog.current_file = current().id + ".tscn"
	export_dialog.popup_centered_ratio(0.65)

func message(text: String) -> void:
	message_dialog.dialog_text = text
	message_dialog.popup_centered(Vector2i(680, 440))

func show_template_description() -> void:
	var resource = current()
	if resource != null and resource.get("description") is String and not resource.description.is_empty():
		message(resource.title + "\n\n" + resource.description)

func set_font_size(value: int, persist: bool = true) -> void:
	font_size = value
	Display.apply(self)
	if persist: _save_display()

func set_ui_scale(value: int, persist: bool = true) -> void:
	ui_scale_percent = value if value in Display.SCALE_OPTIONS else 0
	Display.apply(self)
	if persist: _save_display()

func set_pixel_art(value: bool, persist: bool = true) -> void:
	pixel_art = value
	Display.apply(self)
	if persist: _save_display()

func _save_display() -> void:
	var config = _load_settings()
	config.set_value("display", "font_size", font_size)
	config.set_value("display", "ui_scale_percent", ui_scale_percent)
	config.set_value("display", "pixel_art", pixel_art)
	config.save(settings_path)

func _request_display() -> void:
	if display_queued: return
	display_queued = true
	_update_display.call_deferred()

func _update_display() -> void:
	display_queued = false
	Display.apply(self)

func update_preview_ui() -> void:
	if not is_instance_valid(canvas) or canvas.world == null:
		return
	if level_panel.visible:
		level_timeline.queue_redraw()
	var world = canvas.world
	if is_instance_valid(condition_debug): TimelineTools.update_debug(condition_debug, world)
	_update_play_controls(world)
	_update_combat_status(world)
	edit_bar.visible = canvas.edit_mode != "none" and canvas.visible
	if level_panel.visible and world is STGLevelSimulation and world.definition != null:
		_update_level_status(world)
	edit_hint.text = "正在编辑 · " + EDIT_LABELS.get(canvas.edit_mode, "画布")
	_update_mode_status(world)
	var options = test_menu.get_popup()
	options.set_item_checked(0, show_collision)
	options.set_item_checked(1, sound_enabled)
	WorkspaceNavigation.update_preview_tools(self)

func _update_play_controls(world) -> void:
	if playing:
		play_button.text = "暂停测试"
	elif world.time > STGSimulation.STEP * 2 and not world.completed:
		play_button.text = "继续测试"
	else:
		play_button.text = "开始测试"
	play_button.disabled = current() == null or not world.issue.is_empty()
	play_button.mouse_default_cursor_shape = Control.CURSOR_ARROW if play_button.disabled else Control.CURSOR_POINTING_HAND
	for button in preview_actions:
		button.disabled = play_button.disabled
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
	play_button.tooltip_text = "先在左侧选择资源。" if current() == null else ("配置需要调整：" + world.issue if not world.issue.is_empty() else "运行 / 暂停当前预览；制作数据保持原样。")
	validation_button.visible = not world.issue.is_empty()
	hp_slider.editable = current() is STGBossDefinition and world.issue.is_empty()

func _update_mode_status(world) -> void:
	# 状态是纯显示，控制操作始终在按钮上。画布编辑和测试时钟不会同时推进。
	var color = Style.MUTED
	if not world.issue.is_empty():
		mode_status.text = "状态 · 配置待调整"
		color = Color("ff9aab")
	elif canvas.edit_mode != "none":
		mode_status.text = "编辑 · " + EDIT_LABELS.get(canvas.edit_mode, "画布")
		color = Style.AMBER
	elif playing:
		mode_status.text = "状态 · 测试中"
		color = Style.ACCENT
	elif world.completed:
		mode_status.text = "状态 · 已结束"
	else:
		mode_status.text = "状态 · 已暂停"
	mode_status.add_theme_color_override("font_color", color)

func _update_combat_status(world) -> void:
	Fields.help(preview_status, "当前预览的经过时间、场上攻击数和累计命中次数。\n只显示测试结果，不代表玩家正式游戏存档。")
	if not world.issue.is_empty():
		preview_status.text = "配置需要调整，请查看下方提示。"
		return
	var state = _preview_state(world)
	var suffix = " · " + state if not state.is_empty() else ""
	preview_status.text = "%.2f 秒 · 场上 %d · 命中 %d%s" % [world.time, world.actors.size(), world.hits, suffix]
	if world is STGLevelSimulation:
		preview_status.text += " · 实体 %d" % world.entities.size()

func _preview_state(world) -> String:
	# 完整关卡有自己的进度行；单独测试编队仍在战斗状态行显示关卡状态。
	if world is STGLevelSimulation and not level_panel.visible:
		return world.status()
	if world.boss_player != null:
		return world.boss_player.status()
	return "攻击结束" if world.completed else ""

func _update_level_status(world: STGLevelSimulation) -> void:
	# 只读正式运行器的状态，不在 UI 再判断一次阶段是否结束。
	var progress = "关卡结束" if world.completed else world.segment().title
	if not world.condition_failure.is_empty():
		progress += " · " + world.condition_failure
	elif world.waiting_clear:
		progress += " · " + ("等待清场" if world.segment().exit_rule.condition == "clear" else "等待击败目标")
	if world.waiting_clear:
		var waited = maxf(0, world.segment_elapsed - world.segment().duration)
		progress += "，已等待 %.1f 秒" % waited
	timeline_status.text = "计划进度 %.2f / %.2f s · 实际战斗 %.2f s\n%s" % [world.planned_time(), LevelTiming.total(current()), world.time, progress]
	Fields.help(timeline_status, "计划进度按时间轴推进；实际战斗包含清场等待。\n等待条件满足后才进入下一阶段。\n" + world.status())

func _process(delta: float) -> void: # Godot 回调：固定步长预览，所有运动仍在 runtime。
	if not is_instance_valid(canvas) or canvas.world == null: return
	if playing:
		accumulator += minf(delta, 0.1) * playback_speed
		while accumulator >= STGSimulation.STEP:
			canvas.step_preview()
			accumulator -= STGSimulation.STEP
			if canvas.world.completed or not canvas.world.issue.is_empty():
				playing = false
				break
	else:
		canvas.control_player(minf(delta, 0.1), true)
	update_preview_ui()
	if flow_editor.visible: flow_editor.show_states(canvas.world)
	canvas.queue_redraw()

func show_configuration_issues() -> void:
	ResourceTools.show_issues(self)

func show_resource_usages(collection_name: String = "", resource_id: String = "") -> void:
	ResourceTools.show_usages(self, collection_name, resource_id)

func show_recovery_drafts() -> void:
	DraftRecovery.show_drafts(self)

func enter_flow_branch(index: int) -> void:
	flow_path.append_array(["nodes", boss_flow().index_of(flow_node_id), "children", index])
	flow_node_id = ""
	refresh(true)

func leave_flow_branch() -> void:
	if flow_path.size() < 4: return
	var node_index: int = flow_path[-3]
	flow_path.resize(flow_path.size() - 4)
	var parent = boss_flow()
	flow_node_id = parent.nodes[node_index].id if parent != null and node_index < parent.nodes.size() else ""
	refresh(true)

func repair_document_structure() -> void:
	var kind = collection
	var id = selected_id
	inspector_dirty = true
	session.edit(func(project): Structure.repair(project.find(kind, id), project))

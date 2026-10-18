extends Control
## 成品游戏外壳：菜单、地图、战斗 HUD 和结算。制作工具不参与这条运行链。
const Session = preload("res://stg/runtime/game/session.gd")
const MapView = preload("res://game/world_map.gd")
const PlayerView = preload("res://game/player_view.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
@export var definition: STGGameDefinition
@export var save_path: String = "user://stg_progress_v1.json"
var session: STGGameSession
var selected_location_id: String = ""
var content: VBoxContainer
var battle: VBoxContainer
var combat_surface: Control
var combat_canvas: Node2D
var overlay: CenterContainer
var hud: Label
var header: Label
var status: Label
var accumulator: float = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	_build_layout()
	session = Session.new()
	add_child(session)
	session.simulation_parent = combat_canvas
	session.state_changed.connect(_render)
	session.configure(definition, save_path)
	resized.connect(_fit_battle)

func _build_theme() -> void:
	var ui_theme = Theme.new()
	ui_theme.default_font_size = 19
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	ui_theme.default_font = font
	for type in ["Label", "Button"]:
		ui_theme.set_color("font_color", type, Color("e8eff7"))
	ui_theme.set_color("font_disabled_color", "Button", Color("697a90"))
	ui_theme.set_constant("separation", "VBoxContainer", 18)
	ui_theme.set_constant("separation", "HBoxContainer", 20)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box = StyleBoxFlat.new()
		box.bg_color = {"normal": Color("20334a"), "hover": Color("2c506b"), "pressed": Color("35798c"), "disabled": Color("172336"), "focus": Color("263f56")}[state]
		box.set_corner_radius_all(10)
		box.set_content_margin_all(16)
		box.set_border_width_all(2 if state == "focus" else 1)
		box.border_color = Color("82d8ec") if state == "focus" else Color("34506d")
		ui_theme.set_stylebox(state, "Button", box)
	theme = ui_theme

func _build_layout() -> void:
	var background = ColorRect.new()
	background.color = Color("0d1625")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var layout = VBoxContainer.new()
	margin.add_child(layout)
	var top = HBoxContainer.new()
	layout.add_child(top)
	header = _label("", 25)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(header)
	top.add_child(_label("飞行射击 · 世界航线", 16, Color("7c9bb9")))
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	battle = VBoxContainer.new()
	battle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(battle)
	var bar = HBoxContainer.new()
	battle.add_child(bar)
	hud = _label("", 20)
	hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hud)
	bar.add_child(_button("暂停 / Esc", func(): session.toggle_pause()))
	combat_surface = Control.new()
	combat_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	combat_surface.clip_contents = true
	battle.add_child(combat_surface)
	var canvas_background = ColorRect.new()
	canvas_background.color = Color("09101b")
	canvas_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_surface.add_child(canvas_background)
	combat_canvas = Node2D.new()
	combat_surface.add_child(combat_canvas)
	overlay = CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_surface.add_child(overlay)
	combat_surface.resized.connect(_fit_battle)
	battle.add_child(_label("WASD / 方向键移动    空格 / J 射击    Shift 慢速移动    Esc 暂停", 16, Color("8fa8c0")))
	status = _label("", 16, Color("99aec3"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)

func _render() -> void:
	if session == null:
		return
	accumulator = 0
	header.text = definition.title if definition != null else "STGMaker"
	var in_battle = session.state in ["battle", "paused", "result"]
	content.visible = not in_battle
	battle.visible = in_battle
	_clear(content)
	_clear(overlay)
	status.text = session.progress.issue
	match session.state:
		"menu": _menu()
		"map": _map()
		"battle":
			var view = PlayerView.new()
			view.session = session
			if session.simulation.get_node_or_null("PlayerView") == null:
				view.name = "PlayerView"
				session.simulation.add_child(view)
			else:
				view.free()
		"paused": _pause_panel()
		"result": _result_panel()
		"error":
			content.add_child(_label("游戏资源需要检查", 30))
			var error = _label(session.issue, 18, Color("ffc38a"))
			error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(error)
	if session.progress.write_blocked and session.state in ["menu", "map"]:
		content.add_child(_button("备份损坏存档并保存当前进度", _repair_save))
	_fit_battle.call_deferred()

func _menu() -> void:
	var center = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 600
	center.add_child(panel)
	panel.add_child(_label("起飞，开始你的航线", 42))
	panel.add_child(_label("选择地图入口，挑战敌人，击败 Boss。\n首次通关可获得奖励，并解锁下一段航线。", 20, Color("a5bed7")))
	panel.add_child(_button("进入世界地图", func(): session.show_map()))
	panel.add_child(_button("退出游戏", func(): get_tree().quit()))
	panel.add_child(_label("进度自动保存   ·   已通关 %d 处   ·   货币 %d" % [session.progress.completed.size(), session.progress.currency], 17, Color("7f9cb6")))

func _map() -> void:
	if selected_location_id.is_empty() or definition.world.find(selected_location_id) == null:
		selected_location_id = definition.start_location_id
	var top = HBoxContainer.new()
	content.add_child(top)
	var heading = _label("世界地图", 32)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(_label("货币  %d" % session.progress.currency, 21, Color("ffd58a")))
	top.add_child(_button("返回菜单", func(): session.show_menu()))
	content.add_child(_label("点击已开放的地点查看关卡，再从右侧开始挑战。连线表示解锁关系。", 17, Color("95afc7")))
	var row = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var map = MapView.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(520, 320)
	row.add_child(map)
	map.configure(definition.world, session.progress, selected_location_id)
	map.location_selected.connect(func(identifier): selected_location_id = identifier; _render())
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 300
	row.add_child(side)
	var location = definition.world.find(selected_location_id)
	side.add_child(_label("当前选择", 16, Color("7899b9")))
	side.add_child(_label(location.title, 28))
	var description = _label(location.description, 19, Color("b2c7da"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 300
	side.add_child(description)
	side.add_child(_label("首次通关奖励  %d" % location.reward, 18, Color("ffd58a")))
	var completed = session.progress.completed.has(location.id)
	side.add_child(_label("已通关 · 再次挑战不重复发奖" if completed else "尚未通关", 16, Color("8abbb1")))
	var start = _button("再次挑战" if completed else "开始挑战", func(): session.enter_location(selected_location_id))
	start.disabled = not session.progress.is_unlocked(location)
	side.add_child(start)
	side.add_child(_label("战斗操作\nWASD / 方向键：移动\n空格 / J：持续射击\nShift：慢速移动\nEsc：暂停", 17, Color("8fa8c0")))

func _pause_panel() -> void:
	var panel = _overlay_panel("战斗已暂停")
	panel.add_child(_button("继续战斗", func(): session.toggle_pause()))
	panel.add_child(_button("重新挑战", func(): session.retry()))
	panel.add_child(_button("返回世界地图", func(): session.return_to_map()))

func _result_panel() -> void:
	var victory: bool = session.result.victory
	var panel = _overlay_panel("航线完成" if victory else "挑战失败")
	panel.add_child(_label("用时 %.1f 秒" % session.result.elapsed, 19))
	if victory:
		panel.add_child(_label("首次通关奖励 +%d" % session.result.reward if session.result.reward > 0 else "已记录通关 · 本次为重复挑战", 18, Color("ffd58a")))
	else:
		panel.add_child(_label("调整走位，保持射击，再试一次。", 18, Color("a6bdd2")))
	panel.add_child(_button("返回世界地图", func(): session.return_to_map()))
	panel.add_child(_button("重新挑战", func(): session.retry()))

func _overlay_panel(title: String) -> VBoxContainer:
	var background = PanelContainer.new()
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.10, 0.17, 0.97)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(28)
	box.set_border_width_all(1)
	box.border_color = Color("45647c")
	background.add_theme_stylebox_override("panel", box)
	overlay.add_child(background)
	var panel = VBoxContainer.new()
	panel.custom_minimum_size.x = 390
	background.add_child(panel)
	panel.add_child(_label(title, 32))
	return panel

func _process(dt: float) -> void:
	if session == null or session.simulation == null:
		return
	if session.state == "battle":
		var movement = Vector2(float(_pressed(KEY_D, KEY_RIGHT)) - float(_pressed(KEY_A, KEY_LEFT)), float(_pressed(KEY_S, KEY_DOWN)) - float(_pressed(KEY_W, KEY_UP)))
		movement = movement.normalized()
		if Input.is_physical_key_pressed(KEY_SHIFT):
			movement *= 0.4
		var firing = _pressed(KEY_SPACE, KEY_J)
		accumulator += minf(dt, 0.1)
		while accumulator >= STGSimulation.STEP and session.state == "battle":
			session.advance(STGSimulation.STEP, movement, firing, _pressed(KEY_X, KEY_K))
			accumulator -= STGSimulation.STEP
	hud.text = "%s    生命 %d / %d    用时 %.1fs" % [definition.world.find(session.location_id).title, session.health, definition.player.max_health, session.elapsed]
	status.text = session.progress.issue if not session.progress.issue.is_empty() else _battle_objective()

func _battle_objective() -> String:
	if session.state == "result":
		return "通关进度已保存" if session.result.victory else "返回地图或重新挑战"
	var segment = session.simulation.segment()
	var objective = "继续飞行"
	if segment.exit_rule.mode != "time":
		objective = {"clear": "清理本航段的敌人", "defeat_all": "击败本航段所有敌人", "defeat_target": "击败指定目标"}[segment.exit_rule.condition]
	return "当前航段：%s    任务：%s" % [segment.title, objective]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		session.toggle_pause()
		get_viewport().set_input_as_handled()

func _fit_battle() -> void:
	if combat_canvas == null:
		return
	var fitted = CombatSpace.fit_screen(Rect2(Vector2.ZERO, combat_surface.size))
	combat_canvas.position = fitted.get_center()
	combat_canvas.scale = Vector2.ONE * fitted.size.x / CombatSpace.DESIGN_SIZE.x

func _repair_save() -> void:
	session.progress.archive_corrupt_and_save()
	_render()

func _pressed(first: Key, second: Key) -> bool:
	return Input.is_physical_key_pressed(first) or Input.is_physical_key_pressed(second)

func _label(text: String, font_size: int = 19, color: Color = Color("e8eff7")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.pressed.connect(callback)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

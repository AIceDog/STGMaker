@tool
extends RefCounted
## 工作区只组织界面。选择、展开工具和专注模式不修改制作资源，也不进入撤销历史。
const PreviewTransport = preload("res://addons/stg_maker/ui/preview_transport.gd")
const UI_KEY = "workspace_navigation_ui"

static func bind(host) -> void:
	var layout = host.Layout
	var ui = {}
	for key in ["primary", "game", "enemies", "enemy_library", "behaviors", "attacks", "barrages", "levels", "tools_button", "advanced_panel", "trajectory_button", "project_menu"]:
		ui[key] = layout.node(host, "nav_" + key)
	ui.level_buttons = {}
	for collection in ["levels", "waves", "obstacles"]: ui.level_buttons[collection] = layout.node(host, "nav_" + collection + "_button")
	host.set_meta(UI_KEY, ui)
	for pair in [["library_button", "barrages"], ["boss_button", "bosses"], ["level_button", "levels"], ["bullet_button", "bullets"], ["nav_barrages", "barrages"], ["nav_enemy_library", "bosses"], ["nav_behaviors", "behaviors"], ["nav_levels_button", "levels"], ["nav_waves_button", "waves"], ["nav_obstacles_button", "obstacles"]]:
		layout.press(host, pair[0], func(): host.switch_collection(pair[1]))
	layout.press(host, "nav_game", host.open_game_configuration)
	layout.press(host, "nav_tools_button", func():
		host.set_meta("preview_tools_expanded", not host.get_meta("preview_tools_expanded", false))
		update_preview_tools(host))

static func refresh(host) -> void:
	if not host.has_meta(UI_KEY):
		return
	var ui: Dictionary = host.get_meta(UI_KEY)
	var is_attack = host.collection in ["barrages", "bullets"]
	var is_level = host.collection in ["levels", "waves", "obstacles"]
	host.library_button.button_pressed = is_attack
	host.boss_button.button_pressed = host.collection in ["bosses", "behaviors"]
	host.level_button.button_pressed = is_level
	host.bullet_button.button_pressed = host.collection == "bullets"
	ui.attacks.visible = is_attack
	ui.enemies.visible = host.collection in ["bosses", "behaviors"]
	ui.enemy_library.button_pressed = host.collection == "bosses"
	ui.behaviors.button_pressed = host.collection == "behaviors"
	ui.barrages.button_pressed = host.collection == "barrages"
	ui.levels.visible = is_level
	for collection in ui.level_buttons:
		ui.level_buttons[collection].button_pressed = host.collection == collection
	var resource = host.current()
	var has_description = resource != null and (resource is STGBulletDefinition or resource is STGBarrageSkill or resource is STGBossDefinition) and not resource.description.is_empty()
	ui.project_menu.get_popup().set_item_disabled(ui.project_menu.get_popup().get_item_index(9), not has_description)
	_apply_focus(host)

static func update_preview_tools(host) -> void:
	if not host.has_meta(UI_KEY):
		return
	var ui: Dictionary = host.get_meta(UI_KEY)
	if not ui.has("advanced_panel"):
		return
	var expanded: bool = host.get_meta("preview_tools_expanded", false)
	ui.advanced_panel.visible = expanded
	ui.tools_button.text = "收起工具 ▴" if expanded else "测试工具 ▾"
	host.hp_row.visible = expanded and host.collection == "bosses" and host.current() != null
	if ui.has("trajectory_button"):
		ui.trajectory_button.visible = host.collection == "barrages"
		ui.trajectory_button.set_pressed_no_signal(host.show_trajectories)
	PreviewTransport.update(host)

static func toggle_focus(host) -> void:
	host.set_meta("focused_workspace", not host.get_meta("focused_workspace", false))
	_apply_focus(host)
	host.Display.apply(host)

static func _apply_focus(host) -> void:
	var focused: bool = host.get_meta("focused_workspace", false)
	host.Layout.node(host, "LibraryPanel").visible = not focused
	host.Layout.node(host, "InspectorPanel").visible = not focused

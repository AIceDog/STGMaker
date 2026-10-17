@tool
extends RefCounted
## 工作区只组织界面。选择、展开工具和专注模式不修改制作资源，也不进入撤销历史。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const PreviewTransport = preload("res://addons/stg_maker/ui/preview_transport.gd")
const UI_KEY = "workspace_navigation_ui"

static func build_main(host, parent: Node) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	host.library_button = F.button(row, "招式", func(): host.switch_collection("barrages"), "navigation")
	host.boss_button = F.button(row, "敌人", func(): host.switch_collection("bosses"), "navigation")
	host.level_button = F.button(row, "关卡", func(): host.switch_collection("levels"), "navigation")
	var game = F.button(row, "游戏", host.open_game_configuration, "navigation")
	game.tooltip_text = "打开游戏配置，组织主角、世界地图与关卡入口，并完整试玩或导出游戏。制作库与游戏配置分别保存。"
	host.library_button.tooltip_text = "制作与预览招式；素材只负责外观和碰撞"
	host.boss_button.tooltip_text = "敌人 / Boss 的行为、移动与攻击"
	host.level_button.tooltip_text = "关卡时间轴、出场编队与障碍"
	for button in [host.library_button, host.boss_button, host.level_button]:
		button.toggle_mode = true
	host.set_meta(UI_KEY, {"primary": row, "game": game})

static func build_library(host, parent: Node) -> void:
	var ui: Dictionary = host.get_meta(UI_KEY)
	var attacks = HBoxContainer.new()
	parent.add_child(attacks)
	var barrages = F.button(attacks, "招式库", func(): host.switch_collection("barrages"), "navigation")
	F.help(barrages, "浏览并编辑当前项目的攻击招式；配置发射、运动与生命周期；组合由敌人行为流程安排。")
	host.bullet_button = F.button(attacks, "子弹素材", func(): host.switch_collection("bullets"), "navigation")
	host.bullet_button.tooltip_text = "管理共享外观与碰撞；修改后所有引用处同步"
	var enemies = HBoxContainer.new()
	parent.add_child(enemies)
	var enemy_library = F.button(enemies, "敌人库", func(): host.switch_collection("bosses"), "navigation")
	var behaviors = F.button(enemies, "行为子流程", func(): host.switch_collection("behaviors"), "navigation")
	for button in [enemy_library, behaviors]: button.toggle_mode = true
	ui.merge({"enemies": enemies, "enemy_library": enemy_library, "behaviors": behaviors})
	var levels = HFlowContainer.new()
	parent.add_child(levels)
	var level_buttons = {}
	for pair in [["关卡库", "levels"], ["编队", "waves"], ["障碍", "obstacles"]]:
		var button = F.button(levels, pair[0], func(): host.switch_collection(pair[1]), "navigation")
		var explanations = {"levels": "编辑关卡阶段、出场事件和推进条件；编队和障碍是关卡引用的素材。", "waves": "编辑可复用的出场数量、排列与生成间隔；不在这里设置敌人的攻击行为。", "obstacles": "编辑可复用障碍的外观、碰撞和生命周期；通过编队或关卡事件安排出场。"}
		F.help(button, explanations[pair[1]])
		button.toggle_mode = true
		level_buttons[pair[1]] = button
	barrages.toggle_mode = true
	host.bullet_button.toggle_mode = true
	ui.merge({"attacks": attacks, "barrages": barrages, "levels": levels, "level_buttons": level_buttons}, true)

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

static func build_preview_tools(host, parent: Node) -> void:
	var ui: Dictionary = host.get_meta(UI_KEY)
	var button = F.button(parent, "测试工具 ▾", func():
		host.set_meta("preview_tools_expanded", not host.get_meta("preview_tools_expanded", false))
		update_preview_tools(host))
	button.tooltip_text = "展开或收起倍速、单步、判定显示、声音与 Boss 测试血量；这些选项只影响预览，不修改游戏配置。"
	ui.tools_button = button

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
	host.library_panel.get_parent().visible = not focused
	host.inspector_scroll.get_parent().get_parent().visible = not focused

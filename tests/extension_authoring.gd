extends SceneTree
## 真实控件接入验收；使用实际渲染器，截图用于检查新增模块分组的布局。
const Studio = preload("res://addons/stg_maker/ui/studio_workspace.gd")
const GamePanel = preload("res://addons/stg_maker/ui/game_project_panel.gd")
var checks: int = 0
var failures: int = 0
var studio

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func frames(count: int = 4) -> void:
	for frame in count: await process_frame
func controls(parent: Node) -> Array:
	var result: Array = []
	for child in parent.get_children(): result.append(child); result.append_array(controls(child))
	return result
func field(parent: Node, caption: String, type: String):
	for node in controls(parent):
		if node is Label and node.text == caption:
			var siblings = node.get_parent().get_children()
			var index = siblings.find(node)
			if index + 1 < siblings.size() and siblings[index + 1].is_class(type): return siblings[index + 1]
	return null
func choose(parent: Node, caption: String, text: String) -> bool:
	var selector = field(parent, caption, "OptionButton")
	if selector == null: return false
	for index in selector.item_count:
		if selector.get_item_text(index) == text:
			selector.select(index)
			selector.item_selected.emit(index)
			return true
	return false

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://extension_authoring.cfg"
	root.add_child(studio)
	await frames()
	check(studio.size.x >= 1400 and studio.size.y >= 890, "real editor scene occupies capture viewport")
	check(studio.open_project("res://game/content/modular_example/library.tres"), "split example opens through normal editor")
	studio.switch_collection("barrages")
	studio.selected_id = "modular_spiral"
	studio.refresh(true)
	await frames()
	check(field(studio.inspector, "发射模式 / 模块", "OptionButton") != null, "emission has shared extension picker")
	var amount = field(studio.inspector, "弹丸数量", "SpinBox")
	check(amount != null, "nested directory extension metadata generates editable fields")
	if amount != null: amount.value = 19
	await frames()
	check(studio.fire_pattern().extension.parameters.count == 19, "emission parameter writes correct asset scope")
	studio.session.undo()
	await frames()
	check(studio.fire_pattern().extension.parameters.count == 12, "undo restores custom emission parameters")
	check(choose(studio.inspector, "发射模式 / 模块", "使用内置逻辑"), "emission can switch back to built-in logic")
	await frames()
	check(studio.fire_pattern().extension == null, "built-in selection clears only emission binding")
	check(choose(studio.inspector, "发射模式 / 模块", "分批螺旋发射"), "new emission module is discovered recursively")
	await frames()
	studio.inspector_scroll.scroll_vertical = 10000
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/extension_emission_actual.png")
	studio.switch_collection("barrages", "modular_spiral")
	studio.select_inspector_tab(1)
	studio.refresh(true)
	await frames()
	check(field(studio.inspector, "效果模块", "OptionButton") != null and field(studio.inspector, "追加招式", "OptionButton") != null, "effect slot renders content reference picker from metadata")
	check(choose(studio.inspector, "追加招式", "模块示例 · 分批螺旋"), "effect content selector edits dependency ID")
	await frames()
	check(studio.current().projectile.lifecycle.hit_effects[0].parameters.skill == "modular_spiral", "effect parameters belong to selected bullet snapshot")
	studio.session.undo()
	await frames()
	studio.switch_collection("bosses")
	studio.selected_id = "modular_bat"
	studio.phase_index = 0
	studio.flow_node_id = "health_gate"
	studio.inspector_tab = 0
	studio.refresh(true)
	await frames()
	check(field(studio.inspector, "条件模块", "OptionButton") != null, "condition node exposes custom module selector")
	var boss = studio.current()
	for node in boss.phases[0].behavior_flow.nodes:
		if node.kind == "action": studio.flow_node_id = node.id; break
	studio.refresh(true)
	await frames()
	check(field(studio.inspector, "动作模块", "OptionButton") != null and field(studio.inspector, "俯冲时长 s", "SpinBox") != null, "action node exposes custom parameters")
	check(studio.session.project.validate().is_empty(), "UI changes preserve preview-valid configuration")
	var panel = GamePanel.new()
	panel.game_path = "res://game/content/modular_example/game.tres"
	studio.game_project_panel = panel
	studio.add_child(panel)
	panel.open_for(studio)
	await frames()
	check(field(panel.body, "移动控制", "OptionButton") != null and field(panel.body, "射击武器", "OptionButton") != null and field(panel.body, "主动技能", "OptionButton") != null, "game configuration exposes three independent player capability slots")
	var distance = field(panel.body, "闪移距离", "SpinBox")
	check(distance != null, "player module parameters render from the same metadata form")
	if distance != null: distance.value = 100
	await frames()
	check(panel.game.player.ability.parameters.distance == 100 and panel.dirty(), "player extension edits enter game undo history")
	panel.undo()
	await frames()
	check(panel.game.player.ability.parameters.distance == 75, "game undo restores extension binding parameters")
	var restored_distance = field(panel.body, "闪移距离", "SpinBox")
	if restored_distance != null: panel.body.get_parent().ensure_control_visible(restored_distance)
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/extension_player_actual.png")
	panel.dispose()
	studio.game_project_panel = null
	studio.free()
	await frames()
	print("EXTENSION AUTHORING RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

extends SceneTree
## 制作职责的真实控件验收：静态素材独立编辑、显式贴图、共享引用与基础属性布局。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Section = preload("res://addons/stg_maker/ui/form_section.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func settle() -> void:
	for i in 6: await process_frame
func find(node: Node, predicate: Callable):
	if predicate.call(node): return node
	for child in node.get_children():
		var found = find(child, predicate)
		if found != null: return found
	return null
func all(node: Node, predicate: Callable) -> Array:
	var found = [node] if predicate.call(node) else []
	for child in node.get_children(): found.append_array(all(child, predicate))
	return found
func title(studio, caption: String):
	return find(studio.inspector, func(node): return node is Control and node.get_meta("help_title", "") == caption)
func fields(studio, scope: Array, field: String) -> Array:
	return all(studio.inspector, func(node): return node is Control and node.get_meta("config_scope", []) == scope and node.get_meta("config_field", "") == field)
func button(studio, text: String):
	return find(studio.inspector, func(node): return node is Button and node.text == text)
func choose(selector: OptionButton, text: String) -> void:
	for i in selector.item_count:
		if selector.get_item_text(i) == text:
			selector.select(i)
			selector.item_selected.emit(i)
			return
	check(false, "找不到下拉选项：" + text)

func run() -> void:
	root.size = Vector2i(1600, 1000)
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://authoring_boundary_ui.cfg"
	studio.show_trajectories = false
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	var project = STGProject.create()
	var material = Factory.bullet()
	material.id = "shared_geometry"
	project.bullets.append(material)
	for i in 2:
		var skill = Factory.barrage(material.id)
		skill.id = "geometry_attack_%d" % i
		skill.fire_pattern.count = 1
		skill.fire_pattern.rounds = 1
		project.barrages.append(skill)
	studio.session.project = project
	studio.collection = "bullets"
	studio.selected_id = material.id
	studio.inspected_key = ""
	studio.refresh(true)
	await settle()
	await _test_material_pages(studio)
	await _test_presentation_controls(studio)
	await _test_no_shape_editor(studio)
	await _test_attack_boundary(studio)
	await _test_design_controls(studio)
	await _test_behavior_editing(studio)
	studio.queue_free()
	await settle()
	print("AUTHORING BOUNDARY UI RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_material_pages(studio) -> void:
	check(studio.inspector_tabs.tab_count == 2, "外观碰撞同页，动画粒子独立")
	check(studio.inspector_tabs.get_tab_title(0) == "外观与碰撞" and studio.inspector_tabs.get_tab_title(1) == "粒子 / 扩展", "素材页签明确几何与表现职责")
	var shape = title(studio, "形状")
	check(shape is OptionButton and shape.item_count == 8, "外形包含七种几何与显式贴图")
	check(shape.get_item_text(3) == "三角形" and shape.get_item_text(4) == "自定义多边形", "三角形与多边形独立")
	check(fields(studio, ["visual"], "texture").is_empty(), "几何外形不显示贴图选择按钮")
	choose(shape, "自定义多边形")
	await settle()
	check(studio.current().visual.geometry.polygon_mode == "regular" and studio.current().visual.geometry.sides == 5, "新多边形默认正五边形")
	var sides = fields(studio, ["visual", "geometry"], "sides")[0]
	sides.value = 8
	await settle()
	check(studio.current().visual.geometry.outline().size() == 8, "边数控件改变实际多边形轮廓")
	var size_fields = fields(studio, ["visual", "geometry"], "size")
	size_fields[0].value = 64
	size_fields[1].value = 40
	fields(studio, ["visual", "geometry"], "rotation_degrees")[0].value = 23
	var offsets = fields(studio, ["visual", "geometry"], "offset")
	offsets[0].value = 7
	offsets[1].value = -4
	await settle()
	var geometry = studio.current().visual.geometry
	check(geometry.size == Vector2(64, 40) and geometry.rotation_degrees == 23 and geometry.offset == Vector2(7, -4), "大小、旋转与XY偏移由控件写入同一几何：%s / %s / %s" % [geometry.size, geometry.rotation_degrees, geometry.offset])
	check(studio.current().collision.size == Vector2(20, 20) and studio.current().collision.offset == Vector2.ZERO, "修改外观不隐式改变独立碰撞")
	var tint = find(studio.inspector, func(node): return node is ColorPickerButton)
	tint.color_changed.emit(Color(0.3, 0.5, 0.9, 0.7))
	await settle()
	check(studio.current().visual.color.is_equal_approx(Color(0.3, 0.5, 0.9, 0.7)), "所有外形使用统一颜色和透明度")
	choose(title(studio, "形状"), "贴图")
	await settle()
	check(studio.current().visual.mode == "texture" and not fields(studio, ["visual"], "texture").is_empty(), "只有贴图模式提供图片加载入口")
	studio.asset_key = "texture"
	studio.asset_scope = ["visual"]
	studio.assign_asset("res://icon.svg")
	await settle()
	check(studio.current().visual.texture is Texture2D, "自定义贴图通过正式资源绑定入口写入")
	check(studio.current().visual.geometry.size == Vector2(64, 40) and studio.current().visual.geometry.rotation_degrees == 23, "切换到贴图保留统一局部变换")
	choose(title(studio, "形状"), "三角形")
	await settle()
	check(studio.current().visual.mode == "geometry" and studio.current().visual.texture == null, "切回几何时清除贴图引用，不保留隐式贴图")
	check(fields(studio, ["visual"], "texture").is_empty() and studio.current().visual.geometry.outline().size() == 3, "三角形使用独立三顶点轮廓且无图片入口")
	var collision_section = find(studio.inspector, func(node): return node.get_script() == Section and node.title == "碰撞")
	shape = find(collision_section, func(node): return node is OptionButton and node.get_meta("help_title", "") == "形状")
	check(shape is OptionButton and shape.item_count == 7, "碰撞提供相同几何类型但没有贴图")
	choose(shape, "圆环")
	await settle()
	check(studio.current().collision.kind == "ring" and studio.current().visual.geometry.kind == "triangle", "碰撞与外观类型独立")
	button(studio, "复制当前外观几何").pressed.emit()
	await settle()
	check(studio.current().collision.kind == "triangle" and studio.current().collision.size == Vector2(64, 40), "显式复制操作复制当前几何尺寸")
	check(studio.current().collision != studio.current().visual.geometry, "复制后仍是独立配置资源")
	studio.select_inspector_tab(1)
	await settle()
	check(not fields(studio, [], "visual_scene").is_empty() and title(studio, "飞行方式") == null, "动画粒子页只提供表现绑定")
	for field in ["warning", "fade", "damage", "stages", "on_hit_barrage_id", "sound"]:
		check(not studio.current().get_property_list().any(func(item): return item.name == field), "静态素材不再保存生命周期字段：" + field)

func _test_presentation_controls(studio) -> void:
	studio.select_inspector_tab(1)
	studio.asset_key = "visual_scene"
	studio.asset_scope = []
	studio.assign_asset("res://examples/presentation/pulse_sparks.tscn")
	await settle()
	check(studio.current().visual_scene is PackedScene and studio.canvas.world.actors[0].presentation != null, "表现场景通过正式素材入口绑定并预览")
	choose(title(studio, "播放动画"), "pulse")
	await settle()
	check(studio.current().visual_animation == "pulse", "动画选择写入素材")
	title(studio, "同时显示基础外观").toggled.emit(false)
	await settle()
	check(not studio.current().show_base_visual and studio.current().collision.kind == "triangle", "场景替代基础外观时保留碰撞")
	var clear = fields(studio, [], "visual_scene")[0].get_parent().get_child(-1)
	clear.pressed.emit()
	await settle()
	check(studio.current().visual_scene == null and studio.current().visual_animation.is_empty(), "清除表现场景同时清除其动画选择")
	studio.undo_edit()
	await settle()
	check(studio.current().visual_scene != null and studio.current().visual_animation == "pulse", "场景和动画可作为一次修改完整撤销")
	studio.redo_edit()
	await settle()

func _test_no_shape_editor(studio) -> void:
	studio.select_inspector_tab(0)
	var outlines = PackedVector2Array([Vector2.ZERO, Vector2(0.5, 0), Vector2(0.5, 0.1), Vector2(0.1, 0.1), Vector2(0.1, 0.5), Vector2(0, 0.5)])
	studio.edit_configuration(["visual", "geometry"], func(geometry, _project):
		geometry.kind = "polygon"
		geometry.polygon_mode = "custom"
		geometry.points = outlines)
	await settle()
	check(studio.canvas.handles.is_empty(), "素材预览不再生成几何编辑手柄")
	check(button(studio, "在画面编辑外形") == null and button(studio, "在画面编辑碰撞") == null, "外观碰撞移除画面编辑入口")
	check(studio.current().visual.geometry.points == outlines, "移除编辑器保留素材原有自定义轮廓")
	var sections = all(studio.inspector, func(node): return node.get_script() == Section)
	check(sections.all(func(node): return not node.collapsible), "外观、碰撞与基础参数始终展开")
	for scope in [["visual", "geometry"], ["collision"]]:
		for key in ["size", "offset"]:
			var controls = fields(studio, scope, key)
			check(controls.size() == 2 and controls[0].get_parent() == controls[1].get_parent(), "大小和偏移 XY 位于同一行")
			check(is_equal_approx(controls[0].global_position.y, controls[1].global_position.y), "真实布局中 XY 控件水平对齐")
	var types = studio.get_meta("material_types")
	check(types.get_children().map(func(node): return node.text) == ["全部", "子弹", "激光", "拖尾", "区域"], "素材类型并列展示")
	types.get_child(2).pressed.emit()
	check(studio.asset_list.item_count == 0, "类型筛选不会混入其他素材")
	types.get_child(0).pressed.emit()
	check(studio.asset_list.item_count == 1, "全部筛选恢复当前资源列表")

func _test_attack_boundary(studio) -> void:
	var material_count: int = studio.session.project.bullets.size()
	for attack in studio.session.project.barrages:
		studio.switch_collection("barrages", attack.id)
		await settle()
		check(studio.current().projectile.bullet_id == "shared_geometry", "多个招式保留同一素材引用")
		check(title(studio, "取基准坐标轴") == null and fields(studio, ["fire_pattern"], "offset").size() == 2, "攻击原点仅显示一行 XY 位置偏移")
		check(title(studio, "形状") == null and find(studio.inspector, func(node): return node is ColorPickerButton) == null, "招式不内联编辑形状或颜色")
		check(find(studio.inspector, func(node): return node is Button and (node.text.contains("新建子弹素材") or node.text.contains("发射组"))) == null, "招式没有新建素材或发射组入口")
		check(button(studio, "编辑子弹素材 →") != null, "招式只提供明确的素材编辑跳转")
		check(studio.canvas.world.actors.size() == 1 and studio.canvas.world.actors[0].definition.visual.geometry.size == Vector2(64, 40), "共享素材修改进入所有招式的正式运行预览")
	check(studio.session.project.bullets.size() == material_count, "制作与预览没有生成隐式素材副本")

func _test_design_controls(studio) -> void:
	var original_attack: String = studio.selected_id
	studio.switch_collection("bullets", "shared_geometry")
	root.size = Vector2i(1100, 760)
	studio.set_font_size(24, false)
	await settle()
	for caption in all(studio.inspector, func(node): return node is Label and node.text in ["大小", "局部偏移"]):
		check(caption.autowrap_mode == TextServer.AUTOWRAP_OFF and caption.get_line_count() == 1, "窄窗口大字号下基础标签仍为横排：" + caption.text)
	for scope in [["visual", "geometry"], ["collision"]]:
		for key in ["size", "offset"]:
			var inputs = fields(studio, scope, key)
			check(inputs[0].get_parent() == inputs[1].get_parent() and is_equal_approx(inputs[0].global_position.y, inputs[1].global_position.y), "大字号下 XY 同行")
	studio.set_font_size(0, false)
	root.size = Vector2i(1600, 1000)
	choose(title(studio, "形状"), "贴图")
	await settle()
	check(fields(studio, ["visual"], "spawn_clip").size() == 1 and fields(studio, ["visual"], "hit_clip").size() == 1 and fields(studio, ["visual"], "expire_clip").size() == 1, "四阶段贴图配置直接放在外观页")
	studio.asset_key = "texture"; studio.asset_scope = ["visual"]
	studio.assign_asset("res://tests/fixtures/phase_gif/disposal.gif")
	await settle()
	check(studio.current().visual.run_clip != null and studio.current().visual.texture == null, "选择 GIF 后运行外观只有一份来源")
	check(fields(studio, ["visual"], "texture").is_empty() and fields(studio, ["visual"], "run_clip").size() == 1, "GIF 与静态贴图共用一个运行外观入口")
	studio.asset_key = "run_clip"
	studio.assign_asset("res://icon.svg")
	await settle()
	check(studio.current().visual.run_clip == null and studio.current().visual.texture != null, "同一入口可从 GIF 改回静态图片")
	studio.undo_edit(); await settle()
	check(studio.current().visual.run_clip != null and studio.current().visual.texture == null, "切换来源可完整撤销")
	choose(title(studio, "形状"), "三角形")
	await settle()
	check(studio.current().visual.run_clip == null and fields(studio, ["visual"], "spawn_clip").is_empty(), "切回几何清除贴图动画且不显示动画配置")
	studio.select_inspector_tab(1)
	await settle()
	check(fields(studio, [], "spawn_particles").size() == 1 and fields(studio, [], "run_particles").size() == 1 and fields(studio, [], "hit_particles").size() == 1, "几何子弹仍有三类粒子配置")
	studio.asset_key = "run_particles"; studio.asset_scope = []
	studio.assign_asset("res://examples/presentation/pulse_sparks.tscn")
	await settle()
	check(studio.current().run_particles != null, "粒子字段接受正式场景绑定")
	studio.session.edit(func(project):
		project.bullets.append(Factory.bullet("laser"))
		project.bullets.append(Factory.bullet("trail"))
		project.bosses.append(Factory.boss()))
	studio.switch_collection("barrages", original_attack)
	await settle()
	check(title(studio, "子弹生成位置") != null and title(studio, "攻击原点") == null, "普通子弹使用新的生成位置名称")
	check(fields(studio, ["fire_pattern"], "count").size() == 1, "每轮数量只保留一个编辑入口")
	var count = fields(studio, ["fire_pattern"], "count")[0]
	var section = count.get_parent()
	while section != null and section.get_script() != Section: section = section.get_parent()
	check(section != null and section.title == "发射节奏", "每轮数量归发射节奏")
	choose(title(studio, "发射方式"), "分组发射")
	await settle()
	check(fields(studio, ["fire_pattern"], "group_size").size() == 1 and fields(studio, ["fire_pattern"], "group_interval").size() == 1, "分组模式显示每组数量和组间隔")
	fields(studio, ["fire_pattern"], "group_size")[0].value = 3
	await settle()
	check(studio.current().fire_pattern.group_size == 3, "分组数量通过真实控件提交")
	choose(title(studio, "招式类型"), "激光")
	await settle()
	check(studio.current().kind(studio.session.project) == "laser" and title(studio, "激光生成位置") != null, "激光作为独立类型显示对应位置名称")
	choose(title(studio, "生成模式"), "指定位置生成")
	await settle()
	check(studio.current().projectile.delivery == "position" and title(studio, "攻击中持续时间 s") != null and title(studio, "飞行方式") == null, "定点激光隐藏运动配置并显示攻击中时长")
	var laser_id: String = studio.current().projectile.bullet_id
	studio.switch_collection("bullets", laser_id)
	studio.select_inspector_tab(1); await settle()
	check(fields(studio, [], "spawn_particles").is_empty() and fields(studio, [], "run_particles").is_empty(), "激光不提供普通子弹粒子控件")
	studio.switch_collection("barrages", original_attack)
	choose(title(studio, "招式类型"), "召唤敌人")
	await settle()
	check(title(studio, "召唤的敌人") != null and title(studio, "子弹素材") == null, "召唤是独立类型，只选择敌人")
	choose(title(studio, "生成模式"), "发射出去")
	await settle()
	check(title(studio, "入场速度") != null and title(studio, "入场飞行时间 s") != null, "发射召唤提供入场参数")
	studio.select_inspector_tab(2); await settle()
	check(fields(studio, ["projectile", "lifecycle"], "spawn_effect").size() == 1, "召唤特效在招式中配置")
	studio.select_inspector_tab(0)
	choose(title(studio, "招式类型"), "拖尾")
	await settle()
	check(fields(studio, [], "trail_max_length").size() == 1 and fields(studio, ["fire_pattern"], "count").is_empty() and title(studio, "方向分布") == null, "拖尾页面只显示适用的长度和时间，不复制发射弹道")
	choose(title(studio, "招式类型"), "子弹")
	await settle()
	check(studio.session.project.validate().is_empty(), "四种招式切换后保持正式资源有效")

func _test_behavior_editing(studio) -> void:
	var commands = preload("res://addons/stg_maker/ui/flow_commands.gd")
	var locations = preload("res://addons/stg_maker/authoring/resource_locations.gd")
	var tools = preload("res://addons/stg_maker/ui/resource_tools.gd")
	studio.switch_collection("behaviors")
	studio.Commands.add(studio)
	await settle()
	var flow_id = studio.selected_id
	check(studio.current() is STGBehaviorFlow and studio.flow_editor.visible, "行为子流程有独立资产与同一流程画布")
	commands.add(studio, "parallel")
	await settle()
	var parallel_id = studio.flow_node_id
	check(studio.boss_node().kind == "parallel", "流程工具可创建并行节点")
	button(studio, "＋ 并行分支").pressed.emit()
	await settle()
	check(studio.boss_node().children.size() == 1, "并行分支通过真实按钮保存")
	button(studio, "编辑分支 1 →").pressed.emit()
	await settle()
	check(studio.flow_path.size() == 4 and studio.boss_flow() != studio.current(), "进入并行分支切换编辑路径")
	commands.add(studio, "wait")
	await settle()
	var wait_id = studio.flow_node_id
	fields(studio, studio.boss_node_scope(), "delay")[0].value = 0.125
	await settle()
	check(is_equal_approx(studio.boss_node().delay, 0.125), "分支等待通过控件写入精确相对时间")
	studio.undo_edit()
	await settle()
	check(is_equal_approx(studio.boss_node().delay, 1), "分支内编辑可单独撤销")
	studio.redo_edit()
	await settle()
	check(is_equal_approx(studio.boss_node().delay, 0.125), "分支内编辑可重做")
	commands.add(studio, "attack")
	await settle()
	var attack_scope = studio.boss_node_scope()
	studio.edit_path(attack_scope, "barrage_id", studio.session.project.barrages[0].id, true)
	studio.edit_path(attack_scope, "wait_mode", "immediate", true)
	await settle()
	check(studio.boss_node().kind == "attack" and studio.boss_node().wait_mode == "immediate", "分支释放招式可立即继续")
	var attack_id = studio.flow_node_id
	studio.edit_path(attack_scope, "barrage_id", "missing_attack", true)
	await settle()
	var issues = locations.diagnostics(studio.session.project).filter(func(issue): return issue.id == flow_id and issue.get("scope", []) == attack_scope)
	check(not issues.is_empty(), "并行分支错误保留完整嵌套路径")
	studio.leave_flow_branch()
	await settle()
	check(studio.flow_path.is_empty() and studio.boss_node().id == parallel_id, "返回上级流程恢复并行节点")
	check(tools.navigate(studio, issues[0]), "错误入口可定位嵌套分支")
	await settle()
	check(studio.flow_node_id == attack_id and studio.boss_flow().find(wait_id) != null, "定位恢复正确的子流程和节点")
	studio.undo_edit()
	await settle()
	check(studio.session.project.validate().is_empty(), "修复后嵌套行为与招式引用完整")
	var saved = "user://boundary_behavior_library.tres"
	check(studio.session.save(saved).is_empty(), "行为子流程通过正式事务保存为独立资产")
	check(studio.session.open(saved).is_empty(), "包含并行分支的资源库可重新打开")
	await settle()
	var restored = studio.session.project.find("behaviors", flow_id)
	check(restored != null and restored.find(parallel_id).children[0].find(wait_id).delay == 0.125, "重开保留分支等待参数与关系")

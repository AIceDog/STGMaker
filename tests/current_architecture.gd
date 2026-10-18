extends SceneTree
## 当前架构验收：单一路径、严格格式、生效引用与共有动作生命周期。
# 在全局资源类型编译完成后载入工厂，避免测试脚本的多入口预加载锁住声明类型。
var Factory = load("res://stg/definitions/definition_factory.gd")
const Fixture = preload("res://tests/game_fixture.gd")
const ActionRunner = preload("res://stg/runtime/boss/action_runner.gd")
const Behavior = preload("res://stg/runtime/boss/behavior_context.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const Commands = preload("res://addons/stg_maker/ui/commands.gd")
const Documents = preload("res://addons/stg_maker/authoring/document_loader.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	_test_public_lifecycle()
	_test_effective_references()
	_test_strict_format()
	_test_single_implementation()
	_test_converted_assets()
	print("CURRENT ARCHITECTURE RESULT: %d checks, %d failures" % [checks, failures])
	for frame in 8: await process_frame
	quit(1 if failures else 0)

func _declaration() -> STGExtensionDefinition:
	var definition = STGExtensionDefinition.new()
	definition.kind = "action"
	definition.id = "test_animated_action"
	definition.implementation = load("res://tests/fixtures/animated_action.gd")
	return definition

func _world():
	var game = Fixture.create()
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(game.library, "barrages", game.library.barrages[0].id)
	world.clear_attacks()
	return world

func _visual() -> PackedScene:
	var visual = Node2D.new()
	var animator = AnimationPlayer.new()
	visual.add_child(animator)
	animator.owner = visual
	var library = AnimationLibrary.new()
	var clip = Animation.new()
	clip.length = 1
	library.add_animation("probe", clip)
	animator.add_animation_library("", library)
	var packed = PackedScene.new()
	packed.pack(visual)
	visual.free()
	return packed

func _test_public_lifecycle() -> void:
	var world = _world()
	world.boss_presentation.configure(_visual())
	var behavior = Behavior.new()
	behavior.world = world
	behavior.active_node_id = "probe"
	var events: Array = []
	world.boss_action_event.connect(func(_id, event): events.append(event))
	var action = Factory.action()
	action.extension = STGExtensionBinding.create(_declaration())
	action.duration = 1
	var runner = ActionRunner.new()
	runner.start(behavior, action)
	var instance = runner.session.implementation
	check(not runner.tick(behavior, 0.1), "脚本动作能跨帧执行")
	check(is_equal_approx(world.boss_presentation.animation_player.current_animation_position, 0.1), "脚本动作的动画由共同宿主推进")
	check(runner.tick(behavior, 0.1), "脚本动作可自行完成")
	runner.cancel(behavior)
	check(instance.cancellations == ["completed"] and events.count("completed") == 1 and not events.has("cancelled"), "脚本完成通知和清理只执行一次")
	check(not behavior.action_running and world.action_completed_at.has("probe"), "共同宿主记录完成状态")
	events.clear()
	action.extension = null
	action.windup = 0
	action.duration = 0.1
	action.recovery = 0
	action.presentation.active_animation = "probe"
	runner = ActionRunner.new()
	runner.start(behavior, action)
	runner.tick(behavior, 0.01)
	runner.tick(behavior, 0.05)
	check(world.boss_presentation.animation_player.current_animation_position > 0, "内置动作使用相同表现时钟")
	for step in 20:
		if runner.tick(behavior, 0.01): break
	runner.cancel(behavior)
	check(events.count("completed") == 1 and not events.has("cancelled"), "内置动作也只上报一次完成")
	world.free()

func _test_effective_references() -> void:
	var game = Fixture.create()
	var project = game.library
	var definition = _declaration()
	definition.fields.assign([{"name": "style", "type": "resource_id", "collection": "bullets", "default": project.bullets[0].id}])
	var action = Factory.action()
	action.extension = STGExtensionBinding.create(definition)
	action.presentation.active_animation = "inactive_builtin_clip"
	action.attack.enabled = true
	action.attack.barrage_id = "inactive_builtin_skill"
	project.bosses[0].phases[0].behavior_flow = Factory.flow([action])
	project.barrages.clear()
	check(not Commands.removal_issue(project, "bullets", project.bullets[0].id).is_empty(), "删除保护遍历全部来源，识别敌人脚本对弹丸的引用")
	check(References.collect(project.bosses[0]).size() == 1, "未启用的内置动作草稿不进入引用图")
	check(project.validate().is_empty(), "未启用的动画及招式不干扰脚本动作校验")
	var compiled = Compiler.compile_library(project, [{"collection": "bosses", "id": project.bosses[0].id}])
	check(compiled.issue.is_empty() and compiled.library.bullets.size() == 1, "编译使用同一生效引用图")
	var binding = action.extension
	binding.parameters.style = "missing"
	check(not project.validate().is_empty(), "生效的扩展引用丢失会在预览前报错")

func _test_strict_format() -> void:
	var project = Fixture.create().library
	var path = "user://current_format_probe.tres"
	check(ResourceSaver.save(project, path) == OK and Documents.library(path).issue.is_empty(), "当前格式可直接保存和读取")
	project.schema_version = 10
	ResourceSaver.save(project, path)
	check(not Documents.library(path).issue.is_empty(), "加载器拒绝其他版本且不转换")
	check(not Compiler.compile_library(project, [{"collection": "bullets", "id": project.bullets[0].id}]).issue.is_empty(), "编译器拒绝其他版本")
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, "bullets", project.bullets[0].id)
	check(not world.issue.is_empty(), "运行器同样拒绝其他版本")
	world.free()

func _test_single_implementation() -> void:
	for path in ["stg/runtime/boss/action_executor.gd", "stg/runtime/boss/builtin_action_logic.gd", "stg/runtime/modules/action.gd", "stg/runtime/extensions/motion_session.gd", "stg/runtime/extensions/motion_extension.gd", "stg/runtime/extensions/motion_context.gd"]:
		check(not FileAccess.file_exists("res://" + path), "不保留被替换的入口：" + path)
	for path in ["tools/migrations", "stg/definitions/legacy"]:
		check(not DirAccess.dir_exists_absolute("res://" + path), "转换工具和历史模型不在新工程：" + path)
	for path in ["dependency_policy.gd", "script_dependencies.gd"]:
		check(not FileAccess.file_exists("res://stg/definitions/" + path), "构建专用检查不进入运行框架")
	for path in ["emission.gd", "emission_geometry.gd", "emission_motion.gd", "skill_movement.gd"]:
		check(not FileAccess.file_exists("res://stg/definitions/" + path), "旧发射组与素材运动继承入口已删除：" + path)
	for path in ["attack_editing.gd", "attack_structure.gd", "attack_group_bar.gd", "emission_inspector.gd"]:
		check(not FileAccess.file_exists("res://addons/stg_maker/ui/" + path), "旧编辑与分组入口已删除：" + path)
	check(not Factory.has_method("skill_preview"), "没有把招式隐式包装成敌人的旧预览入口")
	var attack = Factory.barrage("material")
	var material = Factory.bullet()
	var attack_fields = attack.get_property_list().map(func(field): return field.name)
	var material_fields = material.get_property_list().map(func(field): return field.name)
	check("fire_pattern" in attack_fields and "projectile" in attack_fields and not "emissions" in attack_fields, "招式只有一份发射规则和弹体配置")
	for name in ["stages", "warning", "fade", "damage", "hit_effects", "on_hit_barrage_id", "on_expire_barrage_id", "sound"]:
		check(not name in material_fields, "静态素材不保存攻击行为：" + name)
	var context = STGCommandContext.new()
	check(context.has_method("emit_projectile") and context.has_method("play_behavior") and not context.has_method("emit_bullet"), "公开命令只接收明确的招式或行为引用")

func _test_converted_assets() -> void:
	for path in ["res://presets/demo.tres", "res://presets/enemy_library.tres", "res://presets/flytiger_enemies.tres", "res://presets/flytiger_bosses.tres", "res://presets/level_demo.tres", "res://presets/timeline_demo.tres", "res://examples/shared/enemy_library.tres", "res://examples/shared/level_demo.tres", "res://examples/shared/timeline_demo.tres", "res://game/content/first_library.tres", "res://game/content/modular_example/library.tres"]:
		var loaded = Documents.library(path)
		check(loaded.issue.is_empty(), "转换资产可读取：" + path)
		if loaded.resource != null: check(loaded.resource.validate().is_empty(), "转换资产的当前引用合法：" + path)
	for path in ["res://game/content/first_game.tres", "res://game/content/modular_example/game.tres"]:
		var game: STGGameDefinition = load(path)
		check(game != null and game.validate().is_empty(), "转换游戏配置可执行：" + path)
	var recovered = DirAccess.open("res://game/content/recovered")
	if recovered == null: return
	for file in recovered.get_files():
		var path = "res://game/content/recovered/" + file
		if file.ends_with(".tres"):
			var loaded = Documents.library(path)
			check(loaded.issue.is_empty(), "本机保存内容已经转换：" + file)
			if loaded.resource != null: check(loaded.resource.validate().is_empty(), "本机保存内容的引用完整：" + file)
		elif file.ends_with(".tscn"):
			var packed: PackedScene = load(path)
			var node = packed.instantiate()
			check(node.library.schema_version == STGProject.VERSION and node.library.validate().is_empty(), "本机预制场景已引用当前资源库：" + file)
			node.free()

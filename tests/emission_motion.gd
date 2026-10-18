extends SceneTree
## 招式显式拥有飞行过程；覆盖隔离、扩展、变形/后继与构建依赖闭包。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Builder = preload("res://addons/stg_maker/build/project_builder.gd")
const Session = preload("res://addons/stg_maker/ui/session.gd")
const Extension = preload("res://game/extensions/accelerated_straight.tres")
var checks = 0
var failures = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func fixture() -> STGProject:
	var project = STGProject.create()
	var bullet = Factory.bullet(); project.bullets.append(bullet)
	for i in 2:
		var attack = Factory.barrage(bullet.id)
		attack.fire_pattern.count = 2; attack.fire_pattern.rounds = 1; attack.fire_pattern.spread = 0; attack.fire_pattern.angle = 0
		attack.projectile.lifecycle.fade = 0
		attack.projectile.motion_stages[0].duration = 2; attack.projectile.motion_stages[0].speed = 120
		project.barrages.append(attack)
	return project
func simulation(project: STGProject, index: int = 0) -> STGSimulation:
	var world = STGSimulation.new(); root.add_child(world)
	world.reset(project, "barrages", project.barrages[index].id); world.player = Vector2(-10000, -10000)
	check(world.issue.is_empty(), "正式运行器接受招式运动：" + world.issue)
	return world
func run() -> void:
	_test_owned_config_and_copy()
	_test_runtime()
	_test_motion_extension()
	_test_transform_and_events()
	_test_validation_and_compiler()
	_test_compiler_source_isolation()
	print("PROJECTILE MOTION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _test_owned_config_and_copy() -> void:
	var project = fixture()
	var attack = project.barrages[0]
	var other = project.barrages[1]
	check(not attack.projectile.motion_stages.is_empty(), "招式显式保存完整飞行过程，不从素材继承")
	check(attack.projectile.motion_stages[0] != other.projectile.motion_stages[0], "不同招式分别拥有运动配置")
	attack.projectile.motion_stages[0].speed = 300
	check(other.projectile.motion_stages[0].speed == 120, "修改一份招式不影响另一份共用素材的招式")
	var snapshot = project.snapshot()
	check(snapshot.barrages[0].projectile.motion_stages[0].path != attack.projectile.motion_stages[0].path, "快照隔离可编辑运动曲线")
	check(snapshot.bullets[0].scene == project.bullets[0].scene, "快照仍共享只读表现资源")
	var session = Session.new(); session.project = project
	session.edit(func(next): next.barrages[0].projectile.motion_stages[0].speed = 450)
	check(session.project.barrages[0].projectile.motion_stages[0].speed == 450 and attack.projectile.motion_stages[0].speed == 300, "事务隔离源招式配置")
	session.undo(); check(session.project.barrages[0].projectile.motion_stages[0].speed == 300, "撤销恢复运动配置")
	session.redo(); check(session.project.barrages[0].projectile.motion_stages[0].speed == 450, "重做恢复运动编辑")
	var extension_stage = Factory.stage("extension"); extension_stage.extension = STGExtensionBinding.create(Extension)
	extension_stage.extension.parameters = {"initial_speed": 20.0, "acceleration": 80.0}
	attack.projectile.motion_stages.assign([extension_stage]); snapshot = project.snapshot()
	var copied = snapshot.barrages[0].projectile.motion_stages[0]
	check(copied.extension.definition == Extension, "快照共享只读扩展声明")
	copied.extension.parameters.acceleration = 30.0
	check(extension_stage.extension.parameters.acceleration == 80.0, "扩展参数独立复制")
	var destination = "user://projectile_motion_roundtrip.tres"
	check(ResourceSaver.save(project, destination) == OK, "招式运动可保存")
	var loaded = ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE) as STGProject
	check(loaded != null and loaded.validate().is_empty(), "重开后通过当前格式校验")
	check(loaded.barrages[0].projectile.motion_stages[0].extension.parameters.acceleration == 80.0, "序列化保留扩展参数")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
func _test_runtime() -> void:
	var project = fixture(); project.barrages[0].projectile.motion_stages[0].speed = 300
	var first = simulation(project); var second = simulation(project, 1)
	first.step(0.25); second.step(0.25)
	check(first.actors.size() == 2 and second.actors.size() == 2, "单套发射规则创建真实场景实例")
	check(first.actors[0].position.is_equal_approx(first.boss + Vector2(75, 0)), "当前招式速度用于正式运动")
	check(second.actors[0].position.is_equal_approx(second.boss + Vector2(30, 0)), "另一份招式保持独立速度")
	check(first.actors[0].projectile == first.actors[1].projectile, "同一招式的子弹共享只读弹体配置")
	check(first.actors[0].definition == second.actors[0].definition and first.actors[0].definition == project.bullets[0], "两份配置都引用同一份静态素材")
	first.free(); second.free()
func _test_motion_extension() -> void:
	var project = fixture(); var stage = Factory.stage("extension")
	stage.extension = STGExtensionBinding.create(Extension); stage.extension.parameters = {"initial_speed": 20.0, "acceleration": 80.0}; stage.duration = 0.1
	project.barrages[0].projectile.motion_stages.assign([stage])
	var world = simulation(project); world.step(0.02)
	var first = world.actors[0].motion_session; var second = world.actors[1].motion_session
	check(first != second and first.implementation != second.implementation, "每颗子弹持有独立扩展状态")
	check(first.implementation != null and world.actors[0].position.x > world.boss.x, "扩展通过公开运动接口推进")
	world.step(0.1)
	check(first.implementation == null and second.implementation == null and world.actors.is_empty(), "运动到期关闭两份会话并回收")
	world.clear_attacks(); check(first.implementation == null, "重复清屏不重建或重复结束扩展")
	world.free()
	var path = "user://projectile_extension_dependencies.tres"
	check(ResourceSaver.save(project, path) == OK, "扩展运动可序列化供导出")
	var dependencies = Builder._resolve_dependencies({"library.tres": {"text": FileAccess.get_file_as_string(path)}})
	check(dependencies.issue.is_empty() and dependencies.files.has("game/extensions/accelerated_straight.gd"), "扩展实现进入独立成品文件闭包")
	check(not dependencies.files.has("addons/stg_maker/authoring/defaults.gd"), "运行扩展没有编辑器依赖")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func _test_transform_and_events() -> void:
	var project = fixture(); var first = project.barrages[0]; var target = project.barrages[1]
	first.fire_pattern.count = 1
	var wait = Factory.stage("wait"); wait.duration = 0.05
	var transform = Factory.stage("transform"); transform.transform_attack_id = target.id
	first.projectile.motion_stages.assign([wait, transform])
	check(project.validate().is_empty(), "可以变形为引用同一素材的另一份完整招式")
	var world = simulation(project); world.step(0.05)
	var owner = world.barrages[0].owner_id
	check(world.actors.size() == 1 and world.actors[0].projectile == target.projectile, "变形读取目标招式完整配置")
	check(world.actors[0].owner_id == owner and not world.completed, "变形保留归属和完成等待")
	world.step(0.1); check(world.actors[0].position.is_equal_approx(world.boss + Vector2(12, 0)), "变形后按目标招式运动")
	world.free()
	project = fixture(); first = project.barrages[0]; target = project.barrages[1]
	first.fire_pattern.count = 1; target.fire_pattern.count = 1
	first.projectile.motion_stages.assign([wait]); first.projectile.lifecycle.on_expire_barrage_id = target.id
	world = simulation(project); world.step(0.05); owner = world.barrages[0].owner_id; world.step(0.01)
	check(world.actors.size() == 1 and world.actors[0].projectile == target.projectile, "自然到期释放独立后继招式")
	check(world.actors[0].owner_id == owner, "后继招式继承归属")
	world.free()
func _test_validation_and_compiler() -> void:
	var project = fixture(); var projectile = project.barrages[0].projectile
	projectile.motion_stages[0].speed = NAN
	check(not project.validate().is_empty(), "拒绝无效运动数值")
	projectile.motion_stages[0].speed = 100; projectile.motion_stages.append(null)
	check(not project.validate().is_empty(), "拒绝空运动步骤")
	var transform = Factory.stage("transform"); transform.transform_attack_id = project.barrages[1].id
	projectile.motion_stages.assign([transform])
	var compiled = Compiler.compile_library(project, [{"collection": "barrages", "id": project.barrages[0].id}])
	check(compiled.issue.is_empty(), "构建接受变形过程：" + compiled.issue)
	check(compiled.has("library") and compiled.library.find("barrages", project.barrages[1].id) != null, "变形招式进入依赖闭包")
	if compiled.has("library"):
		compiled.library.barrages[0].projectile.motion_stages[0].duration = 3
		check(projectile.motion_stages[0].duration != 3, "构建过程配置隔离源项目")
	transform.transform_attack_id = "missing_transform"
	check("missing_transform" in Compiler.compile_library(project, [{"collection": "barrages", "id": project.barrages[0].id}]).issue, "构建报告丢失的变形引用")
	transform.transform_attack_id = project.barrages[1].id
	project.barrages[1].projectile.lifecycle.on_expire_barrage_id = project.barrages[0].id
	check(not project.validate().is_empty(), "变形与到期后继形成的递归链被拒绝")
func _test_compiler_source_isolation() -> void:
	var project = fixture(); var unused = Factory.bullet(); unused.collision.size = Vector2(-1, -1); project.bullets.append(unused)
	var compiled = Compiler.compile_library(project, [{"collection": "barrages", "id": project.barrages[0].id}])
	check(compiled.issue.is_empty(), "仅校验和编译选中的依赖")
	if not compiled.has("library"): return
	var selected: STGProject = compiled.library
	check(selected.schema_version == STGProject.VERSION and selected.bullets.size() == 1 and selected.barrages.size() == 1, "结果是当前格式最小闭包")
	check(selected.barrages[0].projectile.motion_stages[0].path != project.barrages[0].projectile.motion_stages[0].path, "编译隔离嵌套运动曲线")
	selected.barrages[0].projectile.motion_stages[0].path.set_point_position(1, Vector2(876, 543)); selected.barrages[0].fire_pattern.count = 23
	check(project.barrages[0].projectile.motion_stages[0].path.get_point_position(1) != Vector2(876, 543) and project.barrages[0].fire_pattern.count == 2, "修改编译结果不回写源配置")
	check(project.bullets.size() == 2 and unused.collision.size.x == -1 and selected.find("bullets", unused.id) == null, "裁剪不修改源项目或未选中素材")

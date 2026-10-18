extends SceneTree
## 扩展回归：序列化、实例隔离、生命周期、原有碰撞及真实编辑器控件。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const ConfigCopy = preload("res://stg/definitions/config_copy.gd")
const Studio = preload("res://addons/stg_maker/ui/studio_workspace.gd")
# 声明在实例初始化时加载，避免脚本编译常量与全局 Binding 类型互相持有。
var Example = load("res://game/extensions/accelerated_straight.tres")
var checks = 0
var failures: PackedStringArray = []
var _materials: Dictionary = {}

class TestWorld:
	extends RefCounted
	var player = Vector2(-10000, -10000)
	var boss = Vector2.ZERO
	var player_radius = 4.0
	var hits = 0
	func register_hit(_damage: float) -> void:
		hits += 1
	func present_lifecycle(_sound, _scene, _at: Vector2, _heading: float = 0, _duration: float = 2) -> void:
		pass
	func play_barrage(_id: String, _origin: Vector2, _owner: int, _heading: float) -> void:
		pass

class RecordingMotion:
	extends STGMotionExtension
	var ticks = 0
	var cancellations: PackedStringArray = []
	func tick(_context: STGMotionContext, _dt: float) -> void:
		ticks += 1
	func cancel(reason: String) -> void:
		cancellations.append(reason)

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _bullet(extension = null, parameters: Dictionary = {}) -> STGBarrageSkill:
	if extension == null: extension = Example
	var material = Factory.bullet()
	_materials[material.id] = material
	var bullet = Factory.barrage(material.id)
	bullet.fire_pattern.count = 1; bullet.fire_pattern.rounds = 1; bullet.fire_pattern.angle = 0
	var stage = Factory.stage("wait")
	stage.mode = "extension"
	stage.extension = STGExtensionBinding.create(extension)
	stage.extension.parameters = parameters
	stage.duration = 2
	bullet.projectile.motion_stages[0] = stage
	bullet.projectile.lifecycle.fade = 0
	return bullet

func _actor(bullet: STGBarrageSkill, origin: Vector2 = Vector2.ZERO, angle: float = 0) -> STGBulletActor:
	var actor = STGBulletActor.new()
	root.add_child(actor)
	actor.setup(_materials[bullet.projectile.bullet_id], bullet.projectile, origin, angle, 1)
	return actor

func _recording_definition() -> STGExtensionDefinition:
	var instance = RecordingMotion.new()
	var definition = STGExtensionDefinition.new()
	definition.id = "recording_test"
	definition.implementation = instance.get_script()
	return definition

func _run() -> void:
	_test_validation_and_serialization()
	_test_independent_instances()
	_test_simulation()
	_test_cancellation_and_collision()
	await _test_editor()
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_validation_and_serialization() -> void:
	_expect(Example.validate({}).is_empty(), "extension default metadata validates")
	_expect(not Example.validate({"acceleration": NAN}).is_empty(), "reject non-finite parameter")
	_expect(not Example.validate({"acceleration": 2001.0}).is_empty(), "reject out-of-range parameter")
	_expect(not Example.validate({"initial_speed": "fast"}).is_empty(), "reject wrong parameter type")
	_expect(not Example.validate({"accelaration": 20.0}).is_empty(), "reject unknown parameter name")
	var missing = STGExtensionDefinition.new()
	missing.id = "missing"
	_expect(not missing.validate({}).is_empty(), "reject missing implementation")
	for pair in [["min", Vector2.ZERO], ["max", NAN], ["step", 0], ["step", "fast"], ["default", "fast"]]:
		var malformed = STGExtensionDefinition.new()
		malformed.id = "malformed_metadata"
		malformed.implementation = Example.implementation
		malformed.fields = Example.fields.duplicate(true)
		malformed.fields[0][pair[0]] = pair[1]
		_expect(not malformed.validate({}).is_empty(), "reject malformed field metadata without runtime conversion error: " + pair[0])
	var reversed = STGExtensionDefinition.new()
	reversed.id = "reversed_metadata"
	reversed.implementation = Example.implementation
	reversed.fields = Example.fields.duplicate(true)
	reversed.fields[0].min = 2001.0
	_expect(not reversed.validate({}).is_empty(), "reject reversed parameter range")
	var wrong = STGExtensionDefinition.new()
	wrong.id = "wrong"
	wrong.implementation = preload("res://stg/definitions/config_copy.gd")
	_expect(not wrong.validate({}).is_empty(), "reject script outside motion contract")
	var bullet = _bullet(Example, {"initial_speed": 35.0, "acceleration": 160.0})
	var copy: STGBarrageSkill = ConfigCopy.copy(bullet)
	_expect(copy.projectile.motion_stages[0].extension.definition == Example, "undo snapshot shares immutable extension declaration")
	copy.projectile.motion_stages[0].extension.parameters.acceleration = 40.0
	_expect(bullet.projectile.motion_stages[0].extension.parameters.acceleration == 160.0, "undo snapshot isolates editable extension parameters")
	var path = "user://extension_roundtrip_test.tres"
	_expect(ResourceSaver.save(bullet, path) == OK, "save extension bullet")
	var loaded: STGBarrageSkill = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loaded.projectile.motion_stages[0].extension.parameters == bullet.projectile.motion_stages[0].extension.parameters, "parameters survive save/load")
	_expect(loaded.projectile.motion_stages[0].extension.definition.implementation.resource_path == "res://game/extensions/accelerated_straight.gd", "saved definition retains runtime script dependency")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var project = STGProject.create()
	project.schema_version = STGProject.VERSION
	project.bullets.append(_materials[bullet.projectile.bullet_id])
	project.barrages.append(bullet)
	_expect(project.validate().is_empty(), "project validator accepts motion extension")
	bullet.projectile.motion_stages[0].extension.parameters.acceleration = INF
	_expect(not project.validate().is_empty(), "project validator catches bad extension parameters")

func _test_independent_instances() -> void:
	var bullet = _bullet(Example, {"initial_speed": 100.0, "acceleration": 80.0})
	var world = TestWorld.new()
	var first = _actor(bullet)
	var second = _actor(bullet, Vector2(100, 20), PI / 2)
	first.tick(world, 0.5)
	second.tick(world, 0.25)
	_expect(first.motion_session.implementation != second.motion_session.implementation, "simultaneous bullets have independent extension objects")
	_expect(first.motion_session.context != second.motion_session.context, "simultaneous bullets have independent contexts")
	_expect(first.position.is_equal_approx(Vector2(60, 0)), "accelerated straight uses configured kinematics")
	_expect(second.position.is_equal_approx(Vector2(100, 47.5)), "second bullet keeps its own origin heading and elapsed time")
	first.tick(world, 0.5)
	_expect(first.position.is_equal_approx(Vector2(140, 0)), "first instance advances independently")
	_expect(second.position.is_equal_approx(Vector2(100, 47.5)), "first tick does not alter second instance")
	_expect(bullet.projectile.motion_stages[0].extension.parameters == {"initial_speed": 100.0, "acceleration": 80.0}, "runtime does not mutate serialized parameters")
	first.free()
	second.free()

func _test_simulation() -> void:
	var project = STGProject.create()
	project.schema_version = STGProject.VERSION
	var bullet = _bullet()
	project.bullets.append(_materials[bullet.projectile.bullet_id])
	project.barrages.append(bullet)
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, "barrages", bullet.id)
	_expect(world.issue.is_empty() and world.barrages.size() == 1, "shared simulation loads custom motion attack")
	world.player = Vector2(-10000, -10000)
	var origin: Vector2 = world.boss
	for i in 120: world.step()
	_expect(world.actors[0].position.is_equal_approx(origin + Vector2(160, 0)), "preview/game fixed-step simulation executes custom motion")
	world.free()

func _test_cancellation_and_collision() -> void:
	var world = TestWorld.new()
	var definition = _recording_definition()
	var bullet = _bullet(definition)
	bullet.projectile.motion_stages[0].duration = 0.05
	bullet.projectile.motion_stages.append(Factory.stage("wait"))
	var actor = _actor(bullet)
	actor.tick(world, 0.01)
	var recording = actor.motion_session.implementation
	actor.tick(world, 0.04)
	_expect(recording.cancellations == PackedStringArray(["completed"]), "stage transition cancels extension once")
	actor.stop()
	actor.free()
	_expect(recording.cancellations.size() == 1, "later stop/removal does not duplicate stage cancellation")
	bullet = _bullet(definition)
	bullet.projectile.motion_stages[0].duration = 0.05
	bullet.projectile.lifecycle.fade = 0.5
	actor = _actor(bullet)
	actor.tick(world, 0.01)
	recording = actor.motion_session.implementation
	actor.tick(world, 0.04)
	_expect(actor.fading and recording.cancellations == PackedStringArray(["expired"]), "expiry cancels extension before visual fade")
	actor.tick(world, 0.5)
	_expect(recording.ticks == 2 and recording.cancellations.size() == 1, "fading never ticks ended extension")
	actor.free()
	actor = _actor(_bullet(definition))
	actor.tick(world, 0.01)
	recording = actor.motion_session.implementation
	actor.stop()
	actor.stop()
	_expect(recording.cancellations == PackedStringArray(["stopped"]), "external death/stop cancels exactly once")
	actor.free()
	actor = _actor(_bullet(definition))
	actor.tick(world, 0.01)
	recording = actor.motion_session.implementation
	actor.free()
	_expect(recording.cancellations == PackedStringArray(["removed"]), "world teardown cancels active extension")
	actor = _actor(_bullet(Example, {"initial_speed": 100.0, "acceleration": 0.0}))
	world.player = Vector2(1, 0)
	actor.tick(world, 0.01)
	_expect(world.hits == 1 and not actor.alive and actor.motion_session == null, "custom motion retains built-in collision damage and death lifecycle")
	actor.free()

func _controls(node: Node, kind: String) -> Array:
	var result = []
	if node.is_class(kind): result.append(node)
	for child in node.get_children(): result.append_array(_controls(child, kind))
	return result

func _test_editor() -> void:
	var studio = Studio.new()
	studio.restore_last_project = false
	studio.settings_path = "user://extension_editor_checks.cfg"
	root.add_child(studio)
	for i in 3: await process_frame
	studio.switch_collection("barrages")
	studio.select_inspector_tab(0)
	studio.edit_path(["projectile", "motion_stages", 0], "mode", "extension", true)
	for i in 3: await process_frame
	var selector: OptionButton
	for control in _controls(studio.inspector, "OptionButton"):
		for i in control.item_count:
			if control.get_item_text(i) == Example.title:
				selector = control
				selector.select(i)
				selector.item_selected.emit(i)
				break
		if selector != null: break
	_expect(selector != null, "editor discovers installed extension without opening script")
	for i in 3: await process_frame
	_expect(studio.motion_stage().extension.definition == Example, "extension picker writes declared Resource")
	var spin: SpinBox
	for control in _controls(studio.inspector, "SpinBox"):
		if control.tooltip_text == "正数加速，负数减速；减速到零后会反向移动。": spin = control
	_expect(spin != null, "metadata builds editable acceleration field and help")
	if spin != null: spin.value = 160.0
	for i in 3: await process_frame
	_expect(is_equal_approx(studio.motion_stage().extension.parameters.get("acceleration", 0), 160), "visible field writes serialized configuration")
	_expect(studio.session.project.validate().is_empty(), "edited extension remains valid for preview and game")
	studio.session.undo()
	for i in 3: await process_frame
	_expect(is_equal_approx(studio.motion_stage().extension.parameters.get("acceleration", 0), 80), "undo restores extension parameters")
	studio.session.redo()
	for i in 3: await process_frame
	_expect(is_equal_approx(studio.motion_stage().extension.parameters.get("acceleration", 0), 160), "redo restores extension parameters")
	var malformed = STGExtensionDefinition.new()
	malformed.id = "malformed_ui_metadata"
	malformed.implementation = Example.implementation
	malformed.fields = Example.fields.duplicate(true)
	malformed.fields[0].min = Vector2.ZERO
	studio.edit_path(["projectile", "motion_stages", 0], "extension", STGExtensionBinding.create(malformed), true)
	for i in 3: await process_frame
	var shown_issue = false
	for control in _controls(studio.inspector, "Label"):
		if "扩展定义需要修正" in control.text: shown_issue = true
	_expect(shown_issue, "invalid metadata displays clear editor issue")
	var invalid_field_built = false
	for control in _controls(studio.inspector, "SpinBox"):
		if control.tooltip_text == "进入这个运动阶段时的速度。": invalid_field_built = true
	_expect(not invalid_field_built, "editor does not instantiate invalid metadata fields")
	studio.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://extension_editor_checks.cfg"))


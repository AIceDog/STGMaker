extends SceneTree
## 验证公开 API 的实际游戏结果、跨实例隔离、取消与构建引用；不依赖编辑器内部状态。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Session = preload("res://stg/runtime/extensions/extension_session.gd")
const Flow = preload("res://stg/runtime/boss/flow_runner.gd")
const Behavior = preload("res://stg/runtime/boss/behavior_context.gd")
const Action = preload("res://stg/runtime/boss/action_runner.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Fixture = preload("res://tests/game_fixture.gd")
var checks: int = 0
var failures: int = 0

class RecordingEmission:
	extends STGEmissionExtension
	var calls: Array[String] = []
	var retained: STGEmissionContext
	func start(context: STGEmissionContext, parameters: Dictionary) -> void:
		retained = context
		parameters["tag"] = "runtime only"
	func tick(context: STGEmissionContext, _dt: float) -> void:
		context.emit(context.origin(), 0)
	func cancel(reason: String) -> void: calls.append(reason)

class RecordingAction:
	extends STGActionExtension
	var cancellations: Array[String] = []
	func tick(context: STGActionContext, dt: float) -> void:
		context.move(Vector2(-100 * dt, 0))
		if context.elapsed() >= 0.1: context.finish()
	func cancel(reason: String) -> void: cancellations.append(reason)

class Controller:
	extends STGPlayerExtension
	func tick(context: STGPlayerContext, dt: float) -> void:
		context.move(context.movement_input * 100 * dt)

class FinishingMotion:
	extends STGMotionExtension
	var cancellations: Array[String] = []
	func tick(context: STGMotionContext, _dt: float) -> void: context.finish()
	func cancel(reason: String) -> void: cancellations.append(reason)

class FailingEmission:
	extends STGEmissionExtension
	func start(context: STGEmissionContext, _parameters: Dictionary) -> void:
		context.finish(false)
		context.finish() # 第一次完成结果必须保持；后续请求必须被忽略。
		context.emit(context.origin(), 0)

class FailingPlayer:
	extends STGPlayerExtension
	func tick(context: STGPlayerContext, _dt: float) -> void: context.finish(false)

class InvalidConstructor:
	extends STGActionExtension
	func _init(_required): pass

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func declaration(kind: String, implementation: Script) -> STGExtensionDefinition:
	var result = STGExtensionDefinition.new()
	result.kind = kind
	result.id = "protocol_" + kind
	result.implementation = implementation
	return result

func run() -> void:
	_test_contracts()
	_test_emission_lifecycle()
	_test_early_completion_and_failure()
	_test_actions_and_conditions()
	_test_effects_and_dependencies()
	_test_reference_boundaries()
	_test_player_slots()
	print("EXTENSION PROTOCOL RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _world():
	var project = STGProject.create()
	project.schema_version = STGProject.VERSION
	var bullet = Factory.bullet()
	bullet.id = "protocol_bullet"
	project.bullets.append(bullet)
	var skill = Factory.barrage(bullet.id)
	skill.id = "protocol_skill"
	skill.projectile.motion_stages.assign([Factory.stage("wait")])
	skill.projectile.motion_stages[0].duration = 2
	skill.fire_pattern.count = 1
	skill.fire_pattern.rounds = 1
	project.barrages.append(skill)
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, "barrages", skill.id)
	world.clear_attacks()
	world.player = Vector2(-400, -200)
	return world

func _test_contracts() -> void:
	var definition = declaration("action", RecordingAction)
	check(definition.validate({}, "action").is_empty(), "matching capability is accepted")
	check(not definition.validate({}, "motion").is_empty(), "wrong slot is rejected before execution")
	definition.kind = "emission"
	check(not definition.validate({}, "emission").is_empty(), "script inheritance must match declared family")
	definition.kind = "action"
	definition.sdk_version = 2
	check(not definition.validate({}).is_empty(), "unsupported SDK version is rejected")
	definition = declaration("action", InvalidConstructor)
	check(not definition.validate({}).is_empty(), "required constructor arguments are rejected without invoking script")
	var session = Session.new()
	var context = STGActionContext.new()
	check(not session.begin(null, {}, "action", context), "missing implementation produces a normal failed session")
	check(session.failed and session.finished and not context.active(), "invalid sessions close contexts")

func _test_early_completion_and_failure() -> void:
	var world = _world()
	var projectile = world.project.barrages[0].projectile
	projectile.motion_stages[0].mode = "extension"
	projectile.motion_stages[0].extension = STGExtensionBinding.create(declaration("motion", FinishingMotion))
	projectile.motion_stages.append(Factory.stage("wait"))
	var actor = world.emit_projectile("protocol_skill", Vector2.ZERO, 0, 1)
	actor.tick(world, 0.01)
	check(actor.stage_index == 1, "early motion completion immediately advances to the next stage")
	world.clear_attacks()
	var shot = world.project.barrages[0].fire_pattern
	shot.extension = Factory.extension_binding(declaration("emission", FailingEmission))
	var barrage = world.play_barrage("protocol_skill", Vector2.ZERO)
	world.step(0.01)
	check(barrage.failed and barrage.emission_finished() and world.actors.is_empty(), "failed emission preserves first result and cannot emit after finish")
	world.free()

func _test_emission_lifecycle() -> void:
	var world = _world()
	var shot = world.project.barrages[0].fire_pattern
	var definition = declaration("emission", RecordingEmission)
	definition.fields.assign([{"name": "tag", "type": "string", "default": "asset"}])
	shot.extension = Factory.extension_binding(definition)
	shot.extension_duration = 0.04
	var first = world.play_barrage("protocol_skill", Vector2.ZERO)
	var second = world.play_barrage("protocol_skill", Vector2(100, 0))
	world.step(0.01)
	check(first.emission_sessions.size() == 1 and second.emission_sessions.size() == 1, "each barrage owns its asynchronous emission")
	var a = first.emission_sessions[0].session.implementation
	var b = second.emission_sessions[0].session.implementation
	check(a != b and a.retained != b.retained, "two identical shots have independent implementations and contexts")
	check(shot.extension.parameters.tag == "asset", "runtime parameter mutation cannot alter saved binding")
	check(world.actors.size() == 2 and world.actors[0].owner_id != world.actors[1].owner_id, "custom emissions use normal bullet instances and separate owners")
	check(not first.emission_finished(), "unfinished custom emission keeps attack alive")
	world.stop_owner(first.owner_id)
	world.stop_owner(first.owner_id)
	check(a.calls == ["stopped"] and not a.retained.active(), "owner stop cancels once and invalidates retained context")
	var before = world.actors.size()
	a.retained.emit(Vector2.ZERO, 0)
	check(world.actors.size() == before, "closed context cannot spawn more bullets")
	for i in 4: world.step(0.01)
	check(b.calls == ["expired"] and second.emission_finished(), "duration limit cancels asynchronous emission exactly once")
	var third = world.play_barrage("protocol_skill", Vector2.ZERO)
	world.step(0.01)
	var c = third.emission_sessions[0].session.implementation
	world.free()
	check(c.calls == ["removed"] and not c.retained.active(), "world teardown cancels future custom emission")

func _test_actions_and_conditions() -> void:
	var world = _world()
	var behavior = Behavior.new()
	behavior.world = world
	behavior.active_node_id = "custom_action"
	var config = STGBossAction.new() # 自定义动作无需伪造内置攻击、移动或表现配置。
	config.extension = Factory.extension_binding(declaration("action", RecordingAction))
	config.duration = 1
	var executor = Action.new()
	executor.start(behavior, config)
	var instance = executor.session.implementation
	var origin: Vector2 = world.boss
	check(not executor.tick(behavior, 0.05), "custom action can span multiple ticks")
	check(executor.tick(behavior, 0.05) and not executor.failed, "context completion advances the flow")
	check(world.boss.is_equal_approx(origin + Vector2(-10, 0)), "action moves the same enemy used by the battle")
	executor.cancel(behavior)
	check(instance.cancellations == ["completed"], "completion followed by cancel does not duplicate callback")
	executor = Action.new()
	config.interrupt_on_hit = true
	executor.start(behavior, config)
	instance = executor.session.implementation
	world.boss_hit_serial += 1
	check(executor.tick(behavior, 0.01) and executor.failed and instance.cancellations == ["interrupted"], "hit interruption fails custom action and cancels it once")
	var flow = STGBehaviorFlow.new()
	var node = STGFlowNode.new()
	node.id = "condition"
	node.kind = "condition"
	node.condition = "extension"
	node.extension = Factory.extension_binding(load("res://game/extensions/conditions/health_gate.tres"))
	node.extension.parameters.threshold = 50.0
	node.next_id = STGFlowNode.SUCCESS
	node.failure_id = STGFlowNode.FAILURE
	flow.nodes.append(node)
	flow.entry_id = node.id
	var runner = Flow.new()
	runner.start(flow, behavior)
	world.hp = 40
	runner.tick(0.01)
	check(runner.tick(0.01) == Flow.Status.SUCCESS, "custom condition follows success connection")
	runner.reset()
	world.hp = 90
	runner.tick(0.01)
	check(runner.tick(0.01) == Flow.Status.FAILURE, "custom condition follows failure connection")
	world.free()

func _test_effects_and_dependencies() -> void:
	var world = _world()
	var plain: STGBarrageSkill = world.project.barrages[0]
	var source: STGBarrageSkill = world.project.Copy.copy(plain)
	source.id = "protocol_source"
	world.project.barrages.append(source)
	var effect = Factory.extension_binding(load("res://game/extensions/effects/hit_burst.tres"))
	effect.parameters.skill = plain.id
	source.projectile.lifecycle.hit_effects.append(effect)
	var actor = world.emit_projectile(source.id, world.player, 0, 17)
	actor.tick(world, 0.01)
	check(world.hits == 1, "built-in damage still executes with custom effects")
	check(world.barrages.size() == 1 and world.barrages[0].owner_id == 17, "effect requests successor barrage through public context with inherited owner")
	var refs = preload("res://stg/definitions/resource_references.gd").collect(source)
	check(refs.any(func(ref): return ref.id == "protocol_skill" and ref.collection == "barrages"), "resource_id metadata enters dependency graph")
	var compiled = Compiler.compile_library(world.project, [{"collection": "barrages", "id": source.id}])
	check(compiled.issue.is_empty() and compiled.library.barrages.size() == 2 and compiled.library.bullets.size() == 1, "compiler includes dependencies referenced only by custom parameters")
	effect.parameters.skill = "missing_skill"
	check(not world.project.validate().is_empty(), "missing extension content reference is diagnosed before preview")
	world.free()
func _test_reference_boundaries() -> void:
	var world = _world()
	var references = preload("res://stg/definitions/resource_references.gd")
	var definition = declaration("action", RecordingAction)
	definition.fields.assign([{"name": "bullet_id", "type": "resource_id", "collection": "barrages", "default": "protocol_skill"}])
	var binding = Factory.extension_binding(definition)
	var found = references.collect(binding)
	check(found.size() == 1 and found[0].collection == "barrages", "custom parameter names follow declared collection instead of built-in field-name heuristics")
	var boss = Factory.boss("protocol_skill")
	boss.id = "protocol_custom_boss"
	var action = Factory.action("fire", "unused_missing_builtin_skill")
	action.extension = binding
	boss.phases[0].behavior_flow.nodes[0].action = action
	world.project.bosses.append(boss)
	var compiled = Compiler.compile_library(world.project, [{"collection": "bosses", "id": boss.id}])
	check(compiled.issue.is_empty(), "custom action ignores retained unused built-in attack references")
	var condition = STGFlowNode.new()
	condition.kind = "condition"
	condition.condition = "hp"
	condition.extension = binding
	check(references.collect(condition).is_empty(), "built-in condition ignores inactive extension draft")
	var motion = Factory.stage("wait")
	motion.extension = STGExtensionBinding.create(definition)
	motion.extension.parameters = {"bullet_id": "unused_missing_id"}
	check(references.collect(motion).is_empty(), "built-in motion ignores inactive extension parameters")
	world.free()

func _test_player_slots() -> void:
	var game = Fixture.create()
	game.player.controller = Factory.extension_binding(declaration("player", Controller))
	game.player.weapon = Factory.extension_binding(load("res://game/extensions/players/spread_weapon.tres"))
	game.player.ability = Factory.extension_binding(load("res://game/extensions/players/dash.tres"))
	var session = STGGameSession.new()
	root.add_child(session)
	session.configure(game, "user://protocol_player_progress.json")
	check(session.enter_location("coast"), "game starts with separate controller, weapon and ability modules")
	var initial: Vector2 = session.simulation.player
	session.advance(0.01, Vector2.RIGHT, true, true)
	check(session.simulation.player.x > initial.x + 70, "custom movement and ability operate on the real player")
	check(session.simulation.player_shots.shots.size() == 3, "custom weapon emits independent spread projectiles")
	var player: Vector2 = session.simulation.player
	var context: STGPlayerContext = session.player_contexts.ability
	session.toggle_pause()
	session.advance(1, Vector2.RIGHT, true, true)
	check(session.simulation.player == player, "pause suspends all player extension ticks")
	session.return_to_map()
	check(not context.active() and session.player_modules.is_empty(), "leaving battle releases every player context")
	check(game.player.ability.parameters.distance == 75, "gameplay never writes ability state into shared player definition")
	session.free()
	game.player.ability = Factory.extension_binding(declaration("player", FailingPlayer))
	session = STGGameSession.new()
	root.add_child(session)
	session.configure(game, "user://protocol_failed_player_progress.json")
	session.enter_location("coast")
	session.advance(0.01)
	check(session.state == "error" and session.player_modules.is_empty(), "player module failure closes all player contexts and reports a game error")
	session.free()


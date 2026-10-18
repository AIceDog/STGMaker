@tool
extends RefCounted
## 所有敌人流程和可复用子流程使用同一执行器。等待保留帧内剩余时间，分支可并行推进。
enum Status { RUNNING, SUCCESS, FAILURE }
const ActionRunner = preload("res://stg/runtime/boss/action_runner.gd")
var flow: STGBehaviorFlow
var context
var current_id: String = ""
var action_run
var history: Dictionary = {}
var branches: Array = []
var elapsed: float = 0.0
var cancelled: bool = false
var failed: bool = false
var _wait_elapsed: float = 0.0
var _instance
var _children: Array = []
var _spawned_plans: Array = []
var _finished: bool = false
var first_step_duration: float = -1.0
var owner_id: int:
	get: return context.owner_id if context != null else 0
var origin: Vector2:
	get: return context.origin if context != null else Vector2.ZERO
	set(value):
		if context != null: context.origin = value
		for plan in _spawned_plans: plan.origin = value

func start(definition: STGBehaviorFlow, data) -> void:
	flow = definition
	context = data
	current_id = flow.entry_id
	action_run = null
	history.clear()
	branches.clear()
	_children.clear()
	_spawned_plans.clear()
	_instance = null
	_wait_elapsed = 0
	elapsed = 0
	cancelled = false
	failed = false
	_finished = false

func reset() -> void:
	start(flow, context)
	if not flow.loop_entry_id.is_empty(): current_id = flow.loop_entry_id

func states() -> Dictionary: return history

func tick(dt: float) -> int:
	if cancelled: return Status.FAILURE
	if _finished: return Status.FAILURE if failed else Status.SUCCESS
	if first_step_duration >= 0:
		dt = minf(dt, first_step_duration)
		first_step_duration = -1
	elapsed += dt
	var budget = dt
	# 零时长环不能卡死编辑器；编辑校验同时拒绝没有等待的循环。
	for transition in 128:
		if STGFlowNode.is_terminal(current_id):
			var result = _return_branch()
			if result != Status.RUNNING:
				_finished = true
				failed = result == Status.FAILURE
				return result
			return Status.RUNNING
		var node = flow.find(current_id)
		if node == null:
			failed = true
			_finished = true
			return Status.FAILURE
		history[node.id] = Status.RUNNING
		if node.kind == "condition":
			_advance(node, _condition(node))
			return Status.RUNNING
		if node.kind == "random":
			var order = Array(node.choices)
			for i in range(order.size() - 1, 0, -1):
				var other = context.world.rng.randi_range(0, i)
				var saved = order[i]
				order[i] = order[other]
				order[other] = saved
			branches.append({"node": node, "order": order, "cursor": 0})
			current_id = order[0]
			return Status.RUNNING
		if node.kind == "wait":
			var consumed = minf(budget, maxf(0, node.delay - _wait_elapsed))
			_wait_elapsed += consumed
			budget -= consumed
			if _wait_elapsed + 0.000001 < node.delay: return Status.RUNNING
			_advance(node, true)
			continue
		if node.kind in ["attack", "call"]:
			if _instance == null:
				if node.kind == "attack":
					_instance = context.world.play_barrage(node.barrage_id, context.origin_position(), context.owner_id, context.heading)
				else:
					_instance = context.world.play_behavior(node.behavior_id, context.origin_position(), context.owner_id, context.heading, context.depth + 1)
				if _instance == null:
					_advance(node, false)
					continue
				_instance.first_step_duration = budget
				_spawned_plans.append(_instance)
				context.owned_attacks.append(_instance.owner_id)
			if node.wait_mode == "immediate":
				_advance(node, true)
				continue
			var done = _instance.emission_finished() if node.wait_mode == "emission" else _instance.is_finished(context.world)
			if not done: return Status.RUNNING
			_advance(node, not _instance.failed)
			continue
		if node.kind == "parallel":
			if _children.is_empty():
				for child_flow in node.children:
					var child = get_script().new()
					child.start(child_flow, context.child())
					_children.append(child)
					_spawned_plans.append(child)
			var done = true
			var success = true
			for child in _children:
				var result = child.tick(budget)
				done = done and result != Status.RUNNING
				success = success and result != Status.FAILURE
			if not done: return Status.RUNNING
			_advance(node, success)
			budget = 0 # 等待并行结束后，下一节点从当前帧末尾开始。
			continue
		if action_run == null:
			context.active_node_id = node.id
			action_run = ActionRunner.new()
			action_run.start(context, node.action)
		if action_run.tick(context, budget):
			_advance(node, not action_run.failed)
			context.active_node_id = ""
		# 动作模块自管前后摇；不把同一 dt 重复交给后面的动作。
		return Status.RUNNING
	context.world.issue = "行为流程在一帧内切换超过 128 次，请检查无等待循环"
	failed = true
	_finished = true
	return Status.FAILURE

func _advance(node: STGFlowNode, success: bool) -> void:
	history[node.id] = Status.SUCCESS if success else Status.FAILURE
	current_id = node.next_id if success else node.failure_id
	action_run = null
	_wait_elapsed = 0
	_instance = null
	_children.clear()

func _return_branch() -> int:
	var success = current_id != STGFlowNode.FAILURE
	if branches.is_empty(): return Status.SUCCESS if success else Status.FAILURE
	var frame = branches[-1]
	if not success:
		frame.cursor += 1
		if frame.cursor < frame.order.size():
			current_id = frame.order[frame.cursor]
			return Status.RUNNING
	branches.pop_back()
	history[frame.node.id] = Status.SUCCESS if success else Status.FAILURE
	current_id = frame.node.next_id if success else frame.node.failure_id
	return Status.RUNNING

func _condition(node: STGFlowNode) -> bool:
	var session = preload("res://stg/runtime/extensions/extension_session.gd").new()
	var data = STGConditionContext.new(context.world)
	var binding = node.extension if node.condition == "extension" else null
	var builtin = preload("res://stg/runtime/modules/condition.gd").new(node) if binding == null and node.condition != "extension" else null
	if not session.begin(binding.definition if binding != null else null, binding.parameters if binding != null else {}, "condition", data, builtin): context.world.issue = session.issue
	var result = data.result
	session.cancel("completed")
	return result

func emission_finished() -> bool:
	if cancelled: return true
	if not _finished: return false
	for plan in _spawned_plans:
		if not plan.emission_finished(): return false
	return true
func is_finished(world) -> bool: return emission_finished() and world.count_owned(owner_id, false) == 0

func cancel() -> void:
	if cancelled: return
	cancelled = true
	if action_run != null: action_run.cancel(context)
	if _instance != null: _instance.cancel()
	for plan in _spawned_plans: plan.cancel()
	for child in _children: child.cancel()
	action_run = null
	_children.clear()
	branches.clear()
	if context != null: context.active_node_id = ""


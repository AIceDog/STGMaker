@tool
extends RefCounted
## 所有内置与用户能力共用的生命周期。先断开引用再 cancel，支持重复停止和回调重入。
var implementation: STGExtension
var context: STGExtensionContext
var finished: bool = true
var failed: bool = false
var issue: String = ""

func begin(definition: STGExtensionDefinition, parameters: Dictionary, kind: String, data: STGExtensionContext, builtin: STGExtension = null) -> bool:
	cancel("replaced")
	issue = ""
	failed = false
	finished = false
	context = data
	if context == null:
		issue = "缺少能力上下文"
		failed = true
		cancel("invalid")
		return false
	if definition != null:
		var prepared = definition.instantiate(parameters, kind)
		issue = "；".join(prepared.issues)
		implementation = prepared.implementation
		parameters = prepared.parameters
	else:
		implementation = builtin
		parameters = parameters.duplicate(true)
	if implementation == null or not issue.is_empty():
		if issue.is_empty(): issue = "缺少 %s 能力实现" % kind
		failed = true
		cancel("invalid")
		return false
	implementation.start(context, parameters)
	_settle()
	return true

func tick(dt: float) -> void:
	if implementation == null or dt <= 0: return
	context._elapsed += dt
	implementation.tick(context, dt)
	_settle()

func _settle() -> void:
	if context != null and context.is_finished():
		failed = context._failed
		cancel("failed" if failed else "completed")

func cancel(reason: String = "stopped", failure: bool = false) -> void:
	failed = failed or failure
	var ending = implementation
	var closing = context
	implementation = null
	context = null
	finished = true
	if closing != null: closing._close()
	if ending != null: ending.cancel(reason)

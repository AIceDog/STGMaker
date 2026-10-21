@tool
extends RefCounted
## 仅 STG_PERFORMANCE_TRACE=1 时输出诊断；普通制作不收集样本、不写日志。
static var enabled: bool = OS.get_environment("STG_PERFORMANCE_TRACE") == "1"
static func record(stage: String, started: int, project = null) -> void:
	if not enabled: return
	var assets = 0
	if project != null:
		for collection in project.References.COLLECTIONS: assets += project.get(collection).size()
	print("STG_PERF ", JSON.stringify({"library_assets": assets,"stage": stage, "us": Time.get_ticks_usec() - started,
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "memory": OS.get_static_memory_usage()}))

@tool
extends RefCounted
## 多选的纯计划计算：统一平移整关坐标，再换回阶段内时间，不改 Resource。
const Timing = preload("res://stg/definitions/level_timing.gd")

static func events(level: STGLevelDefinition, ids: Array) -> Array:
	var result: Array = []
	for index in level.segments.size():
		for event in level.segments[index].events:
			if ids.has(event.id):
				result.append({"from": index, "id": event.id, "at": Timing.start(level, index) + event.at})
	return result

static func plan(level: STGLevelDefinition, ids: Array, delta: float) -> Dictionary:
	var selected = events(level, ids)
	if selected.is_empty(): return {"delta": 0.0, "moves": []}
	var first: float = selected[0].at
	var last: float = first
	for entry in selected:
		first = minf(first, entry.at)
		last = maxf(last, entry.at)
	# 同一个位移受整关两端限制；不逐条夹紧，以免挤坏编排中的时间间距。
	var applied = clampf(delta, -first, Timing.total(level) - last)
	var moves: Array = []
	for entry in selected:
		var global_time: float = snappedf(entry.at + applied, 0.0001)
		var destination: int = entry.from if is_zero_approx(applied) else Timing.segment_at(level, global_time)
		moves.append({"from": entry.from, "id": entry.id, "to": destination,
			"at": clampf(global_time - Timing.start(level, destination), 0, level.segments[destination].duration)})
	return {"delta": applied, "moves": moves}

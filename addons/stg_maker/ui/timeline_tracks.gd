@tool
extends RefCounted
## 时间轴布局：把计划时间映射成矩形，按重叠情况分配出场行；不修改配置。
const Timing = preload("res://stg/definitions/level_timing.gd")

static func build(project: STGProject, level: STGLevelDefinition, width: float, font: int, environment: bool) -> Dictionary:
	var label_width = font * 5.5
	var scale = maxf(1, width - label_width - 30) / maxf(0.1, Timing.total(level))
	var row_height = font + 12
	var y = font + 14.0
	var result = {"segments": [], "events": [], "environment": [], "labels": [], "height": 0.0}
	result.labels.append({"title": "关卡阶段", "y": y + font + 2})
	for index in level.segments.size():
		var segment = level.segments[index]
		var start = label_width + Timing.start(level, index) * scale
		result.segments.append(Rect2(start, y, maxf(1, segment.duration * scale - 2), row_height))
	y += row_height + 10
	for kind in ["enemy", "obstacle"]:
		var entries = []
		for index in level.segments.size():
			for event in level.segments[index].events:
				var wave = project.find("waves", event.wave_id)
				if wave == null or wave.kind != kind: continue
				var at = Timing.start(level, index) + event.at
				var span = minf((wave.count - 1) * wave.interval, level.segments[index].duration - event.at)
				entries.append({"index": index, "id": event.id, "event": event, "at": at, "span": span, "kind": kind})
		entries.sort_custom(func(a, b): return a.at < b.at)
		var ends = []
		result.labels.append({"title": "敌人出场" if kind == "enemy" else "障碍出场", "y": y + font + 2})
		for entry in entries:
			var x = label_width + entry.at * scale
			var bar_width = maxf(font * 6.0, entry.span * scale)
			var lane = 0
			while lane < ends.size() and ends[lane] > x: lane += 1
			if lane == ends.size(): ends.append(0)
			ends[lane] = x + bar_width + 6
			entry.rect = Rect2(x, y + lane * row_height, bar_width, row_height - 3)
			entry.generation_width = maxf(4, entry.span * scale)
			result.events.append(entry)
		y += max(1, ends.size()) * row_height + 10
	if environment:
		result.labels.append({"title": "背景卷轴", "y": y + font + 2})
		for index in level.segments.size():
			var rect = result.segments[index]
			result.environment.append({"index": index, "rect": Rect2(rect.position.x, y, rect.size.x, row_height - 3)})
		y += row_height + 8
		result.labels.append({"title": "音乐", "y": y + font + 2})
		result.music = Rect2(label_width, y, scale * Timing.total(level), row_height - 3)
		y += row_height + 8
	result.height = y + 8
	return result

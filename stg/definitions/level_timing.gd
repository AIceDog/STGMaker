@tool
extends RefCounted
## 完整关卡的计划坐标。事件仍保存阶段内时间，前段延长不会改写后段配置。
static func start(level: STGLevelDefinition, index: int) -> float:
	var value: float = 0
	for i in index:
		value += level.segments[i].duration
	return value

static func total(level: STGLevelDefinition) -> float:
	return start(level, level.segments.size())

static func segment_at(level: STGLevelDefinition, time: float) -> int:
	var value: float = 0
	for i in level.segments.size():
		value += level.segments[i].duration
		if time < value:
			return i
	return level.segments.size() - 1

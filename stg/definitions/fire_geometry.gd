@tool
extends RefCounted
## 发射排列几何，运行器和轨迹预览共用。
static func spawn_point(shot: STGFirePattern, index: int) -> Vector2:
	var fraction = index / maxf(1, shot.count - 1)
	match shot.arrangement:
		"circle":
			return Vector2.from_angle(TAU * index / shot.count) * shot.radius
		"line":
			return Vector2(lerpf(-shot.line_length / 2, shot.line_length / 2, fraction), 0)
		"path":
			return shot.path.sample_baked(shot.path.get_baked_length() * fraction, true)
	return Vector2.ZERO



@tool
extends RefCounted
## 空间路径与时间曲线的共享校验。
static func check_path(path: Curve2D, issues: PackedStringArray, title: String) -> void:
	if path == null or path.point_count < 2:
		issues.append(title + "：路径至少两个点")
		return
	for i in path.point_count:
		for vector in [path.get_point_position(i), path.get_point_in(i), path.get_point_out(i)]:
			if not vector.is_finite():
				issues.append(title + "：路径包含非有限坐标")

static func check_curve(curve: Curve, issues: PackedStringArray, title: String, progress: bool = false) -> void:
	if curve == null or curve.point_count < 2:
		issues.append(title + "：时间曲线至少两个点")
		return
	var previous = Vector2(-1, -1)
	for i in curve.point_count:
		var point = curve.get_point_position(i)
		if not point.is_finite() or point.x <= previous.x or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 10:
			issues.append(title + "：曲线需要递增时间与 0–10 倍率")
		if progress and (point.y < previous.y or point.y > 1):
			issues.append(title + "：路径进度需要单调递增到 1")
		previous = point
	if not is_zero_approx(curve.get_point_position(0).x) or not is_equal_approx(previous.x, 1):
		issues.append(title + "：曲线必须覆盖 0–1")
	if progress and (not is_zero_approx(curve.get_point_position(0).y) or not is_equal_approx(previous.y, 1)):
		issues.append(title + "：路径进度端点需要为 0 和 1")

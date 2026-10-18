@tool
extends RefCounted
## 战斗空间约定：画面比例与窗口尺寸分离，不把 UI 像素当成路径坐标。
## 3840:2160 对应 16:9；使用 960×540 设计单位，中心为 (0, 0)，+X 向右、+Y 向下。
const DISPLAY_RESOLUTION = Vector2(3840, 2160)
const DESIGN_SIZE = DISPLAY_RESOLUTION / 4.0
const BOUNDS = Rect2(-DESIGN_SIZE / 2.0, DESIGN_SIZE)
const PLAYER_SPAWN = Vector2(-320, 0)
const ENEMY_SPAWN = Vector2(320, 0)
const ENEMY_SHOT_ANGLE = PI # Godot 角度使用弧度；PI 指向左，0 指向右。
const BULLET_PATH_ROTATION = ENEMY_SHOT_ANGLE - PI / 2.0 # 移动弹局部 +Y 转向实际发射方向。

static func fit_screen(available: Rect2) -> Rect2:
	# 自定义接口：把完整虚拟屏幕等比放入可用矩形，四周多余空间作为留黑区。
	var factor = maxf(0.001, minf(available.size.x / DESIGN_SIZE.x, available.size.y / DESIGN_SIZE.y))
	var fitted_size = DESIGN_SIZE * factor
	return Rect2(available.get_center() - fitted_size / 2.0, fitted_size)

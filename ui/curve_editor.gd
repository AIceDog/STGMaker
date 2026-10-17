@tool
extends Control
## 时间曲线编辑控件。横轴固定 0–1，纵轴为倍率；一次拖动只提交一次资源副本。
const F = preload("res://addons/stg_maker/ui/fields.gd")
signal curve_changed(curve: Curve)
var curve: Curve
var ceiling: float = 3.0
var dragging: int = -1
var padding: float = 30
var progress_mode: bool = false
var time_caption: String = "阶段时间"

func configure(value: Curve, maximum: float = 3) -> void:
	curve = value.duplicate(true) if value != null else null
	ceiling = maximum
	progress_mode = maximum == 1
	if curve != null:
		for i in curve.point_count: ceiling = maxf(ceiling, curve.get_point_position(i).y)
	var vertical = "纵轴是路径走过的比例：0 为起点，100% 为终点，\n曲线保持向前推进。" if progress_mode else "纵轴是外观或碰撞的倍率：\n1 倍保持原大小，0.5 倍为一半。"
	F.help(self, "横轴是当前运动步骤或移动段的相对时间，\n从 0 到 100%；不是整关时间，也不改变步骤时长。\n" + vertical + "\n拖动橙色点调整曲线，双击空处加点，\n右键中间点删除；首尾点保留。\n拖动释放后提交一次修改。")
	queue_redraw()

func screen(point: Vector2) -> Vector2:
	return Vector2(padding, padding) + Vector2(point.x, 1 - point.y / ceiling) * (size - Vector2.ONE * padding * 2)

func value(point: Vector2) -> Vector2:
	var relative = ((point - Vector2.ONE * padding) / (size - Vector2.ONE * padding * 2).max(Vector2.ONE)).clamp(Vector2.ZERO, Vector2.ONE)
	return Vector2(relative.x, (1 - relative.y) * ceiling)

func nearest(point: Vector2) -> int:
	if curve == null: return -1
	for i in curve.point_count:
		if screen(curve.get_point_position(i)).distance_to(point) <= 12: return i
	return -1

func _draw() -> void: # Godot 回调；下列 draw_* 是 Godot 内置绘制方法。
	draw_rect(Rect2(Vector2.ZERO, size), Color("111c29"))
	if curve == null: return
	for i in 6:
		var x = screen(Vector2(i / 5.0, 0)).x
		draw_line(Vector2(x, padding), Vector2(x, size.y - padding), Color("2c3d50"))
	var points = PackedVector2Array()
	for i in 121: points.append(screen(Vector2(i / 120.0, curve.sample(i / 120.0))))
	draw_polyline(points, Color("55dfbc"), 2, true)
	for i in curve.point_count: draw_circle(screen(curve.get_point_position(i)), 5, Color("ffbf79"))
	var font = get_theme_font("font", "Label")
	draw_string(font, Vector2(8, 22), time_caption + " 0 → 100% · 拖动点 / 双击加点 / 右键删点", HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, get_theme_default_font_size())
	draw_string(font, Vector2(4, size.y - 8), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(4, 42), "100%" if progress_mode else "%.1f×" % ceiling, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func _gui_input(event: InputEvent) -> void: # Godot 回调
	if curve == null: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = nearest(event.position)
				if event.double_click and dragging < 0:
					var point = value(event.position)
					for i in curve.point_count:
						if absf(point.x - curve.get_point_position(i).x) < 0.01: return
					if progress_mode:
						for i in range(1, curve.point_count):
							if point.x < curve.get_point_position(i).x:
								point.y = clampf(point.y, curve.get_point_position(i - 1).y, curve.get_point_position(i).y); break
					curve.add_point(point, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
					curve_changed.emit(curve)
			elif dragging >= 0: dragging = -1; curve_changed.emit(curve)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var index = nearest(event.position)
			if index > 0 and index < curve.point_count - 1: curve.remove_point(index); curve_changed.emit(curve)
		queue_redraw()
		accept_event() # Godot 内置：标记输入已处理
	elif event is InputEventMouseMotion and dragging >= 0:
		var point = value(event.position)
		if dragging == 0: point.x = 0
		elif dragging == curve.point_count - 1: point.x = 1
		else: point.x = clampf(point.x, curve.get_point_position(dragging - 1).x + 0.005, curve.get_point_position(dragging + 1).x - 0.005)
		if progress_mode:
			if dragging == 0: point.y = 0
			elif dragging == curve.point_count - 1: point.y = 1
			else: point.y = clampf(point.y, curve.get_point_position(dragging - 1).y, curve.get_point_position(dragging + 1).y)
		curve.set_point_value(dragging, point.y)
		dragging = curve.set_point_offset(dragging, point.x)
		queue_redraw()
		accept_event()


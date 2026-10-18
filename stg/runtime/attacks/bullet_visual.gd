@tool
extends RefCounted
## _draw 回调中的静态素材绘制；素材局部旋转和偏移独立于弹体运动朝向。
static func draw(actor) -> void:
	var material: STGBulletDefinition = actor.definition
	if material == null: return
	var visual = material.visual
	var geometry = visual.geometry
	var factor: float = actor.visual_scale
	if factor > 0 and (material.visual_scene == null or material.show_base_visual):
		var color = visual.color
		color.a *= actor.opacity()
		actor.draw_set_transform(geometry.offset * factor, deg_to_rad(geometry.rotation_degrees), Vector2.ONE * factor)
		if visual.mode == "texture":
			var texture = actor.current_texture()
			if texture != null: actor.draw_texture_rect(texture, Rect2(-geometry.size / 2, geometry.size), false, color)
		elif material.form == "laser" and geometry.along_beam:
			var path = material.beam_points(geometry)
			if path.size() >= 2: actor.draw_polyline(path, color, geometry.size.y, true)
		else: _geometry(actor, geometry, color)
	actor.draw_set_transform(Vector2.ZERO)
	if actor.show_collision and actor.collision != null:
		var hit = material.collision
		actor.draw_set_transform(hit.offset * actor.collision_scale, deg_to_rad(hit.rotation_degrees), Vector2.ONE * actor.collision_scale)
		var color = Color(1, 0.3, 0.5, 0.3)
		if material.form == "laser" and hit.along_beam:
			var path = material.beam_points(hit)
			if path.size() >= 2:
				actor.draw_polyline(path, color, hit.size.y, true)
				actor.draw_circle(path[0], hit.size.y / 2, color)
				actor.draw_circle(path[-1], hit.size.y / 2, color)
		else: _geometry(actor, hit, color)
		actor.draw_set_transform(Vector2.ZERO)

static func _geometry(actor, geometry: STGBulletGeometry, color: Color) -> void:
	if (geometry.kind == "circle" or geometry.kind == "sector" and is_equal_approx(geometry.sector_angle, 360)) and is_equal_approx(geometry.size.x, geometry.size.y):
		actor.draw_circle(Vector2.ZERO, geometry.size.x / 2, color)
	elif geometry.kind == "ring":
		var outside = geometry.outline()
		for i in outside.size():
			var a = outside[i]
			var b = outside[(i + 1) % outside.size()]
			actor.draw_colored_polygon(PackedVector2Array([a, b, b * geometry.inner_ratio, a * geometry.inner_ratio]), color)
	else:
		var points = geometry.outline()
		if not Geometry2D.triangulate_polygon(points).is_empty(): actor.draw_colored_polygon(points, color)

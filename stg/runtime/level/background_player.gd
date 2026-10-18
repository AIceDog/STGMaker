@tool
extends Node2D
## 背景接口 configure/update_scroll：位置由卷轴距离决定，可重复测试，不使用独立墙钟。
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
var definition: STGLevelDefinition
var distance: float = 0

## 自定义配置入口：共享关卡背景定义，绘制读取纹理与图层倍率，不修改配置。
func configure(level: STGLevelDefinition) -> void:
	definition = level
	queue_redraw()

## 自定义更新：value 为关卡累计推进像素数，图层从同一距离计算各自位移。
func update_scroll(value: float) -> void:
	distance = value
	queue_redraw()

func _draw() -> void: # Godot 回调；draw_* 为内置绘制方法。
	if definition == null:
		return
	draw_rect(CombatSpace.BOUNDS, definition.background_color)
	for index in definition.background_layers.size():
		var layer = definition.background_layers[index]
		var offset = distance * layer.scroll_ratio
		if layer.texture != null:
			# 按高度等比铺贴，避免将不同宽高比的美术强拉成 16:9。
			var texture_size = layer.texture.get_size()
			var width = CombatSpace.DESIGN_SIZE.y * texture_size.x / maxf(1, texture_size.y)
			var left = CombatSpace.BOUNDS.position.x - fposmod(offset, width)
			while left < CombatSpace.BOUNDS.end.x:
				draw_texture_rect(layer.texture, Rect2(Vector2(left, CombatSpace.BOUNDS.position.y), Vector2(width, CombatSpace.DESIGN_SIZE.y)), false, layer.tint)
				left += width
		else:
			# 没有美术时仍能观察两层向左滚动的速度差；正式制作时替换贴图即可。
			for i in 22:
				var x = -480 + fposmod(i * 173.0 + index * 91 - offset, 960)
				var y = -240 + fposmod(i * 97.0 + index * 137, 480)
				draw_circle(Vector2(x, y), 1.3 + index, Color("536d91") * layer.tint)

@tool
extends Node2D
## 命中帧动画脱离原弹体收尾；计时仍由 Simulation 推进，不影响命中判定。
const Frames = preload("res://stg/definitions/texture_frames.gd")
var clip: SpriteFrames
var size: Vector2
var tint: Color
var elapsed: float = 0.0

func tick(dt: float) -> void:
	elapsed += dt
	queue_redraw()

func _draw() -> void:
	if clip == null: return
	var texture = Frames.texture_at(clip, elapsed)
	if texture != null: draw_texture_rect(texture, Rect2(-size / 2, size), false, tint)

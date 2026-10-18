extends Node2D
## 主角仅负责绘制；输入、生命和无敌判定均由 STGGameSession 管理。
var session: STGGameSession

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if session == null or session.simulation == null:
		return
	var at = session.simulation.player
	var flashing = session.invulnerability > 0 and int(session.invulnerability * 12) % 2 == 0
	var color = Color("77e3ff")
	color.a = 0.35 if flashing else 1.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(17, 0), at + Vector2(-12, -12), at + Vector2(-6, 0), at + Vector2(-12, 12)]), color)
	draw_line(at + Vector2(-13, 0), at + Vector2(-23, 0), Color("ffd381"), 5, true)
	draw_circle(at, session.definition.player.hit_radius, Color("f4fdff"))

@tool
extends STGBehaviorProgram
func start(ctx: STGBehaviorContext, p: Dictionary) -> void:
    var value: float = 0
    match p.query:
        "distance": value = ctx.enemy_position().distance_to(ctx.player_position())
        "hp": value = ctx.enemy_health()
        "cooldown": value = ctx.action_elapsed(p.node_id)
        "recent_hit": value = ctx.seconds_since_hit()
        "player_x": value = ctx.player_position().x - ctx.enemy_position().x
        "player_y": value = ctx.player_position().y - ctx.enemy_position().y
    var yes: bool = value <= p.threshold if p.comparison == "less_equal" else value >= p.threshold
    ctx.complete("yes" if yes else "no")

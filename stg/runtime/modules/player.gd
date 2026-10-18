@tool
extends STGPlayerExtension
## 默认主角规则成为能力实现；输入采集与游戏界面不含移动/武器算法。
func tick(context: STGPlayerContext, dt: float) -> void:
	match context.slot:
		"controller": context.move(context.movement_input.limit_length() * context._player_definition.move_speed * dt)
		"weapon":
			if context.firing: context.fire()

@tool
extends STGConditionExtension
var node: STGFlowNode
func _init(definition: STGFlowNode) -> void: node = definition
func evaluate(context: STGConditionContext, _parameters: Dictionary) -> bool:
	var value = context.enemy_position().distance_to(context.player_position())
	match node.condition:
		"hp": value = context.enemy_health()
		"cooldown": value = context.action_elapsed(node.reference_id)
		"recent_hit": value = context.seconds_since_hit()
	return value <= node.threshold if node.comparison == "less_equal" else value >= node.threshold

@tool
extends STGConditionExtension
func evaluate(context: STGConditionContext, parameters: Dictionary) -> bool:
	return context.enemy_health() <= float(parameters.get("threshold", 100))

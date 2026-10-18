@tool
extends STGEffectExtension
## 招式 ID 使用 resource_id 元数据，构建器能找到依赖，导入时也能重映射。
func apply(context: STGEffectContext, parameters: Dictionary) -> void:
	var skill = str(parameters.get("skill", ""))
	if not skill.is_empty(): context.play_barrage(skill, context.origin(), context.heading())

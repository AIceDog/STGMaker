@tool
extends STGEffectExtension
## 原有接触伤害也是效果实现，和额外命中效果共用执行入口。
func apply(context: STGEffectContext, _parameters: Dictionary) -> void:
	context.damage_player(context.damage)

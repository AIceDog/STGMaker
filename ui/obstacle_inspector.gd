@tool
extends RefCounted
const F = preload("res://addons/stg_maker/ui/fields.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const EntityFields = preload("res://addons/stg_maker/ui/entity_fields.gd")

static func build(host, box, obstacle: STGObstacleDefinition) -> void:
	R.asset(host, box, "texture", "障碍贴图", obstacle.texture)
	F.label(box, "占位颜色")
	var color = ColorPickerButton.new(); color.color = obstacle.color
	color.color_changed.connect(R.setter(host, [], "color")); box.add_child(color)
	F.help(color, F.Help.text("占位颜色"))
	F.note(box, "障碍定义可以被多个编队复用；障碍不执行敌人 AI。")
	EntityFields.build(host, box, obstacle.entity_settings)

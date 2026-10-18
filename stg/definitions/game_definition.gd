@tool
class_name STGGameDefinition
extends Resource
## 成品游戏的唯一入口资源。资源定义可同时被编辑器、预览与独立游戏读取。
@export var title: String = "STGMaker · 飞行射击"
@export var library: STGProject
@export var player: STGPlayerDefinition
@export var world: STGWorldDefinition
@export var start_location_id: String = ""

func validate() -> PackedStringArray:
	var errors = PackedStringArray()
	if title.strip_edges().is_empty():
		errors.append("游戏缺少名称")
	if library == null:
		errors.append("游戏缺少战斗资源库")
	else:
		errors.append_array(library.validate())
	if player == null:
		errors.append("游戏缺少主角定义")
	else:
		errors.append_array(player.validate())
	if world == null:
		errors.append("游戏缺少世界地图")
	else:
		errors.append_array(world.validate(library))
		if world.find(start_location_id) == null:
			errors.append("游戏的起始地点不存在")
		elif not world.find(start_location_id).requires_completion.is_empty():
			errors.append("游戏的起始地点必须初始开放")
	if player != null and library != null:
		for reference in preload("res://stg/definitions/resource_references.gd").collect(player):
			if library.find(reference.collection, reference.id) == null: errors.append("主角扩展引用不存在：" + reference.collection + ":" + reference.id)
	return errors

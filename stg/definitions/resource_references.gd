@tool
extends RefCounted
## 当前生效配置的引用图；编译、导入、删除保护与校验使用同一遍历。
const COLLECTIONS = ["bullets", "barrages", "behaviors", "bosses", "waves", "levels", "obstacles"]
const LABELS = {"bullets": "子弹素材", "barrages": "招式库", "behaviors": "行为子流程", "bosses": "敌人 / Boss", "waves": "出场编队", "levels": "关卡", "obstacles": "障碍定义"}
const FIELDS = {
	"bullet_id": "bullets", "transform_attack_id": "barrages",
	"barrage_id": "barrages", "on_expire_barrage_id": "barrages", "on_hit_barrage_id": "barrages",
	"behavior_id": "behaviors", "on_expire_behavior_id": "behaviors", "on_hit_behavior_id": "behaviors",
	"on_death_skill_id": "barrages", "entry_barrage_id": "barrages",
	"on_death_behavior_id": "behaviors", "entry_behavior_id": "behaviors",
	"enemy_id": "bosses", "obstacle_id": "obstacles", "wave_id": "waves", "level_id": "levels",
}

static func collect(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_visit(value, result, {})
	return result

static func users(project: Resource, collection: String, identifier: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source in COLLECTIONS:
		for asset in project.get(source):
			if asset == null or (source == collection and asset.id == identifier): continue
			for reference in collect(asset):
				if reference.collection == collection and reference.id == identifier:
					result.append({"collection": source, "asset": asset})
					break
	return result

## 未启用的字段保留为制作草稿，不参与当前能力的依赖。
static func active_property(value: Resource, key: String) -> bool:
	if value is STGBossAction and value.extension != null: return key == "extension"
	if value is STGBossAttack:
		if key == "barrage_id": return value.enabled and value.behavior_id.is_empty()
		if key == "behavior_id": return value.enabled and not value.behavior_id.is_empty()
	if value is STGMotionStage:
		if key == "extension": return value.mode == "extension"
		if key == "transform_attack_id": return value.mode == "transform"
	if value is STGFlowNode:
		if key == "barrage_id": return value.kind == "attack"
		if key == "behavior_id": return value.kind == "call"
		if key == "children": return value.kind == "parallel"
		if key == "action": return value.kind == "action"
		if key == "extension": return value.kind == "condition" and value.condition == "extension"
	if value is STGWaveDefinition:
		if key == "enemy_id": return value.kind == "enemy"
		if key == "obstacle_id": return value.kind == "obstacle"
	return true

static func _visit(value: Variant, result: Array[Dictionary], visited: Dictionary) -> void:
	if value is Texture2D or value is AudioStream or value is PackedScene or value is Script: return
	if value is Resource:
		if visited.has(value.get_instance_id()): return
		visited[value.get_instance_id()] = true
		if value is STGBarrageSkill and value.fire_pattern != null and not value.fire_pattern.enemy_id.is_empty():
			# 召唤引用敌人，弹体素材与运动草稿不参与生效依赖。
			_visit(value.fire_pattern, result, visited)
			return
		if value is STGExtensionBinding and value.definition != null:
			result.append_array(value.definition.references(value.parameters))
		if value is STGExtensionBinding: return # 参数名由扩展元数据解释，不能套用内置字段映射。
		for property in value.get_property_list():
			if property.name == "script" or not property.usage & PROPERTY_USAGE_STORAGE or not active_property(value, property.name): continue
			_field(value, property.name, value.get(property.name), result, visited)
	elif value is Array:
		for child in value: _visit(child, result, visited)
	elif value is Dictionary:
		for key in value: _field(value, key, value[key], result, visited)

static func _field(owner: Variant, key: Variant, child: Variant, result: Array[Dictionary], visited: Dictionary) -> void:
	if FIELDS.has(key) and child is String and not child.is_empty():
		result.append({"owner": owner, "key": key, "collection": FIELDS[key], "id": child})
	else:
		_visit(child, result, visited)

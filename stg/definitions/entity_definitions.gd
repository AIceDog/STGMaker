@tool
extends RefCounted
## 所有模块共用实体引用解析；不在 UI、校验和运行器重复判断 enemy / obstacle。
static func resolve(project, wave: STGWaveDefinition) -> Resource:
	if project == null or wave == null:
		return null
	match wave.kind:
		"enemy":
			return project.find("bosses", wave.enemy_id)
		"obstacle":
			return project.find("obstacles", wave.obstacle_id)
	return null

static func settings(project, wave: STGWaveDefinition) -> STGEntitySettings:
	var entity = resolve(project, wave)
	return entity.entity_settings if entity != null else null

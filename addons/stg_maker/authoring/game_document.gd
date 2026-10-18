@tool
extends RefCounted
## 制作阶段读取游戏文件：刷新配置数据，复用脚本和场景依赖，避免重复加载执行代码。
const Copy = preload("res://stg/definitions/config_copy.gd")

static func snapshot(game: STGGameDefinition) -> STGGameDefinition:
	# 战斗库来自编辑会话的不可变快照，主角/地图小改动只复制游戏配置，避免逐字段复制全库。
	var result = STGGameDefinition.new()
	result.title = game.title
	result.library = game.library
	result.player = Copy.copy(game.player)
	result.world = Copy.copy(game.world)
	result.start_location_id = game.start_location_id
	return result
static func load_definition(path: String) -> STGGameDefinition:
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as STGGameDefinition
	if loaded == null or loaded.library == null or loaded.library.schema_version != STGProject.VERSION:
		return null
	var library_path = loaded.library.resource_path
	if not library_path.is_empty() and not "::" in library_path:
		# IGNORE 只刷新文档和内嵌资源；外部脚本仍 REUSE。战斗库单独刷新，保持磁盘数据最新。
		var library = ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_IGNORE) as STGProject
		if library == null:
			return null
		preload("res://addons/stg_maker/authoring/asset_store.gd").refresh_library(library)
		library.take_over_path(library_path)
		loaded.library = library
	for key in ["player", "world"]:
		var resource: Resource = loaded.get(key)
		if resource != null and not resource.resource_path.is_empty() and not "::" in resource.resource_path:
			loaded.set(key, ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE))
	return loaded

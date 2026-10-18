@tool
extends RefCounted
## 编辑阶段发现声明；游戏运行直接读取资产引用，不扫描插件目录。
static func list_definitions(kind: String, directory: String = "res://game/extensions") -> Array[STGExtensionDefinition]:
	var result: Array[STGExtensionDefinition] = []
	var folder = DirAccess.open(directory)
	if folder == null: return result
	var files = folder.get_files()
	files.sort()
	for file in files:
		if not file.ends_with(".tres"): continue
		var candidate = load(directory.path_join(file))
		if candidate is STGExtensionDefinition and candidate.kind == kind: result.append(candidate)
	var directories = folder.get_directories()
	directories.sort()
	for child in directories:
		if not child.begins_with("."): result.append_array(list_definitions(kind, directory.path_join(child)))
	return result

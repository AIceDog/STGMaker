@tool
extends RefCounted
## 敌人示例只从正式资源资产提供制作副本；预设是唯一数据来源。
const Loader = preload("res://addons/stg_maker/authoring/document_loader.gd")
const SOURCE = "res://presets/enemy_library.tres"

func build() -> STGProject:
	var loaded = Loader.library(SOURCE)
	if not loaded.issue.is_empty():
		push_error(loaded.issue)
		return null
	return loaded.resource.snapshot()

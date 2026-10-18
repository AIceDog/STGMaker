@tool
extends RefCounted
## FlyTiger Boss 模板只提供当前格式资产的独立快照。
const Loader = preload("res://addons/stg_maker/authoring/document_loader.gd")
const SOURCE = "res://presets/flytiger_bosses.tres"

func build() -> STGProject:
	var loaded = Loader.library(SOURCE)
	if not loaded.issue.is_empty():
		push_error(loaded.issue)
		return null
	return loaded.resource.snapshot()

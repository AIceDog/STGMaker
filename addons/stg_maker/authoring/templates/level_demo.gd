@tool
extends RefCounted
## 完整关卡模板只提供当前格式资产的独立快照；依赖导入由 TemplateImport 负责。
const Loader = preload("res://addons/stg_maker/authoring/document_loader.gd")
const SOURCE = "res://presets/timeline_demo.tres"

func build() -> STGProject:
	var loaded = Loader.library(SOURCE)
	if not loaded.issue.is_empty():
		push_error(loaded.issue)
		return null
	return loaded.resource.snapshot()

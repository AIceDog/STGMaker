@tool
extends "res://stg/definitions/definition_factory.gd"
## 新库保持为空；工厂只在用户明确创建资产时使用。
static func populate(project) -> void: project.schema_version=STGProject.VERSION

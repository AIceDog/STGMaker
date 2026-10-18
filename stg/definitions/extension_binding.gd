@tool
class_name STGExtensionBinding
extends Resource
## 资产中的扩展选择与参数；同一声明可以被多个资产以不同参数复用。
@export var definition: STGExtensionDefinition
@export var parameters: Dictionary = {}

func validate(kind: String) -> PackedStringArray:
	if definition == null: return PackedStringArray(["扩展缺少声明资源"])
	return definition.validate(parameters, kind)

static func create(declaration: STGExtensionDefinition, values: Dictionary = {}) -> Resource:
	# 静态工厂不持有自己的脚本构造器与返回类型，避免 Godot 的类型引用环。
	# 实际返回值仍是 STGExtensionBinding，资源字段和运行协议保持强类型。
	var result = load("res://stg/definitions/extension_binding.gd").new()
	result.definition = declaration
	result.parameters = declaration.parameters_with_defaults(values) if declaration != null else values.duplicate(true)
	return result

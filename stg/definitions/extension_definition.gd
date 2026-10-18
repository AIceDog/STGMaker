@tool
class_name STGExtensionDefinition
extends Resource
## 可序列化扩展声明。implementation 作为 Script 资源引用进入导出依赖闭包。
## 能力声明与实现脚本只读共享；参数和执行对象分别属于资产与运行实例。
const KINDS = ["motion", "emission", "action", "condition", "effect", "player"]
const COLLECTIONS = ["bullets", "barrages", "behaviors", "bosses", "waves", "levels", "obstacles"]
@export_enum("motion", "emission", "action", "condition", "effect", "player") var kind: String = "motion"
@export var sdk_version: int = 1
@export var id: String = ""
@export var title: String = "自定义运动"
@export_multiline var help: String = ""
@export var implementation: Script
# 字段：name、label、type(float/int/bool/string/resource_id)、default；资源 ID 另声明 collection。
@export var fields: Array[Dictionary] = []

func default_parameters() -> Dictionary:
	var result = {}
	for field in fields:
		result[str(field.get("name", ""))] = field.get("default").duplicate(true) if field.get("default") is Dictionary or field.get("default") is Array else field.get("default")
	return result

func parameters_with_defaults(parameters: Dictionary) -> Dictionary:
	var result = default_parameters()
	result.merge(parameters.duplicate(true), true)
	return result

func validate(parameters: Dictionary, expected_kind: String = "") -> PackedStringArray:
	return instantiate(parameters, expected_kind).issues

## 校验和运行实例化共用一次准备；构造函数不会在同一次启动中被调用两遍。
func instantiate(parameters: Dictionary, expected_kind: String = "") -> Dictionary:
	var issues = validate_fields()
	var metadata_valid = issues.is_empty()
	if kind not in KINDS or (not expected_kind.is_empty() and kind != expected_kind):
		issues.append("扩展能力类型不匹配：需要 %s，声明为 %s" % [expected_kind, kind])
	if sdk_version != 1: issues.append("不支持的扩展 SDK 版本：" + str(sdk_version))
	if id.is_empty() or title.is_empty():
		issues.append("扩展必须有稳定 ID 和显示名称")
	var names = []
	var values = parameters_with_defaults(parameters)
	for field in fields:
		var key = str(field.get("name", ""))
		names.append(key)
	# 只有元数据已通过检查，才把 min/max 等交给数值转换和字段校验。
	if metadata_valid:
		for field in fields:
			issues.append_array(_validate_value(field, values.get(str(field.name))))
	for key in parameters:
		if not names.has(key): issues.append("未知扩展参数：" + str(key))
	var instance
	if implementation == null or not implementation.can_instantiate():
		issues.append("缺少有效的能力扩展脚本")
	elif _requires_constructor_arguments(implementation):
		issues.append("扩展构造函数不能要求参数；请在 start 中读取上下文与参数")
	else:
		instance = implementation.new()
		if not _matches(instance):
			issues.append("%s 扩展脚本必须继承 %s" % [kind, {"motion": "STGMotionExtension", "emission": "STGEmissionExtension", "action": "STGActionExtension", "condition": "STGConditionExtension", "effect": "STGEffectExtension", "player": "STGPlayerExtension"}.get(kind, "STGExtension")])
		elif issues.is_empty():
			issues.append_array(instance.validate_parameters(values))
		if instance is Node:
			instance.free()
			instance = null
	return {"issues": issues, "parameters": values, "implementation": instance if issues.is_empty() else null}

static func _requires_constructor_arguments(script: Script) -> bool:
	for method in script.get_script_method_list():
		if method.name == "_init":
			return method.args.size() > method.default_args.size()
	return false

func validate_fields() -> PackedStringArray:
	var issues: PackedStringArray = []
	var names = []
	for field in fields:
		var key = str(field.get("name", ""))
		var kind = str(field.get("type", ""))
		if typeof(field.get("name")) != TYPE_STRING or key.is_empty() or names.has(key):
			issues.append("扩展参数名称为空、类型错误或重复：" + key)
		names.append(key)
		if kind not in ["float", "int", "bool", "string", "resource_id"]:
			issues.append("不支持的参数类型：" + kind)
			continue
		if kind == "resource_id" and field.get("collection", "") not in COLLECTIONS:
			issues.append("资源参数 %s 缺少有效 collection" % key)
		var valid_bounds = true
		if kind in ["float", "int"]:
			for bound in ["min", "max", "step"]:
				if field.has(bound) and not _finite_number(field[bound]):
					issues.append("参数 %s 的 %s 必须是有限数值" % [key, bound])
					valid_bounds = false
			if valid_bounds:
				if float(field.get("min", -INF)) > float(field.get("max", INF)):
					issues.append("参数 %s 的最小值不能大于最大值" % key)
				if field.has("step") and float(field.step) <= 0:
					issues.append("参数 %s 的调整步长必须大于零" % key)
		if valid_bounds:
			issues.append_array(_validate_value(field, field.get("default")))
	return issues

static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))

static func _validate_value(field: Dictionary, value: Variant) -> PackedStringArray:
	var issues: PackedStringArray = []
	var key = str(field.get("name", ""))
	match str(field.get("type", "")):
		"float", "int":
			if not _finite_number(value):
				issues.append("参数 %s 必须是有限数值" % key)
			elif float(value) < float(field.get("min", -INF)) or float(value) > float(field.get("max", INF)):
				issues.append("参数 %s 超出范围" % key)
			elif field.type == "int" and not is_equal_approx(float(value), roundf(float(value))):
				issues.append("参数 %s 必须是整数" % key)
		"bool":
			if typeof(value) != TYPE_BOOL: issues.append("参数 %s 必须是开关值" % key)
		"string", "resource_id":
			if typeof(value) != TYPE_STRING: issues.append("参数 %s 必须是文本" % key)
	return issues

func _matches(instance) -> bool:
	if kind not in KINDS or not instance is RefCounted: return false
	# 校验实际脚本继承关系；按需读取协议，声明类型不静态持有全部能力脚本。
	var protocol: Script = load("res://" + "stg/api/" + kind + "_extension.gd")
	var script: Script = instance.get_script()
	while script != null:
		if script == protocol: return true
		script = script.get_base_script()
	return false

## 参数中的资源 ID 进入同一引用索引，导入重映射、删除保护和编译闭包都能识别。
func references(parameters: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var values = parameters_with_defaults(parameters)
	for field in fields:
		if field.get("type", "") != "resource_id": continue
		var key = str(field.get("name", ""))
		var identifier = str(values.get(key, ""))
		if not identifier.is_empty(): result.append({"owner": parameters, "key": key, "collection": field.get("collection", ""), "id": identifier, "extension": true})
	return result

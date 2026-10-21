@tool
class_name STGBehaviorPreset
extends Resource
## 预设是制作模板；流程节点持有快照，修改模板不反写已创建节点。
@export var id: String = ""
@export var title: String = "新行为预设"
@export_multiline var description: String = ""
@export var program: STGBehaviorProgramDefinition
@export var default_parameters: Dictionary = {}
@export var exposed_parameters: PackedStringArray = []
@export var parameter_options: Dictionary = {}
func parameters(overrides: Dictionary = {}) -> Dictionary:
    var result = program.parameters_with_defaults(default_parameters) if program != null else default_parameters.duplicate(true)
    result.merge(overrides.duplicate(true), true)
    return result
func editable_fields() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if program == null: return result
    var common = STGBehaviorProgramDefinition.common_fields().map(func(field): return field.name)
    for source in program.fields:
        if source.name not in exposed_parameters and source.name not in common: continue
        var field: Dictionary = source.duplicate(true)
        var option = parameter_options.get(source.name, {})
        if not option is Dictionary: option = {}
        for key in ["label", "help", "min", "max", "step"]:
            if option.has(key): field[key] = option[key]
        field["default"] = parameters().get(source.name)
        result.append(field)
    return result
func validate(overrides: Dictionary = {}) -> PackedStringArray:
    var issues = PackedStringArray()
    if id.is_empty() or title.strip_edges().is_empty(): issues.append("行为预设缺少 ID 或名称")
    if program == null: issues.append("行为预设缺少程序声明"); return issues
    issues.append_array(program.validate(parameters(overrides), "behavior"))
    if not issues.is_empty(): return issues
    var names = program.fields.map(func(field): return field.name)
    var editable = editable_fields().map(func(field): return field.name)
    for key in exposed_parameters:
        if key not in names or exposed_parameters.count(key) > 1: issues.append("开放参数不存在或重复："+key)
    for key in overrides:
        if key not in editable: issues.append("未开放的行为参数："+str(key))
    for key in parameter_options:
        if key not in names or not parameter_options[key] is Dictionary: issues.append("行为参数包装无效："+str(key))
    var metadata = STGExtensionDefinition.new()
    metadata.fields = editable_fields()
    issues.append_array(metadata.validate_fields())
    for field in metadata.fields:
        issues.append_array(STGParameterSchema.validate(field, parameters(overrides).get(field.name)))
        var base = program.fields.filter(func(item):return item.name==field.name)[0]
        if field.type in ["float","int"] and (field.get("min",-INF)<base.get("min",-INF) or field.get("max",INF)>base.get("max",INF)):
            issues.append("行为预设范围不能超过程序声明："+field.name)
    return issues

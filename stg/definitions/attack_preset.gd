@tool
class_name STGAttackPreset
extends Resource
## 制作模板；生成招式时复制快照，不实时同步已有招式。
const Copy = preload("res://stg/definitions/config_copy.gd")
@export var id: String = ""
@export var title: String = "新程序预设"
@export var category: String = "自定义"
@export_multiline var description: String = ""
@export var program: STGAttackProgramDefinition
@export var allow_reference_override: bool = true
@export var reference_id: String = ""
@export var default_parameters: Dictionary = {}
@export var exposed_parameters: PackedStringArray = []
@export var parameter_options: Dictionary = {}
func parameters(overrides: Dictionary = {}) -> Dictionary:
    var result = program.parameters_with_defaults(default_parameters) if program != null else default_parameters.duplicate(true)
    result.merge(overrides.duplicate(true), true)
    return result
func fields() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if program == null: return result
    for field in program.fields:
        var entry: Dictionary = field.duplicate(true)
        var option = parameter_options.get(str(field.name), {})
        if not option is Dictionary: option = {}
        for key in ["label", "help", "min", "max", "step"]:
            if option.has(key): entry[key] = option[key]
        entry["default"] = parameters().get(str(field.name))
        result.append(entry)
    return result
func validate(project, overrides: Dictionary = {}, reference_override: String = "") -> PackedStringArray:
    var issues = PackedStringArray()
    if not reference_override.is_empty() and not allow_reference_override: issues.append("预设未开放素材替换")
    if id.is_empty() or title.strip_edges().is_empty(): issues.append("预设缺少 ID 或名称")
    if program == null: issues.append("预设缺少攻击程序"); return issues
    var metadata_issues = program.validate_fields()
    if not metadata_issues.is_empty(): issues.append_array(metadata_issues); return issues
    issues.append_array(program.validate(parameters(overrides), "attack"))
    for reference in program.references(parameters(overrides)):
        if project.find(reference.collection,reference.id)==null: issues.append("程序引用不存在："+reference.collection+":"+reference.id)
    var names = []
    for field in program.fields: names.append(str(field.name))
    for name in exposed_parameters:
        if name not in names or exposed_parameters.count(name)>1: issues.append("开放参数不存在或重复：" + name)
    for name in overrides:
        if name not in exposed_parameters: issues.append("不允许覆盖未开放参数：" + str(name))
    for name in parameter_options:
        if name not in names or not parameter_options[name] is Dictionary: issues.append("参数包装配置无效："+str(name))
    # 包装参数只允许收紧算法边界，不能通过 UI 放宽程序的有效范围。
    var wrapped = STGExtensionDefinition.new()
    wrapped.fields = fields()
    var wrapping_issues = wrapped.validate_fields()
    if not wrapping_issues.is_empty(): issues.append_array(wrapping_issues); return issues
    for index in program.fields.size():
        var base = program.fields[index]
        var field = wrapped.fields[index]
        if str(base.type) in ["int", "float"]:
            if field.get("min",-INF)<base.get("min",-INF) or field.get("max",INF)>base.get("max",INF): issues.append("包装范围不能超出程序边界："+str(base.name))
    var values = parameters(overrides)
    for field in wrapped.fields:
        issues.append_array(STGExtensionDefinition._validate_value(field, values.get(str(field.name))))
    var collection=program.reference_collection()
    var content = project.find(collection, reference_id if reference_override.is_empty() else reference_override)
    if content==null:issues.append("请选择召唤的敌人" if collection=="bosses" else "请选择兼容的子弹素材")
    elif collection=="bullets" and program.capability not in content.supported_capabilities():issues.append("子弹素材形式不适合当前招式")
    return issues

@tool
class_name STGBehaviorProgramDefinition
extends STGExtensionDefinition
## 行为声明与招式声明共享参数系统；所有节点必须显式声明且位于统一目录。
@export var outputs: Array[Dictionary] = [{"id":"completed","label":"完成"},{"id":"failure","label":"失败"}]
@export var capabilities: PackedStringArray = []
@export var branch_mode: String = "none"
@export var variable_outputs: bool = false
@export_enum("none","parallel","sum_branches","references") var child_budget_mode:String="none"
@export var child_flow_fields:PackedStringArray=[]
static func common_fields() -> Array[Dictionary]:
    var result:Array[Dictionary]=[
        {"name":"windup","label":"前摇时间 s","type":"float","default":0.0,"min":0.0,"max":600.0,"step":0.001,"group":"时序与动画"},
        {"name":"execution_duration","label":"执行时间 s","type":"float","default":1.0,"min":0.0,"max":3600.0,"step":0.001,"group":"时序与动画"},
        {"name":"recovery","label":"后摇时间 s","type":"float","default":0.0,"min":0.0,"max":600.0,"step":0.001,"group":"时序与动画"},
        {"name":"active_animation_mode","label":"执行动画播放方式","type":"enum","default":"fit_cycles","values":["fit_cycles","once_hold"],"labels":["循环并对齐执行时间","播一次后保持末帧"],"group":"时序与动画"},
        {"name":"active_cycles","label":"执行动画次数（0 自动）","type":"int","default":0,"min":0,"max":1000000,"step":1,"group":"时序与动画"},
        {"name":"interrupt_on_hit","label":"受击立即中断","type":"bool","default":false,"group":"时序与动画"}]
    for stage in ["windup","active","recovery"]:
        var label={"windup":"前摇","active":"执行中","recovery":"后摇"}[stage]
        result.append({"name":stage+"_animation","label":label+"动画","presentation":"enemy_animation","type":"string","default":"","group":"时序与动画"})
        result.append({"name":stage+"_sound","label":label+"声音","type":"resource","default":null,"resource_class":"AudioStream","group":"时序与动画"})
        result.append({"name":stage+"_volume_db","label":label+"音量 dB","type":"float","default":0.0,"min":-80.0,"max":12.0,"step":0.1,"group":"时序与动画"})
        result.append({"name":stage+"_sound_loop","label":label+"声音循环","type":"bool","default":false,"group":"时序与动画"})
    return result
func _init() -> void:
    kind = "behavior"
    fields = common_fields()
func validate_fields() -> PackedStringArray:
    var issues = super.validate_fields()
    if kind != "behavior": issues.append("行为程序必须声明 behavior 类别")
    if implementation == null or not implementation.resource_path.begins_with("res://stg/behaviors/"):
        issues.append("所有行为节点实现必须位于 stg/behaviors/")
    if not resource_path.is_empty() and not resource_path.begins_with("res://stg/behaviors/"):
        issues.append("行为声明必须位于 stg/behaviors/")
    var ancestor=implementation
    while ancestor!=null and ancestor.resource_path!="res://stg/api/behavior_extension.gd":
        if not ancestor.resource_path.begins_with("res://stg/behaviors/"):
            issues.append("行为节点继承链绕过统一目录");break
        ancestor=ancestor.get_base_script()
    for required in common_fields():
        var found = fields.filter(func(field): return field.get("name") == required.name)
        if found.size() != 1 or found[0].get("type") != required.type:
            issues.append("行为程序缺少公共参数：" + required.name)
        elif required.name in ["windup","execution_duration","recovery"] and (found[0].get("min",-INF)<0 or float(found[0].get("default",0))<0):
            issues.append("节点时长声明必须使用非负边界")
    if child_budget_mode not in ["none","parallel","sum_branches","references"]:issues.append("子流程预算策略无效")
    for key in child_flow_fields:
        var matches=fields.filter(func(field):return field.get("name")==key and field.get("type")=="resource_id" and field.get("collection")=="behaviors")
        if matches.size()!=1:issues.append("子流程预算字段必须声明行为引用："+key)
    var ids = []
    for port in outputs:
        var id = str(port.get("id", ""))
        if id.is_empty() or id in ids or not port.get("label","") is String or str(port.get("label","")).is_empty(): issues.append("行为输出 ID 或名称无效 / 重复")
        ids.append(id)
    if "failure" not in ids or outputs.is_empty(): issues.append("行为程序必须声明失败出口")
    for capability in capabilities:
        if capability not in ["movement", "attack", "children"]: issues.append("未知行为能力：" + capability)
    if branch_mode not in ["none", "children"]: issues.append("行为分支声明无效")
    return issues
func ports(parameters: Dictionary) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if variable_outputs:
        var count=parameters.get("branches",2)
        if not STGParameterSchema.number(count):return result
        for index in clampi(int(count),0,128):
            result.append({"id":"choice_%d" % index,"label":"分支 %d" % (index+1),"role":"child"})
    result.append_array(outputs)
    return result

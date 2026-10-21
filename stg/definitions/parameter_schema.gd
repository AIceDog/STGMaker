@tool
class_name STGParameterSchema
extends RefCounted
## 参数类型的唯一校验入口；资源以 Resource 保存，构建器能直接收集依赖。
const TYPES = ["float","int","bool","string","enum","vector2","color","resource_id","resource","resource_override"]
static func number(v) -> bool: return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v))
static func validate(field: Dictionary, value) -> PackedStringArray:
 var errors=PackedStringArray();var name=str(field.get("name",""));var type=str(field.get("type",""))
 if type not in TYPES:return PackedStringArray(["不支持的参数类型："+type])
 match type:
  "float","int":
   if not number(value):errors.append("必须是有限数值")
   elif value<float(field.get("min",-INF)) or value>float(field.get("max",INF)):errors.append("超出允许范围")
   elif type=="int" and value!=roundf(value):errors.append("必须是整数")
  "bool":
   if not value is bool:errors.append("必须是开关")
  "string","resource_id":
   if not value is String:errors.append("必须是文本或资源 ID")
  "enum":
   if value not in field.get("values",[]):errors.append("不在可选项中")
  "vector2":
   if not value is Vector2 or not value.is_finite():errors.append("必须是有限 XY")
  "color":
   if not value is Color or not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b) or not is_finite(value.a):errors.append("必须是有限颜色")
  "resource","resource_override":
   var resource=value
   if type=="resource_override":
    if not value is Dictionary or value.get("mode","") not in ["inherit","disabled","custom"]:return PackedStringArray([name+"：资源覆盖状态无效"])
    resource=value.get("value") if value.mode=="custom" else null
    if value.mode=="custom" and resource==null:errors.append("自定义覆盖尚未选择资源")
   if resource==null:
    if type=="resource" and not field.get("nullable",true):errors.append("需要选择资源")
   elif not resource is Resource or not resource.is_class(str(field.get("resource_class","Resource"))):errors.append("资源类型必须为 "+str(field.get("resource_class","Resource")))
   elif resource is PackedScene:
    var issue=preload("res://stg/definitions/scene_contract.gd").particles_issue(resource,name!="run_particles_override") if name.ends_with("particles_override") else preload("res://stg/definitions/scene_contract.gd").presentation_issue(resource,"")
    if not issue.is_empty():errors.append(issue)
   elif resource is SpriteFrames:errors.append_array(preload("res://stg/definitions/texture_frames.gd").validate(resource))
 for i in errors.size():errors[i]=name+"："+errors[i]
 return errors

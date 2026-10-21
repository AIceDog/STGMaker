@tool
extends RefCounted
## 编辑器发现程序；成品通过声明的 Script 引用加载，不扫描目录。
const D=preload("res://stg/definitions/definition_factory.gd")
const Copy=preload("res://stg/definitions/config_copy.gd")
static func definitions() -> Array[STGAttackProgramDefinition]:
 var result:Array[STGAttackProgramDefinition]=[]
 var names=DirAccess.get_files_at("res://stg/programs");names.sort()
 var ids={}
 for name in names:
  if not name.ends_with(".tres"):continue
  var resource=load("res://stg/programs/"+name)
  if not resource is STGAttackProgramDefinition:continue
  if ids.has(resource.id):push_error("重复程序 ID："+resource.id);continue
  ids[resource.id]=true;result.append(resource)
 return result
static func preset(program:STGAttackProgramDefinition) -> STGAttackPreset:
 var p=STGAttackPreset.new();p.id=program.id;p.title=program.title;p.program=program;p.default_parameters=program.default_parameters()
 for field in program.fields:p.exposed_parameters.append(str(field.name))
 return p
static func skill(preset_value: STGAttackPreset) -> STGBarrageSkill:
 var result=STGBarrageSkill.new();result.id=D.uid("attack");result.title=preset_value.title;result.description=preset_value.description;result.attack_preset=Copy.copy(preset_value)
 return result

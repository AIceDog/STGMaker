@tool
extends RefCounted
const Factory=preload("res://addons/stg_maker/authoring/attack_presets.gd")
const Fields=preload("res://addons/stg_maker/ui/attack_parameter_fields.gd")
const Form=preload("res://addons/stg_maker/ui/form_scene.gd")
static func choices(host) -> Array:
 var result=[]
 for program in Factory.definitions():result.append(Factory.preset(program))
 result.append_array(host.session.project.attack_presets)
 var current=host.current()
 if current is STGBarrageSkill and current.attack_preset!=null and not result.any(func(p):return p.id==current.attack_preset.id):result.append(current.attack_preset)
 return result
static func build(host,parent,skill:STGBarrageSkill) -> void:
 var view=load("res://addons/stg_maker/ui/forms/barrage_properties.tscn").instantiate();view.theme=null;parent.add_child(view);Form.snapshot(view)
 var preset=skill.attack_preset
 var title:LineEdit=view.get_node("%Title");title.text=skill.title
 var commit=func():
  if host.current()!=null and title.text!=host.current().title:host.edit_path([],"title",title.text)
 title.text_submitted.connect(func(_v):commit.call());title.focus_exited.connect(commit)
 var available=choices(host);var select:OptionButton=view.get_node("%Program")
 for p in available:select.add_item(p.title)
 for i in available.size():
  if available[i].id==preset.id:select.select(i)
 select.item_selected.connect(func(index):switch_type(host,available[index]))
 var ids:Array=[""];var labels:Array=["请选择引用内容"]
 var collection=preset.program.reference_collection()
 for resource in host.session.project.get(collection):
  if collection=="bosses" or preset.program.capability in resource.supported_capabilities():ids.append(resource.id);labels.append(resource.title)
 var reference:OptionButton=view.get_node("%Reference")
 for label in labels:reference.add_item(label)
 var effective=preset.reference_id if skill.reference_override.is_empty() else skill.reference_override
 reference.select(maxi(0,ids.find(effective)));reference.disabled=not preset.allow_reference_override
 view.get_node("%ReferenceLabel").text="召唤的敌人" if collection=="bosses" else "子弹素材"
 reference.item_selected.connect(func(index):host.edit_configuration([],func(target,_p):
  target.attack_preset.reference_id=ids[index];target.reference_override="",true,"reference"))
 view.get_node("%EditReference").pressed.connect(func():
  var s=host.current();var id=s.attack_preset.reference_id if s.reference_override.is_empty() else s.reference_override
  if not id.is_empty():host.edit_reference(s.attack_preset.program.reference_collection(),id))
 var groups={};var values=preset.parameters(skill.program_parameters)
 for field in preset.fields():
  if str(field.name) not in preset.exposed_parameters:continue
  var group=str(field.get("group","参数"))
  if not groups.has(group):groups[group]=_group(view.get_node("%Parameters"),group)
  var key=str(field.name)
  Fields.add(groups[group],field,values.get(key),func(value):host.edit_configuration([],func(target,_p):target.program_parameters[key]=value,false,key),host.session.project)
 view.get_node("%Maker").pressed.connect(host.open_attack_presets)
 var issues=preset.validate(host.session.project,skill.program_parameters,skill.reference_override)
 view.get_node("%Status").text="；".join(issues)
 Form.apply_display(view,host.get_meta("display_unit",1.0),host.Display)
static func _group(parent:Node,title:String) -> Node:return preload("res://addons/stg_maker/ui/fields.gd").group(parent,title)
static func switch_type(host,source:STGAttackPreset) -> void:
 var Copy=preload("res://stg/definitions/config_copy.gd")
 host.edit_configuration([],func(skill,project):
  var old=skill.attack_preset.reference_id if skill.reference_override.is_empty() else skill.reference_override
  var reference=project.find(source.program.reference_collection(),old)
  var compatible=reference!=null and (source.program.reference_collection()=="bosses" or source.program.capability in reference.supported_capabilities())
  skill.attack_preset=Copy.copy(source)
  if source.allow_reference_override:skill.attack_preset.reference_id=old if compatible else ""
  skill.reference_override="";skill.program_parameters.clear(),true,"program")
static func sync(host) -> void:
 var skill=host.current()
 if skill is STGBarrageSkill and skill.attack_preset!=null:
  Fields.sync(host.inspector,skill.attack_preset.parameters(skill.program_parameters))
  for child in host.inspector.get_children():
   var title=child.get_node_or_null("%Title")
   if title!=null and title.text!=skill.title:title.text=skill.title
   var status=child.get_node_or_null("%Status")
   if status!=null:status.text="；".join(skill.attack_preset.validate(host.session.project,skill.program_parameters,skill.reference_override))

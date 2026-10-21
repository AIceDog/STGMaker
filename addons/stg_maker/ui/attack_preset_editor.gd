@tool
extends Window
const Factory=preload("res://addons/stg_maker/authoring/attack_presets.gd")
const Fields=preload("res://addons/stg_maker/ui/attack_parameter_fields.gd")
const F=preload("res://addons/stg_maker/ui/fields.gd")
const Form=preload("res://addons/stg_maker/ui/form_scene.gd")
var host
var view:Control
var selected_id:String=""
var programs:Array=[]
var structure:Array=[]
var syncing:bool=false
func current() -> STGAttackPreset:return host.session.project.find("attack_presets",selected_id) if host!=null else null
func open_for(workspace) -> void:
 host=workspace;title="程序预设制作";theme=host.theme
 view=load("res://addons/stg_maker/ui/forms/attack_preset_editor.tscn").instantiate();view.theme=null;add_child(view);Form.snapshot(view)
 size=Vector2i(1100,800);min_size=Vector2i(800,600)
 close_requested.connect(func():commit_pending();hide());view.get_node("%Close").pressed.connect(func():commit_pending();hide())
 view.get_node("%New").pressed.connect(_new)
 view.get_node("%Remove").pressed.connect(func():
  var id=selected_id;host.session.edit(func(p):p.attack_presets=p.attack_presets.filter(func(item):return item.id!=id)))
 view.get_node("%Undo").pressed.connect(func():commit_pending();host.session.undo())
 view.get_node("%Redo").pressed.connect(func():commit_pending();host.session.redo())
 view.get_node("%Save").pressed.connect(func():commit_pending();host.save_project())
 view.get_node("%CreateSkill").pressed.connect(func():
  commit_pending()
  if current()!=null:host.add_program_attack(selected_id);hide())
 view.get_node("%List").item_selected.connect(func(i):commit_pending();selected_id=view.get_node("%List").get_item_metadata(i);structure.clear();_sync())
 for pair in [["Name","title"],["Category","category"],["Description","description"]]:
  var control=view.get_node("%"+pair[0])
  var commit=func():
   if current()!=null and current().get(pair[1])!=control.text:_edit(func(p):p.set(pair[1],control.text))
  control.focus_exited.connect(commit)
  if control is LineEdit:control.text_submitted.connect(func(_text):commit.call())
 view.get_node("%Program").item_selected.connect(func(i):
  var program=programs[i]
  _edit(func(p):
   p.program=program;p.default_parameters=program.default_parameters();p.reference_id="";p.parameter_options.clear();p.exposed_parameters.clear()
   for field in program.fields:p.exposed_parameters.append(str(field.name)),true))
 view.get_node("%Material").item_selected.connect(func(i):
  var id=view.get_node("%Material").get_item_metadata(i);_edit(func(p):p.reference_id=id))
 view.get_node("%MaterialOverride").toggled.connect(func(v):
  if not syncing:_edit(func(p):p.allow_reference_override=v))
 host.session.changed.connect(_sync);_sync();apply_workspace_display(host.get_meta("display_unit",1.0));popup_centered_clamped(size,.85)
func _new() -> void:
 commit_pending()
 var p=Factory.preset(Factory.definitions()[0]);p.id=host.Commands.Defaults.uid("preset");p.title="新程序预设";selected_id=p.id
 host.session.edit(func(project):project.attack_presets.append(p))
func _edit(change:Callable,rebuild:bool=false,key:String="") -> void:
 if current()==null:return
 var id=selected_id
 host.session.edit_asset("attack_presets",id,func(project):change.call(project.find("attack_presets",id)),{"structure":false,"collection":"attack_presets","id":id,"field":key})
 if rebuild:structure.clear();_sync()
func commit_pending() -> void:
 var focus=gui_get_focus_owner()
 if focus!=null:focus.release_focus()
func _sync() -> void:
 if syncing or view==null:return
 syncing=true
 if current()==null:selected_id=host.session.project.attack_presets[0].id if not host.session.project.attack_presets.is_empty() else ""
 var list:ItemList=view.get_node("%List");list.clear()
 for p in host.session.project.attack_presets:
  list.add_item(p.title);list.set_item_metadata(list.item_count-1,p.id)
  if p.id==selected_id:list.select(list.item_count-1)
 view.get_node("%Undo").disabled=host.session.undo_stack.is_empty();view.get_node("%Redo").disabled=host.session.redo_stack.is_empty()
 var p=current();view.get_node("%Properties").visible=p!=null
 view.get_node("%Remove").disabled=p==null;view.get_node("%CreateSkill").disabled=p==null
 if p==null:view.get_node("%Status").text="新建预设后选择程序和开放参数。";syncing=false;return
 for pair in [["Name",p.title],["Category",p.category],["Description",p.description]]:
  var c=view.get_node("%"+pair[0])
  if c.text!=pair[1]:c.text=pair[1]
 view.get_node("%MaterialOverride").set_pressed_no_signal(p.allow_reference_override)
 var key=[p.id,p.program,p.parameter_options,host.session.project.bullets.map(func(m):return [m.id,m.title,m.form]),host.session.project.bosses.map(func(m):return [m.id,m.title])]
 if key!=structure:structure=key.duplicate(true);_rebuild(p)
 Fields.sync(view.get_node("%Parameters"),p.parameters())
 for checkbox in view.get_node("%Parameters").find_children("*","CheckBox",true,false):
  if checkbox.has_meta("exposed_key"):checkbox.set_pressed_no_signal(str(checkbox.get_meta("exposed_key")) in p.exposed_parameters)
 view.get_node("%Status").text="；".join(p.validate(host.session.project))
 syncing=false
func _rebuild(p:STGAttackPreset) -> void:
 programs=Factory.definitions()
 if p.program!=null and not programs.has(p.program):programs.append(p.program)
 var select:OptionButton=view.get_node("%Program");select.clear()
 for program in programs:select.add_item(program.title)
 select.select(programs.find(p.program))
 select=view.get_node("%Material");select.clear();select.add_item("请选择引用内容");select.set_item_metadata(0,"")
 var collection=p.program.reference_collection()
 for source in host.session.project.get(collection):
  if collection=="bosses" or p.program.capability in source.supported_capabilities():
   select.add_item(source.title);select.set_item_metadata(select.item_count-1,source.id)
   if source.id==p.reference_id:select.select(select.item_count-1)
 view.get_node("%MaterialLabel").text="召唤敌人" if collection=="bosses" else "兼容子弹素材"
 var box=view.get_node("%Parameters")
 F.close_popups(box)
 for child in box.get_children():box.remove_child(child);child.queue_free()
 for field in p.fields():
  var field_key=str(field.name);var card=F.group(box,str(field.get("label",field_key)))
  var base=p.program.fields.filter(func(f):return f.name==field_key)[0].duplicate(true)
  Fields.add(card,base,p.parameters().get(field_key),func(v):_edit(func(target):target.default_parameters[field_key]=v,false,field_key),host.session.project)
  var checkbox=CheckBox.new();checkbox.text="向策划开放";checkbox.set_meta("exposed_key",field_key);card.add_child(checkbox);checkbox.set_pressed_no_signal(field_key in p.exposed_parameters)
  checkbox.toggled.connect(func(enabled):_edit(func(target):
   if enabled and field_key not in target.exposed_parameters:target.exposed_parameters.append(field_key)
   elif not enabled:target.exposed_parameters.erase(field_key)))
  for option in ["label","help"]:
   F.text(card,"显示名称" if option=="label" else "参数说明",str(field.get(option,"")),func(v):_option(field_key,option,v))
  if field.type in ["float","int"]:
   for option in ["min","max"]:
    F.number(card,"允许最小值" if option=="min" else "允许最大值",field.get(option,0),func(v):_option(field_key,option,v),-100000,100000)
 apply_workspace_display(host.get_meta("display_unit",1.0))
func _option(key:String,property:String,value) -> void:
 _edit(func(p):
  if not p.parameter_options.has(key):p.parameter_options[key]={}
  p.parameter_options[key][property]=value,true)
func apply_workspace_display(unit:float) -> void:
 if view==null:return
 Form.apply_display(view,unit,host.Display)
 for child in view.find_children("*","Control",true,false):
  if child.get_meta("form_fragment",false):Form.apply_display(child,unit,host.Display)
func _exit_tree() -> void:
 if is_instance_valid(host) and host.session.changed.is_connected(_sync):host.session.changed.disconnect(_sync)

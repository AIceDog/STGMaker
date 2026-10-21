extends SceneTree
const Fixture=preload("res://tests/unified14_fixture.gd")
var checks=0
var failures=0
var studio
func _initialize():run.call_deferred()
func frames(n=4):
 for i in n:await process_frame
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func parameter(key:String):
 for node in studio.inspector.find_children("*","Control",true,false):
  if node.get_meta("program_parameter","")==key:return node
 return null
func run():
 root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
 studio=load("res://addons/stg_maker/studio.tscn").instantiate();studio.restore_last_project=false;studio.settings_path="user://unified14_test.cfg"
 root.add_child(studio);await frames(8)
 check(studio.session.project.barrages.is_empty() and studio.canvas.world.issue.is_empty(),"真实空库冷启动")
 studio.session.project=Fixture.project();studio.selected_id="fan";studio.collection="barrages";studio.refresh(true);await frames()
 check(studio.inspector_tabs.tab_count==1 and studio.inspector_tabs.get_tab_title(0)=="招式参数","仅有统一参数页")
 check(parameter("damage")!=null and parameter("expire_clip_override")!=null and parameter("end_sound")!=null,"伤害和收尾资源在通用参数区")
 var input=parameter("angle");var id=input.get_instance_id();input.value=90;await frames()
 check(studio.current().program_parameters.angle==90 and parameter("angle").get_instance_id()==id,"角度180→90且控件复用")
 studio.undo_edit();await frames();check(parameter("angle").value==180,"撤销角度")
 studio.redo_edit();await frames();check(parameter("angle").value==90,"重做角度")
 var before=studio.current().attack_preset.reference_id
 var choice=load("res://addons/stg_maker/authoring/attack_presets.gd").preset(load("res://stg/programs/homing.tres"))
 load("res://addons/stg_maker/ui/barrage_inspector.gd").switch_type(studio,choice);await frames()
 check(studio.current().program_parameters.is_empty() and studio.current().attack_preset.reference_id==before,"切换同类程序保留兼容引用并重置参数")
 choice=load("res://addons/stg_maker/authoring/attack_presets.gd").preset(load("res://stg/programs/summon.tres"))
 load("res://addons/stg_maker/ui/barrage_inspector.gd").switch_type(studio,choice);await frames()
 check(studio.current().attack_preset.reference_id.is_empty(),"切换召唤清空不兼容引用")
 studio.undo_edit();await frames()
 var resource=parameter("expire_clip_override");resource.mode.select(1);resource.mode.item_selected.emit(1);await frames()
 check(studio.current().program_parameters.expire_clip_override.mode=="disabled","资源禁用独立于继承")
 resource.clear.pressed.emit();await frames()
 check(studio.current().program_parameters.expire_clip_override.mode=="disabled" and studio.current().program_parameters.expire_clip_override.value==null,"资源清除可独立保存")
 resource.mode.select(0);resource.mode.item_selected.emit(0);await frames()
 check(studio.current().program_parameters.expire_clip_override.mode=="inherit","禁用后可切回沿用素材")
 var reference=studio.inspector.get_child(0).get_node("%Reference")
 reference.select(0);reference.item_selected.emit(0);await frames()
 check(studio.current().attack_preset.reference_id.is_empty() and studio.current().reference_override.is_empty(),"素材引用可明确清除")
 studio.undo_edit();await frames()
 var save_path="user://unified14_ui_%d/library.tres"%Time.get_ticks_usec()
 check(studio.session.save(save_path).is_empty() and studio.session.open(save_path).is_empty(),"统一参数和覆盖状态保存重开")
 await frames()
 studio.open_attack_presets();await frames();var maker=studio.attack_preset_editor;maker._new();await frames()
 check(maker.current()!=null and maker.current().program!=null,"空项目可创建预设包装")
 check(maker.view.get_node_or_null("%Damage")==null and maker.view.get_node_or_null("%SpawnSound")==null,"制作页没有固定伤害或音效栏")
 maker.hide()
 studio.new_game_configuration();await frames()
 check(studio.game_project_panel.game.world.locations.is_empty() and studio.game_project_panel.game.library.barrages.size()==studio.session.project.barrages.size(),"新游戏配置不隐式填入关卡或示例")
 studio.game_project_panel.hide()
 var folder="res://tests/.test_run_logs/unified14_ui";DirAccess.make_dir_recursive_absolute(folder)
 for skill in studio.session.project.barrages:
  if skill.id=="fan":continue
  studio.select_resource(skill.id);await frames()
  check(studio.canvas.world.issue.is_empty(),"切换程序页面："+skill.id+studio.canvas.world.issue)
  for tick in 90:studio.canvas.world.step()
  await frames()
  RenderingServer.force_draw(false);root.get_texture().get_image().save_png(folder+"/"+skill.id+".png")
 studio.session.recoverable_changes=false;studio.queue_free();await frames(8)
 print("UNIFIED14 UI RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

@tool
extends EditorPlugin
## 真实工具脚本环境验证新程序和制作页；不修改源资产或用户偏好。
var checks=0
var failures=0
func _enter_tree():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func frames(n=8):
 for i in n:await get_tree().process_frame
func run():
 await frames(30)
 var filesystem=EditorInterface.get_resource_filesystem()
 var started=Time.get_ticks_msec()
 while filesystem!=null and filesystem.is_scanning() and Time.get_ticks_msec()-started<20000:await frames(1)
 check(filesystem==null or not filesystem.is_scanning(),"编辑器完成资源扫描后开始程序检查")
 var candidates=EditorInterface.get_editor_main_screen().find_children("*","Control",true,false).filter(func(n):return n.get_script()==load("res://addons/stg_maker/ui/studio_workspace.gd") and n.workspace_active)
 check(candidates.size()==1,"真实插件存在唯一工坊实例")
 if candidates.size()==1:
  var studio=candidates[0]
  var isolated=load("res://addons/stg_maker/ui/session.gd").new()
  isolated.recovery_folder="user://attack_sdk_editor_drafts"
  isolated.create()
  isolated.project=preload("res://tests/unified14_fixture.gd").project()
  studio.session=isolated;isolated.changed.connect(studio._document_changed)
  studio.show_trajectories=false
  studio.reset_selection();studio.show_collection("barrages")
  EditorInterface.set_main_screen_editor("STGMaker")
  await frames()
  for skill in studio.session.project.barrages:
   studio.select_resource(skill.id)
   await frames()
   for tick in 24:studio.canvas.world.step()
   await frames(4)
   check(studio.canvas.world.issue.is_empty() and (not studio.canvas.world.actors.is_empty() or not studio.canvas.world.summons.is_empty()),"工具脚本模式执行程序："+skill.title+studio.canvas.world.issue)
   check(studio.inspector_tabs.tab_count==1,"插件按声明装配程序参数页")
  studio.open_attack_presets()
  studio.attack_preset_editor._new()
  await frames()
  check(studio.attack_preset_editor.current()!=null,"真实插件可打开预设制作页")
  var folder="res://tests/.test_run_logs/attack_program_ui"
  DirAccess.make_dir_recursive_absolute(folder)
  RenderingServer.force_draw(false)
  studio.attack_preset_editor.get_texture().get_image().save_png(folder+"/plugin_maker.png")
  studio.attack_preset_editor.hide()
  await matrix(studio)
  await showcase(studio)
  await behavior_contract(studio)
  await preload("res://tests/ui_input_regression.gd").run(studio,check,"plugin")
  studio.session.recoverable_changes=false
 print("ATTACK PROGRAM EDITOR RESULT: %d checks, %d failures"%[checks,failures])
 # 退出放到异步检查栈返回之后，避免帧信号中的协程仍持有工具脚本。
 finish.call_deferred()
func finish():
 preload("res://tests/editor_shutdown.gd").request(self)

func matrix(studio):
 var window=get_tree().root;var original=window.size
 var distraction=EditorInterface.is_distraction_free_mode_enabled();EditorInterface.set_distraction_free_mode(true)
 var folder="res://tests/.test_run_logs/render_matrix";DirAccess.make_dir_recursive_absolute(folder)
 for dimensions in [Vector2i(1100,760),Vector2i(1440,900),Vector2i(2560,1440)]:
  window.size=dimensions
  for scale in [100,150,200]:
   studio.set_ui_scale(scale,false);await frames()
   check(studio.play_button.is_visible_in_tree() and studio.save_button.get_theme_font_size("font_size")>=18,"插件入口与字体：%s %d"%[dimensions,scale])
   check(studio.canvas.size.x>=320 and studio.canvas.size.y>=260,"插件画布可用：%s %d"%[dimensions,scale])
   var scroll:ScrollContainer=studio.get_node("WorkspaceScroll");scroll.scroll_horizontal=100000;await frames(4)
   check(studio.inspector_scroll.get_global_rect().intersects(studio.get_global_rect()),"插件放大后可滚动到达参数区")
   RenderingServer.force_draw(false);window.get_texture().get_image().save_png(folder+"/plugin_%dx%d_%d.png"%[dimensions.x,dimensions.y,scale]);scroll.scroll_horizontal=0
 studio.set_ui_scale(100,false);window.size=original;EditorInterface.set_distraction_free_mode(distraction)

func showcase(studio):
 var path="res://projects/attack_showcase/library.tres";var hash=FileAccess.get_sha256(path)
 studio.session.recoverable_changes=false;studio.session.project=load(path).snapshot()
 studio.show_collection("barrages",studio.session.project.barrages[0].id);studio.set_pixel_art(true,false);studio.set_font_size(0,false);studio.set_ui_scale(100,false)
 var folder="res://tests/.test_run_logs/attack_showcase";DirAccess.make_dir_recursive_absolute(folder)
 for index in studio.session.project.barrages.size():
  var skill=studio.session.project.barrages[index];studio.select_resource(skill.id);await frames(3)
  for tick in [60,108,174,84,108,360,114,62,336,108][index]:studio.canvas.world.step()
  studio.update_preview_ui();await frames(2)
  check(studio.canvas.world.issue.is_empty(),"真实插件运行像素招式："+skill.title+studio.canvas.world.issue)
  if index in [6,7,8,9]:
   RenderingServer.force_draw(false);get_tree().root.get_texture().get_image().save_png(folder+"/plugin_%02d.png"%(index+1))
 studio.show_collection("bosses","showcase_emitter");studio.set_boss_view("battle")
 studio.show_collection("behaviors","showcase_body_flow");await frames()
 check(studio.flow_editor.is_visible_in_tree(),"真实插件进入行为子流程显示节点图")
 studio.set_boss_view("battle");studio.refresh(false);await frames()
 check(studio.canvas.is_visible_in_tree() and not studio.flow_editor.is_visible_in_tree(),"真实插件普通刷新不改变当前视图")
 studio.select_resource("showcase_geometry_flow");await frames()
 check(studio.flow_editor.is_visible_in_tree(),"真实插件切换子流程恢复节点图")
 RenderingServer.force_draw(false);get_tree().root.get_texture().get_image().save_png(folder+"/plugin_behavior.png")
 check(FileAccess.get_sha256(path)==hash,"真实插件不改写展示源资源")
 studio.session.recoverable_changes=false

func behavior_contract(studio):
 await preload("res://tests/behavior16_ui_regression.gd").run(studio,check,"plugin")
 var D=preload("res://stg/definitions/definition_factory.gd")
 studio.session.project=preload("res://tests/unified14_fixture.gd").project()
 studio.show_collection("bosses","enemy")
 for name in ["dash","teleport","orbit"]:
  var parameters={"windup":.02,"recovery":.02}
  if name!="teleport":parameters.execution_duration=.1
  var node=D.flow_node(name,parameters)
  studio.session.edit(func(project):project.bosses[0].phases[0].behavior_flow=D.flow([node]);project.bosses[0].phases[0].loop=false)
  studio.flow_node_id=node.id;studio.inspector_tab=1;studio.refresh(true);await frames()
  for tick in 24:studio.canvas.world.step()
  check(studio.canvas.world.issue.is_empty() and studio.canvas.world.boss.is_finite(),"真实插件 @tool 运行行为节点："+name)
  check(studio.inspector_tabs.is_tab_disabled(1)==false,"所有节点前后摇页可用")
  var controls=studio.inspector.find_children("*","Control",true,false)
  check(controls.any(func(control):return control.get_meta("program_parameter","")=="windup"),"插件由声明生成公共参数")
 var preset=D.behavior_preset(load("res://stg/behaviors/dash.tres"));preset.id="plugin_behavior_preset"
 studio.session.edit(func(project):project.behavior_presets.append(preset))
 preload("res://addons/stg_maker/ui/behavior_node_fields.gd").open_presets(studio,preset.id);await frames()
 var editor
 for child in studio.get_children():
  if child is Window and child.get_script()!=null and child.get_script().resource_path.ends_with("behavior_preset_editor.gd"):editor=child
 check(editor!=null and editor.visible,"真实插件可打开行为预设制作窗口")
 if editor!=null:
  var folder="res://tests/.test_run_logs/behavior15";DirAccess.make_dir_recursive_absolute(folder)
  RenderingServer.force_draw(false);editor.get_texture().get_image().save_png(folder+"/plugin_presets.png")
  editor.queue_free();await frames()
 RenderingServer.force_draw(false);get_tree().root.get_texture().get_image().save_png("res://tests/.test_run_logs/behavior15/plugin_timing.png")
 studio.session.recoverable_changes=false

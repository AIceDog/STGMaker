extends SceneTree
const PATH="res://projects/attack_showcase/library.tres"
const Commands=preload("res://addons/stg_maker/ui/flow_commands.gd")
var checks=0
var failures=0
var studio
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func frames(n=4):
 for i in n:await process_frame
func run():
 root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
 var hash=FileAccess.get_sha256(PATH);var prefs=FileAccess.get_sha256("user://stg_maker.cfg") if FileAccess.file_exists("user://stg_maker.cfg") else ""
 studio=load("res://addons/stg_maker/studio.tscn").instantiate();studio.restore_last_project=false;studio.settings_path="user://showcase_ui_diagnostic.cfg";root.add_child(studio);await frames()
 check(studio.session.project.barrages.is_empty(),"工坊启动仍为空白")
 check(studio.session.open(PATH).is_empty(),"正常会话打开展示库")
 studio.show_collection("barrages",studio.session.project.barrages[0].id);studio.set_pixel_art(true,false);studio.set_font_size(0,false);studio.set_ui_scale(100,false);studio.canvas.set_trajectories_visible(false);await frames()
 var folder="res://tests/.test_run_logs/attack_showcase";DirAccess.make_dir_recursive_absolute(folder)
 var ticks=[60,108,174,84,108,360,114,62,336,108]
 var ids=studio.session.project.barrages.map(func(skill):return skill.id)
 for index in ids.size():
  studio.select_resource(ids[index]);await frames(2)
  for tick in ticks[index]:studio.canvas.world.step()
  studio.update_preview_ui();await frames(2)
  check(studio.inspector_tabs.tab_count==1 and studio.canvas.world.issue.is_empty(),"像素招式页面与真实渲染："+studio.current().title+studio.canvas.world.issue)
  check(studio.canvas.world.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"像素素材使用最近邻预览")
  RenderingServer.force_draw(false);root.get_texture().get_image().save_png(folder+"/standalone_%02d.png"%(index+1))
 studio.show_collection("bosses","showcase_emitter");await frames();studio.set_boss_view("battle")
 studio.show_collection("behaviors","showcase_body_flow");await frames()
 check(studio.flow_editor.is_visible_in_tree() and studio.boss_view=="flow","从敌人战斗预览进入子流程默认节点图")
 check(studio.flow_editor.graph.get_connection_list().size()>=6,"六种弹丸在原GraphEdit中有顺序连线")
 studio.select_flow_node(studio.boss_flow().entry_id);Commands.add(studio,"wait");await frames()
 var inserted=studio.flow_node_id
 check(studio.boss_flow().nodes.size()==7 and studio.boss_node().behavior_preset.program.id=="behavior.wait","子流程原节点编辑器可插入等待")
 Commands.duplicate_node(studio);await frames();check(studio.boss_flow().nodes.size()==8,"复制节点")
 Commands.remove(studio);await frames();check(studio.boss_flow().nodes.size()==7,"删除节点")
 studio.undo_edit();await frames();check(studio.boss_flow().nodes.size()==8,"撤销恢复节点")
 studio.redo_edit();await frames();check(studio.boss_flow().nodes.size()==7,"重做删除节点")
 Commands.arrange(studio);await frames()
 var entry=studio.boss_flow().entry_id
 studio.flow_editor.graph.connection_request.emit("entry",0,inserted,0);await frames()
 check(studio.boss_flow().entry_id==inserted,"真实连线信号进入编辑事务")
 studio.undo_edit();await frames();check(studio.boss_flow().entry_id==entry,"撤销恢复连线")
 studio.select_flow_node(inserted);studio.set_boss_view("battle");studio.edit_configuration(["nodes",studio.boss_flow().index_of(inserted)],func(node,_project):node.program_parameters.execution_duration=.2,true);await frames()
 check(studio.canvas.is_visible_in_tree() and not studio.flow_editor.is_visible_in_tree(),"普通参数刷新保持主动选择的战斗预览")
 studio.select_resource("showcase_geometry_flow");await frames()
 check(studio.flow_editor.is_visible_in_tree() and studio.boss_flow().nodes.size()==4,"切换另一个子流程默认节点图")
 RenderingServer.force_draw(false);root.get_texture().get_image().save_png(folder+"/standalone_behavior.png")
 await preload("res://tests/ui_input_regression.gd").run(studio,check,"standalone")
 studio.session.recoverable_changes=false;studio.queue_free();await frames(5)
 check(FileAccess.get_sha256(PATH)==hash,"图编辑只修改会话，不覆盖展示源库")
 check((FileAccess.get_sha256("user://stg_maker.cfg") if FileAccess.file_exists("user://stg_maker.cfg") else "")==prefs,"像素预览不改写全局用户偏好")
 print("ATTACK SHOWCASE UI RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

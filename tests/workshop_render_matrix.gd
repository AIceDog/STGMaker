extends SceneTree
## 实际渲染器：三种窗口尺寸 × 三种缩放，保持真实静态布局与操作入口。
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func frames():
 for i in 6:await process_frame
func run():
 var studio=load("res://addons/stg_maker/studio.tscn").instantiate()
 studio.restore_last_project=false
 studio.settings_path="user://matrix_isolated.cfg"
 studio.show_trajectories=false
 root.add_child(studio)
 studio.set_font_size(0,false)
 await frames()
 studio.session.project=preload("res://tests/unified14_fixture.gd").project();studio.selected_id="fan";studio.collection="barrages";studio.refresh(true)
 var folder="res://tests/.test_run_logs/render_matrix"
 DirAccess.make_dir_recursive_absolute(folder)
 for dimensions in [Vector2i(1100,760),Vector2i(1440,900),Vector2i(2560,1440)]:
  root.size=dimensions
  for percent in [100,150,200]:
   studio.set_ui_scale(percent,false)
   await frames()
   var label="%dx%d_%d"%[dimensions.x,dimensions.y,percent]
   check(studio.size.is_equal_approx(Vector2(dimensions)),"工作台挂载完整窗口："+label)
   check(studio.save_button.get_theme_font_size("font_size")>=18,"字号清晰："+label)
   check(studio.play_button.is_visible_in_tree() and studio.inspector_scroll.is_visible_in_tree() and studio.library_panel.is_visible_in_tree(),"保留播放、属性与资源入口："+label)
   check(studio.canvas.size.x>=320 and studio.canvas.size.y>=260,"可用画布："+label)
   check(studio.inspector_scroll.get_v_scroll_bar()!=null,"长属性可滚动："+label)
   RenderingServer.force_draw(false)
   root.get_texture().get_image().save_png(folder+"/standalone_"+label+".png")
   var scroll:ScrollContainer=studio.get_node("WorkspaceScroll")
   scroll.scroll_horizontal=100000
   await frames()
   check(studio.inspector_scroll.get_global_rect().intersects(Rect2(Vector2.ZERO,Vector2(root.size))),"放大后滚动可到达属性栏："+label)
   RenderingServer.force_draw(false)
   if percent==200:root.get_texture().get_image().save_png(folder+"/standalone_right_"+label+".png")
   scroll.scroll_horizontal=0
 studio.session.recoverable_changes=false
 studio.queue_free();await frames()
 print("WORKSHOP RENDER MATRIX RESULT: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)

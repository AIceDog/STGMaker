@tool
extends RefCounted
## 同时由真实插件和独立工坊运行；检查原生弹窗所有权与自动提示的输入边界。
static func frames(studio,n=2):
 for i in n:await studio.get_tree().process_frame
static func parameter(studio,key):
 for node in studio.inspector.find_children("*","Control",true,false):
  if node.get_meta("program_parameter","")==key:return node
 return null
static func run(studio,check:Callable,prefix:String):
 var original_process=studio.is_processing();studio.set_process(false)
 var hash=FileAccess.get_sha256("res://projects/attack_showcase/library.tres")
 studio.show_collection("barrages","showcase_01_five_shot");await frames(studio)
 studio.playing=true;studio.accumulator=0;studio._advance_preview(.3)
 check.call(not studio.playing and studio.preview_notice.contains("0.25") and studio.preview_status.text.contains("已暂停") and studio.preview_status.is_visible_in_tree(),prefix+"负载保护保留并在现有状态栏提示")
 check.call(not studio.message_dialog.visible and studio.get_last_exclusive_window()==studio.get_window(),prefix+"自动提示不创建排他窗口或拦截输入")
 await frames(studio,3) # 等容器布局与可见状态真正渲染后截图。
 RenderingServer.force_draw(false)
 studio.get_tree().root.get_texture().get_image().save_png("res://tests/.test_run_logs/attack_showcase/"+prefix+"_nonmodal_pause.png")
 studio.toggle_play()
 check.call(studio.playing and studio.preview_notice.is_empty() and not studio.message_dialog.visible,prefix+"负载提示可由恢复测试按钮解除")
 studio.toggle_play()
 studio.bullet_button.pressed.emit();await frames(studio)
 check.call(studio.collection=="bullets" and studio.current()!=null,prefix+"负载暂停后其他导航按钮继续工作")
 studio.show_collection("barrages","showcase_01_five_shot");await frames(studio)
 studio.playing=true;studio.accumulator=.01
 var time=studio.canvas.world.time
 studio._suspend_preview_clock();studio._process(.5)
 check.call(studio.playing and studio.canvas.world.time==time and is_equal_approx(studio.accumulator,.01),prefix+"失焦期间不推进时钟或丢弃已累积的固定步长")
 studio._resume_preview_clock();studio._process(.5)
 check.call(studio.playing and studio.preview_notice.is_empty() and is_equal_approx(studio.canvas.world.time-time,.01-studio.accumulator),prefix+"恢复窗口首帧只处理原有固定步长，不增加消息循环耗时")
 time=studio.canvas.world.time
 studio.open_dialog.popup_centered_ratio(.4);await frames(studio)
 studio._process(.5)
 check.call(studio.playing and studio.canvas.world.time==time and not studio.message_dialog.visible,prefix+"文件窗口打开时不额外弹出负载窗口")
 studio.open_dialog.hide();studio._resume_preview_clock();studio._process(.5)
 check.call(studio.get_last_exclusive_window()==studio.get_window() and studio.preview_notice.is_empty(),prefix+"关闭文件窗口后无残留的排他子窗口")
 studio.playing=false
 var field=parameter(studio,"texture_override")
 field.mode.select(2);field.mode.item_selected.emit(2);await frames(studio)
 field._choose();await frames(studio)
 var dialog=field.picker_dialog
 check.call(is_instance_valid(dialog) and dialog.get_parent()==field and dialog.visible,prefix+"资源选择器归属于发起字段")
 field._choose()
 check.call(field.picker_dialog==dialog,prefix+"重复点击不叠加资源选择窗口")
 dialog.canceled.emit();await frames(studio)
 check.call(not is_instance_valid(dialog) and studio.get_last_exclusive_window()==studio.get_window(),prefix+"取消选择后窗口与输入占用一起回收")
 field._choose();await frames(studio);dialog=field.picker_dialog
 studio.select_resource("showcase_02_boomerang")
 check.call(not dialog.visible and studio.get_last_exclusive_window()==studio.get_window(),prefix+"切换招式在移除字段前关闭资源窗口")
 await frames(studio)
 check.call(not is_instance_valid(dialog),prefix+"切页后没有游离的文件窗口")
 var color=parameter(studio,"tint");var popup=color.get_popup();popup.popup_centered();await frames(studio)
 studio.select_resource("showcase_03_delayed_split")
 check.call(not popup.visible,prefix+"切页前关闭颜色选择器内部弹窗")
 await frames(studio)
 var program=studio.inspector.get_child(0).get_node("%Program");popup=program.get_popup();popup.popup();await frames(studio)
 studio.select_resource("showcase_04_stop_aim")
 check.call(not popup.visible,prefix+"切页前关闭类型下拉窗口")
 await frames(studio)
 var ids=studio.session.project.barrages.map(func(skill):return skill.id)
 for i in 20:
  studio.select_resource(ids[i%ids.size()]);await frames(studio,1)
 check.call(studio.get_last_exclusive_window()==studio.get_window() and not studio.message_dialog.visible,prefix+"连续切换二十次没有残留模态窗口")
 check.call(FileAccess.get_sha256("res://projects/attack_showcase/library.tres")==hash,prefix+"输入回归不改写展示库")
 studio.playing=false;studio.set_process(original_process)

@tool
extends EditorPlugin
var studio
func _enter_tree(): run.call_deferred()
func run():
 for i in 60: await get_tree().process_frame
 var found=EditorInterface.get_editor_main_screen().find_children("*","Control",true,false).filter(func(n):return n.get_script()==load("res://addons/stg_maker/ui/studio_workspace.gd") and n.workspace_active)
 if found.is_empty():get_tree().quit();return
 studio=found[0];studio.settings_path="user://window_probe.cfg";studio.session.recovery_folder="user://window_probe_drafts";studio.session.open("res://projects/attack_showcase/library.tres");studio.show_collection("barrages");studio.set_ui_scale(100,false)
 EditorInterface.set_main_screen_editor("STGMaker")
 print("WINDOW_PROBE_READY")
 studio.playing=true;studio._process(.3)
 for i in 180:
  await get_tree().create_timer(1).timeout
  var windows=[]
  for w in get_tree().root.find_children("*","Window",true,false):
   if w.visible:windows.append({"path":str(w.get_path()),"title":w.title,"exclusive":w.exclusive,"transient":w.transient,"popup":w.popup_window,"id":w.get_window_id(),"focused":w.has_focus(),"text":w.dialog_text if w is AcceptDialog else ""})
  print("WINDOW_STATE ",JSON.stringify({"windows":windows,"playing":studio.playing,"root_focus":get_tree().root.has_focus(),"time":studio.canvas.world.time}))
 studio.session.recoverable_changes=false
 preload("res://tests/editor_shutdown.gd").request(self)

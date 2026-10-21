extends SceneTree
const Builder=preload("res://addons/stg_maker/build/project_builder.gd")
const Commands=preload("res://addons/stg_maker/ui/commands.gd")
const Export=preload("res://tests/export_runtime.gd")
const PATH="res://projects/attack_showcase/library.tres"
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func run():
 var library=load(PATH);var hash=FileAccess.get_sha256(PATH)
 var stamp=str(Time.get_ticks_usec());var source="user://showcase_prefab_source_"+stamp;DirAccess.make_dir_recursive_absolute(source)
 var files={};Builder._gather("res://stg",files,[])
 for index in library.barrages.size():
  var name="attack_%02d.tscn"%index;var path=source+"/"+name
  var host={"session":{"project":library},"collection":"barrages","selected_id":library.barrages[index].id}
  check(Commands.export_prefab(host,path).is_empty(),"真实招式预制体导出："+library.barrages[index].title)
  files[name]={"source":path}
 # Minimal runtime module validation package, no game shell, levels, menus, or copied source project.
 files["project.godot"]={"text":'config_version=5
[application]
config/name="Showcase Prefab Validation"
[rendering]
renderer/rendering_method="gl_compatibility"
'}
 files["Prepare Game.ps1"]={"text":Builder._preparation_script()}
 var resolved=Builder._resolve_dependencies(files)
 check(resolved.issue.is_empty(),"正式依赖解析器收集预制体及贴图："+resolved.issue)
 if not resolved.issue.is_empty():quit(1);return
 var output=ProjectSettings.globalize_path("user://showcase_prefab_export_"+stamp)
 var checked=Builder._check_destination(output,"showcase_prefabs");var written=Builder._write(resolved.files,output,checked.get("owned",[]),"showcase_prefabs")
 check(written.issue.is_empty(),"独立运行模块写入成功："+written.issue)
 if not written.issue.is_empty():quit(1);return
 for material in library.bullets:
  check(FileAccess.file_exists(output.path_join(material.visual.texture.resource_path.trim_prefix("res://"))),"PNG 随预制体依赖导出："+material.title)
 check(not DirAccess.dir_exists_absolute(output.path_join("addons")) and not DirAccess.dir_exists_absolute(output.path_join("tests")) and not DirAccess.dir_exists_absolute(output.path_join("game")),"独立模块无编辑器、测试源码或完整游戏外壳")
 var verifier=FileAccess.open(output.path_join("verify.gd"),FileAccess.WRITE)
 verifier.store_string('''extends SceneTree
func _initialize():run.call_deferred()
func run():
 var valid=true
 for index in 10:
  var packed=load("res://attack_%02d.tscn"%index)
  if packed==null:valid=false;continue
  var prefab=packed.instantiate();prefab.autoplay=false;root.add_child(prefab);prefab.play();prefab.set_player(Vector2(-640,120))
  valid=valid and prefab.simulation.boss==Vector2.ZERO
  var calls=[];prefab.finished.connect(func():calls.append(true))
  for tick in 1100:
   if not prefab.running:break
   prefab._physics_process(STGSimulation.STEP)
  valid=valid and prefab.simulation.issue.is_empty() and not prefab.running and calls.size()==1
  if not valid:print("Failed exported prefab ",index," ",prefab.simulation.issue)
  prefab.queue_free()
  for frame in 2:await process_frame
 print("EXPORTED SHOWCASE RESULT: 10 checks, %d failures"%(0 if valid else 1));quit(0 if valid else 1)
''');verifier.close()
 var log:Array=[];var code=Export.import_project(output,log)
 check(code==0 and not Builder._has_errors(log),"无源项目缓存的模块独立导入："+"\n".join(log))
 log.clear();code=Export.run(output,log,"verify.gd",2000)
 check(code==0 and not Builder._has_errors(log) and "EXPORTED SHOWCASE RESULT: 10 checks, 0 failures" in "\n".join(log),"外部预制体入口独立运行十种招式："+"\n".join(log))
 check(FileAccess.get_sha256(PATH)==hash,"导出不改写源展示库")
 print("ATTACK SHOWCASE BUILD RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

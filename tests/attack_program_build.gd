extends SceneTree
## 只构建新SDK闭环测试夹具，不逐个导出现有示例工程。
const Factory=preload("res://addons/stg_maker/authoring/attack_presets.gd")
const D=preload("res://addons/stg_maker/authoring/defaults.gd")
const Builder=preload("res://addons/stg_maker/build/project_builder.gd")
const Commands=preload("res://addons/stg_maker/ui/commands.gd")
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func run():
 var game=preload("res://tests/game_fixture.gd").create()
 var actions:Array[STGFlowNode]=[]
 var skills=[]
 for skill in game.library.barrages:
  skills.append(skill)
  var action=D.flow_node("attack",{"barrage_id":skill.id,"wait_mode":"cleared"})
  actions.append(action)
 var driver=preload("res://stg/definitions/config_copy.gd").copy(game.library.bosses[0]);driver.id="driver";game.library.bosses.append(driver);game.library.waves[0].enemy_id=driver.id
 driver.phases[0].behavior_flow=D.flow(actions)
 check(game.validate().is_empty(),"新SDK独立游戏夹具有效："+"；".join(game.validate()))
 var resource_dir="res://assets/.validation_art_%d"%Time.get_ticks_usec()
 DirAccess.make_dir_recursive_absolute(resource_dir)
 var texture=GradientTexture2D.new();ResourceSaver.save(texture,resource_dir+"/texture.tres");texture=load(resource_dir+"/texture.tres")
 var clip=SpriteFrames.new();clip.add_frame("default",texture);ResourceSaver.save(clip,resource_dir+"/clip.tres");clip=load(resource_dir+"/clip.tres")
 var sound=AudioStreamWAV.new();sound.data=PackedByteArray([0,0,0,0]);ResourceSaver.save(sound,resource_dir+"/sound.tres");sound=load(resource_dir+"/sound.tres")
 actions[0].program_parameters.active_sound=sound
 actions[0].program_parameters.active_volume_db=-6.0
 var effect=PackedScene.new();var node=Node2D.new();effect.pack(node);node.free();ResourceSaver.save(effect,resource_dir+"/effect.tscn");effect=load(resource_dir+"/effect.tscn")
 var first=game.library.find("barrages","straight")
 first.program_parameters={"texture_override":{"mode":"custom","value":texture},"expire_clip_override":{"mode":"custom","value":clip},"spawn_sound":sound,"end_effect":effect}
 var path="user://attack_sdk_prefab_%d.tscn"%Time.get_ticks_usec()
 var host={"session":{"project":game.library},"collection":"barrages","selected_id":skills[0].id}
 check(Commands.export_prefab(host,path).is_empty(),"新招式可以导出预制体")
 var packed=load(path)
 var prefab=packed.instantiate();root.add_child(prefab)
 for i in 3:await process_frame
 check(prefab.simulation!=null and prefab.simulation.issue.is_empty(),"预制体使用同一正式运行器")
 check(prefab.simulation.boss==Vector2.ZERO,"预制体原点接入保持原契约")
 prefab.queue_free()
 for i in 3:await process_frame
 var output="user://attack_sdk_export_%d"%Time.get_ticks_usec()
 var built=Builder.build(game,output)
 check(built.issue.is_empty(),"SDK游戏项目构建成功："+built.issue)
 if built.issue.is_empty():
  check(not DirAccess.dir_exists_absolute(output.path_join("addons")),"成品不包含编辑器")
  for file in ["texture.tres","clip.tres","sound.tres","effect.tscn"]:
   check(FileAccess.file_exists(output.path_join(resource_dir.trim_prefix("res://")+"/"+file)),"类型资源依赖随独立项目导出："+file)
  var verifier=FileAccess.open(output.path_join("verify_attack_sdk.gd"),FileAccess.WRITE)
  verifier.store_string('''extends SceneTree
func _initialize():run.call_deferred()
func run():
 var game=load("res://game/content/game.tres")
 var valid=game!=null and game.validate().is_empty()
 var count=0
 if valid:
  for skill in game.library.barrages:
   if skill.attack_preset==null:continue
   var world=STGSimulation.new();root.add_child(world);world.reset(game.library,"barrages",skill.id)
   for i in 24:world.step()
   valid=valid and world.issue.is_empty() and (not world.actors.is_empty() or not world.summons.is_empty())
   count+=1
   world.clear_attacks();world.free()
 var driver=game.library.find("bosses","driver")
 valid=valid and driver.phases[0].behavior_flow.nodes[0].parameters().active_sound is AudioStream and is_equal_approx(driver.phases[0].behavior_flow.nodes[0].parameters().active_volume_db,-6)
 valid=valid and game.library.schema_version==16
 valid=valid and count==10
 print("EXPORTED ATTACK SDK RESULT: 10 checks, %d failures"%(0 if valid else 1))
 quit(0 if valid else 1)
''');verifier.close()
  var log:Array=[]
  var code=preload("res://tests/export_runtime.gd").import_project(ProjectSettings.globalize_path(output),log)
  check(code==0 and not Builder._has_errors(log),"导出工程脱离源缓存导入："+"\n".join(log))
  log.clear()
  code=preload("res://tests/export_runtime.gd").run(ProjectSettings.globalize_path(output),log,"verify_attack_sdk.gd",2000)
  check(code==0 and not Builder._has_errors(log) and "EXPORTED ATTACK SDK RESULT: 10 checks, 0 failures" in "\n".join(log),"成品运行全部十种程序："+"\n".join(log))
 for file in ["texture.tres","clip.tres","sound.tres","effect.tscn"]:DirAccess.remove_absolute(resource_dir+"/"+file)
 DirAccess.remove_absolute(resource_dir)
 print("ATTACK PROGRAM BUILD RESULT: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)

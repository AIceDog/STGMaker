extends SceneTree
const Fixture=preload("res://tests/unified14_fixture.gd")
const D=Fixture.D
var checks=0
var failures=0
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize():run.call_deferred()
func run():
 var session=load("res://addons/stg_maker/ui/session.gd").new();session.create()
 check(session.project.validate().is_empty() and session.project.bullets.is_empty() and session.project.barrages.is_empty() and session.project.bosses.is_empty() and session.project.attack_presets.is_empty(),"空库与格式14")
 var project=Fixture.project()
 check(project.barrages.size()==10,"目录发现十种算法")
 check(project.validate().is_empty(),"夹具合法："+"；".join(project.validate()))
 for skill in project.barrages:
  print("Checking ",skill.id)
  var world=STGSimulation.new();root.add_child(world);world.presentation_enabled=false;world.reset(project,"barrages",skill.id)
  check(world.issue.is_empty(),"程序可启动："+skill.id+world.issue)
  world.step()
  check(not world.actors.is_empty() or not world.summons.is_empty(),"程序生成实体："+skill.id+world.issue)
  for i in 1700:
   if world.completed or not world.issue.is_empty():break
   world.step()
  check(world.issue.is_empty() and world.completed,"程序有限完成："+skill.id+world.issue)
  world.clear_attacks();world.free()
 print("UNIFIED14 CORE RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

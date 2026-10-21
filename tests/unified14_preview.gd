extends SceneTree
const Fixture=preload("res://tests/unified14_fixture.gd")
const Preview=preload("res://addons/stg_maker/ui/trajectory_preview.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize():run.call_deferred()
func run():
 var project=Fixture.project()
 project.barrages[-1].program_parameters.entry_duration=0.6
 for skill in project.barrages:
  var preview=Preview.new();preview.start(project,skill.id,Vector2(400,600))
  if preview._world!=null:check(not preview._world.presentation_enabled,"预测关闭附加表现："+skill.id)
  while preview.running:preview.advance(8,0)
  check(preview.issue.is_empty() and not preview.paths.is_empty(),"所有形态有预测数据："+skill.id+preview.issue)
  check(preview._point_count<=32768 and preview.paths.size()<=48,"预测配额："+skill.id)
  var points=preview.paths.duplicate(true)
  preview.start(project,skill.id,Vector2(400,600))
  while preview.running:preview.advance(8,0)
  check(preview.paths==points,"重播确定性："+skill.id)
  preview.cancel()
 print("UNIFIED14 PREVIEW RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

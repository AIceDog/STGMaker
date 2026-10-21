extends SceneTree
const Fixture=preload("res://tests/unified14_fixture.gd")
const D=Fixture.D
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func advance(world,seconds):
 for i in ceili(seconds/STGSimulation.STEP):world.step()
func run():
 var project=Fixture.project();var enemy=project.bosses[0]
 var wait=D.flow_node("wait",{"execution_duration":.15})
 var fire=D.flow_node("attack",{"barrage_id":"fan","wait_mode":"emission"})
 enemy.phases[0].behavior_flow=D.flow([wait,fire]);enemy.phases[0].loop=false
 project.find("barrages","fan").program_parameters={"rounds":1,"count":5,"duration":.4}
 check(project.validate().is_empty(),"原敌人行为节点可引用统一程序招式")
 var world=STGSimulation.new();root.add_child(world);world.reset(project,"bosses",enemy.id)
 advance(world,.1);check(world.actors.is_empty(),"攻击前等待仍由敌人行为节点控制")
 advance(world,.15);check(world.actors.size()==5,"原行为攻击节点调用扇形程序")
 advance(world,1);check(world.completed,"原流程结束及程序实体完成后正常收尾");world.free()
 var summon=project.find("barrages","summon");summon.program_parameters={"count":1,"entry_duration":.1,"entry_velocity":Vector2(100,0),"duration":2.0}
 world=STGSimulation.new();root.add_child(world);world.reset(project,"barrages","summon");world.set_presentation_clock(false,2);advance(world,.08)
 check(world.summons.size()==1 and world.summons[0].world.actors.is_empty(),"召唤入场时不提前执行行为攻击")
 check(not world.summons[0].world.presentation_clock_playing and world.summons[0].world.presentation_rate==2,"暂停单步创建的召唤继承声音暂停/倍速")
 advance(world,.25);check(world.summons.size()==1 and world.summons[0].world.actors.size()==5,"召唤入场后沿用原行为流程和程序招式")
 world.clear_attacks();check(world.battle_budget.summons==0,"清屏回收嵌套攻击和召唤");world.free()
 var game=preload("res://tests/game_fixture.gd").create();var level=STGLevelSimulation.new();root.add_child(level);level.reset(game.library,"levels",game.library.levels[0].id);level.step()
 var entity=level.entities[0]
 check(entity.simulation.battle_budget==level.battle_budget,"关卡敌人使用整场共享召唤配额")
 entity.simulation.spawn_summon("enemy",Vector2.ZERO,1,5)
 check(level.battle_budget.summons==1,"关卡召唤计入总预算")
 level.set_presentation_clock(false,2)
 check(not entity.simulation.presentation_clock_playing and entity.simulation.presentation_rate==2,"关卡暂停/倍速传给攻击与召唤")
 level.clear();check(level.battle_budget.summons==0,"关卡退出释放共享召唤预算");level.free()
 print("UNIFIED14 BEHAVIOR RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

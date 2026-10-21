extends SceneTree
const PATH="res://projects/attack_showcase/library.tres"
const Preview=preload("res://addons/stg_maker/ui/trajectory_preview.gd")
var checks=0
var failures=0
var library:STGProject
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func world(skill:STGBarrageSkill):
 var simulation=STGSimulation.new();root.add_child(simulation);simulation.presentation_enabled=false;simulation.reset(library,"barrages",skill.id);simulation.player=Vector2(-400,-230);return simulation
func run():
 library=load(PATH)
 check(library!=null and library.schema_version==STGProject.VERSION,"展示库当前格式可重新打开")
 if library==null:quit(1);return
 check(library.barrages.size()==10 and library.bullets.size()==10 and library.attack_presets.size()==10 and library.behaviors.size()==2 and library.bosses.size()==1,"十组素材招式预设与最小行为演示")
 check(library.levels.is_empty() and library.waves.is_empty(),"展示库不生成完整游戏或关卡")
 check(library.validate().is_empty(),"展示库引用与程序参数合法："+"；".join(library.validate()))
 var hash=FileAccess.get_sha256(PATH)
 var session=load("res://addons/stg_maker/ui/session.gd").new();session.create()
 check(session.project.barrages.is_empty() and session.project.bullets.is_empty(),"默认新建项目仍为空白")
 for index in library.bullets.size():
  var material=library.bullets[index];var image=material.visual.texture.get_image();var size=32 if index<6 else (64 if index==9 else 16)
  check(image.get_size()==Vector2i(size,size) and image.detect_alpha()!=Image.ALPHA_NONE,"PNG尺寸及透明度："+material.title)
  check(material.visual.color==Color.WHITE and material.collision.validate().is_empty(),"贴图颜色及独立碰撞："+material.title)
  if index in [6,7,8]:
   var ratio=material.collision.size.y/material.visual.geometry.size.y
   var covered=true
   for y in range(ceili((.5-ratio/2)*16),floori((.5+ratio/2)*16)):
    for x in [0,8,15]:covered=covered and image.get_pixel(x,y).a>=.5
   check(covered,"条带碰撞处于不透明核心内："+material.title)
 for skill in library.barrages:
  var simulation=world(skill);check(simulation.issue.is_empty(),"可启动："+skill.title+simulation.issue)
  var ids={};var maximum=0;var states={};var saw_warning=false;var saw_live=false;var saw_drain=false
  var positions=[];var first_fork=[]
  for tick in 960:
   simulation.step();maximum=maxi(maximum,simulation.actors.size())
   for actor in simulation.actors:
    ids[actor.get_instance_id()]=true
    check_finite(actor)
    if tick%12==0 and actor.capability=="Body2D":positions.append(actor.program_position())
    if actor.capability=="Beam2D" or actor.capability=="Area2D":
     saw_warning=saw_warning or not actor.damaging;saw_live=saw_live or actor.damaging
    if actor.capability=="Polyline2D" and first_fork.is_empty():first_fork=Array(actor.points)
    if actor.capability=="Trail2D" and actor.age>3.2 and not actor.segments.is_empty():saw_drain=true
   if tick in [71,107,131]:states[tick]=simulation.actors.map(func(a):return a.program_position())
   if simulation.completed or not simulation.issue.is_empty():break
  check(simulation.completed and simulation.issue.is_empty(),"有限完成与正式回收："+skill.title+simulation.issue)
  if skill.title=="五连点射":check(ids.size()==5,"点射严格生成五颗")
  elif skill.title=="折返飞镖":
   var leftmost=10000.0
   for at in positions:leftmost=minf(leftmost,at.x)
   check(leftmost<-300 and not positions.is_empty() and positions[-1].x>200,"飞镖先外飞再返回初始原点")
  elif skill.title=="延时散花":check(ids.size()==11 and maximum==10,"核心停留后分裂十颗，核心被回收")
  elif skill.title=="刹停狙击":check(states.get(71)==states.get(107) and states.get(107)!=states.get(131),"停车时保持位置，锁定后再次发射")
  elif skill.title=="蛇行弹":
   var ys=[]
   for at in positions:ys.append(at.y)
   check(ys.max()-ys.min()>60,"蛇行具有实际横向摆动")
  elif skill.title=="边界反弹":
   check(positions.all(func(at):return Rect2(-Vector2(480,270),Vector2(960,540)).has_point(at)) and positions.size()>90,"反弹路径保持在战斗边界内")
  elif skill.title=="伸缩激光":check(saw_warning and saw_live,"激光预警关闭判伤，伸长阶段开启")
  elif skill.title=="分叉雷电":check(maximum==4 and first_fork.size()==9,"雷电主干及三个独立分叉共用折线运行接口")
  elif skill.title=="追踪尾迹":check(saw_drain,"停止记录后旧段仍自然消散")
  elif skill.title=="预警地雷":check(saw_warning and saw_live and simulation.hits==1,"地雷预警后在锁定落点生效一次")
  simulation.clear_attacks();check(simulation.actors.is_empty() and simulation.battle_budget.actors==0,"强制清屏释放预算："+skill.title);simulation.free()
  var preview=Preview.new();preview.start(library,skill.id,Vector2(-320,0))
  while preview.running:preview.advance(8,0)
  check(preview.issue.is_empty() and not preview.paths.is_empty() and preview.paths.size()<=48 and preview._point_count<=32768,"统一虚线预测："+skill.title+preview.issue)
  var expected=preview.paths.duplicate(true);preview.start(library,skill.id,Vector2(-320,0))
  while preview.running:preview.advance(8,0)
  check(preview.paths==expected,"固定种子预测确定性："+skill.title);preview.cancel()
  var changed=library.snapshot();var copy=changed.find("barrages",skill.id)
  var field={"五连点射":"count","折返飞镖":"speed","延时散花":"count","刹停狙击":"count","蛇行弹":"amplitude","边界反弹":"bounces","伸缩激光":"length","分叉雷电":"branches","追踪尾迹":"speed","预警地雷":"warning"}[skill.title]
  var original=copy.attack_preset.parameters().get(field)
  var value=float(original)*.5 if field not in ["count","branches","bounces"] else maxi(1,int(original)-1)
  copy.program_parameters[field]=value
  check(changed.validate().is_empty(),"关键参数可独立覆盖："+skill.title)
  var altered=Preview.new();altered.start(changed,skill.id,Vector2(-320,0))
  while altered.running:altered.advance(8,0)
  # Mine timing changes sampled geometry time even though the locked outline is unchanged.
  check(altered.issue.is_empty() and altered.paths!=expected,"关键参数实际改变预测："+skill.title+altered.issue);altered.cancel()
 var enemy=STGSimulation.new();root.add_child(enemy);enemy.presentation_enabled=false;enemy.reset(library,"bosses",library.bosses[0].id);enemy.player=Vector2(-400,-230)
 var seen={}
 for tick in 9000:
  enemy.step()
  for actor in enemy.actors:seen[actor.get_meta("source_skill","")]=true
  if seen.size()==10 or not enemy.issue.is_empty():break
 check(enemy.issue.is_empty() and seen.size()==10,"演示发射台通过两个原行为子流程依次调用十种攻击："+enemy.issue)
 enemy.clear_attacks();enemy.free()
 var folder="user://showcase_roundtrip_%d"%Time.get_ticks_usec();var path=folder+"/library.tres"
 check(session.open(PATH).is_empty(),"会话正常打开展示库")
 var id=session.project.barrages[0].id
 session.edit_asset("barrages",id,func(p):p.find("barrages",id).program_parameters.count=7,{"structure":false})
 session.undo();check(session.project.find("barrages",id).attack_preset.parameters().count==5,"撤销恢复预设快照")
 session.redo();check(session.project.find("barrages",id).program_parameters.count==7,"重做恢复具体招式覆盖")
 check(session.save(path).is_empty() and session.open(path).is_empty() and session.project.find("barrages",id).program_parameters.count==7,"覆盖值及像素资源引用保存重开")
 check(FileAccess.get_sha256(PATH)==hash,"模拟、预测和保存副本不改写展示源库")
 session.recoverable_changes=false
 print("ATTACK SHOWCASE RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check_finite(actor):
 var geometry=actor.geometry_snapshot()
 for point in geometry.points:
  if not point.is_finite():check(false,"程序生成非有限几何")

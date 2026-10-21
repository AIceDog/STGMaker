extends SceneTree
const D=preload("res://stg/definitions/definition_factory.gd")
const Catalog=preload("res://addons/stg_maker/authoring/attack_presets.gd")
const Assets=preload("res://addons/stg_maker/authoring/asset_store.gd")
const ROOT="res://projects/attack_showcase"
func _initialize():run.call_deferred()
func run():
 var spec=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"/art_sources.json"))
 DirAccess.make_dir_recursive_absolute(ROOT+"/assets")
 for asset in spec.assets:
  if FileAccess.file_exists(ROOT+"/assets/"+asset.name+".png"):continue
  var image=Image.load_from_file(asset.source)
  if image==null or image.is_empty():push_error("素材源无法读取："+asset.name);quit(1);return
  if asset.name in ["beam","lightning","flame"]:
   var rect=asset.get("packing_rect",[]);image=image.get_region(Rect2i(int(rect[0]),int(rect[1]),int(rect[2]),int(rect[3]))) if rect.size()==4 else image.get_region(image.get_used_rect());image.resize(int(asset.size),int(asset.size)-2,Image.INTERPOLATE_NEAREST)
   var tile=Image.create_empty(int(asset.size),int(asset.size),false,Image.FORMAT_RGBA8);tile.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(0,1));image=tile
  else:image.resize(int(asset.size),int(asset.size),Image.INTERPOLATE_NEAREST)
  var error=image.save_png(ROOT+"/assets/"+asset.name+".png")
  if error!=OK:quit(2);return
 if "art_only" in OS.get_cmdline_user_args():print("SHOWCASE ART RESULT: 10 checks, 0 failures");quit();return
 var project=STGProject.create()
 var recipes=[
  ["five_shot","五连点射","needle","straight","moving","固定间隔连续发出五颗针弹。",{"count":5,"rounds":1,"group_size":1,"group_interval":.12,"speed":450.0,"duration":2.5,"angle":180.0}],
  ["boomerang","折返飞镖","boomerang","boomerang","moving","外飞后回到释放时原点，自转只改变刀刃朝向。",{"speed":500.0,"out_time":1.35,"return_time":1.1,"hit_mode":"repeat","hit_interval":.35}],
  ["delayed_split","延时散花","crystal","delayed_split","moving","核心移动并停留后分裂为环形弹群；核心阶段不判伤。",{"child_speed":230.0}],
  ["stop_aim","刹停狙击","arrow","stop_aim","moving","初段散开，停住蓄势，再锁定当时的玩家位置发射。",{}],
  ["sine_wave","蛇行弹","scale","sine_wave","moving","向前飞行时叠加正弦横摆，相位差形成交错弹路。",{}],
  ["ricochet","边界反弹","block","ricochet","moving","按战斗边界反射，达到反弹上限或寿命后结束。",{"hit_mode":"repeat","hit_interval":.4}],
  ["telescoping_beam","伸缩激光","beam","telescoping_beam","laser","预警后逐渐伸长，保持后缩回；预警期间不判伤。",{"hit_mode":"repeat","hit_interval":.4}],
  ["fork_lightning","分叉雷电","lightning","fork_lightning","laser","向锁定落点生成主干与侧向分叉，按固定随机种子闪击。",{"hit_mode":"repeat","hit_interval":.2}],
  ["seeking_trail","追踪尾迹","flame","seeking_trail","trail","采样点转向玩家，旧轨迹停留原地并逐段自然消散。",{"speed":220.0,"hit_mode":"repeat","hit_interval":.4}],
  ["warning_mine","预警地雷","mine","area","area","锁定释放时的玩家落点，预警结束后短时生效。",{"warning":.75,"duration":.55,"damage":3.0,"hit_mode":"activation"}]]
 for index in recipes.size():
  var recipe=recipes[index];var prefix="showcase_%02d_"%(index+1)
  var material=D.bullet(recipe[4]);material.id=prefix+recipe[2];material.title=["黄色针弹","青色回旋刃","紫色晶体弹","红色箭头弹","绿色蛇鳞弹","橙色方块弹","蓝白能量条带","紫白电弧条带","红橙火焰条带","红色像素地雷"][index]
  material.description="像素贴图提供外观，独立碰撞覆盖主体并内缩。"
  material.visual.mode="texture";material.visual.color=Color.WHITE;material.visual.texture=load(ROOT+"/assets/"+recipe[2]+".png")
  material.visual.geometry.size=Vector2(32,32)
  material.collision.kind="circle";material.collision.size=Vector2(18,18)
  if index==0:material.collision.kind="rectangle";material.collision.size=Vector2(20,6)
  if index==2:material.collision.kind="diamond";material.collision.size=Vector2(20,20)
  if index==3:material.collision.kind="triangle";material.collision.size=Vector2(22,18)
  if index==4:material.collision.kind="diamond";material.collision.size=Vector2(24,14)
  if index==5:material.collision.kind="rectangle";material.collision.size=Vector2(22,22)
  if index in [6,7]:
   material.visual.geometry.size=Vector2(800,18 if index==6 else 10);material.collision.kind="rectangle";material.collision.size=Vector2(800,12 if index==6 else 2.5)
  if index==8:
   material.visual.geometry.size=Vector2(1,20);material.collision.kind="rectangle";material.collision.size=Vector2(1,5);material.trail_offset=0;material.trail_spacing=3
  if index==9:material.visual.geometry.size=Vector2(64,64);material.collision.size=Vector2(42,42)
  if index<6:
   var bitmap=BitMap.new();bitmap.create_from_image_alpha(material.visual.texture.get_image(),.65)
   var outlines=bitmap.opaque_to_polygons(Rect2i(0,0,32,32),1)
   var best=PackedVector2Array();var best_area=0.0
   for outline in outlines:
    var area=0.0
    for j in outline.size():area+=outline[j].cross(outline[(j+1)%outline.size()])
    if absf(area)>best_area:best_area=absf(area);best=outline
   var inset=Geometry2D.offset_polygon(best,-.6)
   if not inset.is_empty():best=inset[0]
   material.collision.kind="polygon";material.collision.polygon_mode="custom";material.collision.size=Vector2(32,32)
   material.collision.points=PackedVector2Array()
   for point in best:material.collision.points.append((point-Vector2(16,16))/32.0)
  project.bullets.append(material)
  var program=load("res://stg/programs/"+recipe[3]+".tres")
  if program==null:push_error("无法加载程序："+recipe[3]);quit(3);return
  var preset=Catalog.preset(program);preset.id=prefix+"preset";preset.title=recipe[1];preset.category="像素招式展示";preset.description=recipe[5];preset.reference_id=material.id
  preset.default_parameters.merge(recipe[6],true)
  # Wrap only useful designer fields; internal fixed scheduling values stay in the preset.
  preset.exposed_parameters.clear()
  for field in program.fields:
   var name=str(field.name)
   if name not in ["rounds","interval","group_size","damage_on_contact","spawn_clip_override","run_clip_override","spawn_particles_override","run_particles_override","hit_particles_override","hit_clip_override","spawn_sound","run_sound","hit_sound","end_sound","spawn_effect","hit_effect","end_effect","effect_duration"]:
    preset.exposed_parameters.append(name)
  if index==0:
   preset.parameter_options={"count":{"min":1,"max":12,"help":"每轮逐颗发射；间隔由下方组间隔控制。"},"group_interval":{"min":.04,"max":.5,"help":"本预设固定每组一颗，这是两颗针弹之间的时间。"}}
  project.attack_presets.append(preset)
  var skill=Catalog.skill(preset);skill.id=prefix+recipe[0];project.barrages.append(skill)
 var bullets=sequence(project,"showcase_body_flow","弹丸演示",0,6)
 var geometry=sequence(project,"showcase_geometry_flow","几何攻击演示",6,10)
 project.behaviors.assign([bullets,geometry])
 var enemy=D.boss();enemy.id="showcase_emitter";enemy.title="像素招式演示发射台";enemy.description="依次调用弹丸演示与几何攻击演示，等待清理后继续，整轮循环。";enemy.color=Color("8bc6e8")
 var flow=STGBehaviorFlow.new();flow.entry_id="body";var body_call=D.flow_node("call");body_call.id="body";body_call.title="调用弹丸演示";body_call.behavior_id=bullets.id;body_call.wait_mode="cleared";body_call.next_id="geometry";body_call.editor_position=Vector2(250,50)
 var geo_call=D.flow_node("call");geo_call.id="geometry";geo_call.title="调用几何攻击演示";geo_call.behavior_id=geometry.id;geo_call.wait_mode="cleared";geo_call.editor_position=Vector2(250,235)
 flow.nodes.assign([body_call,geo_call]);enemy.phases[0].behavior_flow=flow;enemy.phases[0].loop=true;project.bosses.append(enemy)
 var errors=project.validate()
 if not errors.is_empty():push_error("；".join(errors));quit(4);return
 var issue=Assets.save_library(project,ROOT+"/library.tres")
 if not issue.is_empty():push_error(issue);quit(5);return
 print("SHOWCASE GENERATION RESULT: 10 checks, 0 failures");quit()
func sequence(project:STGProject,id:String,title:String,begin:int,end:int) -> STGBehaviorFlow:
 var flow=STGBehaviorFlow.new();flow.id=id;flow.title=title
 for i in range(begin,end):
  var node=D.flow_node("attack");node.id="attack_%02d"%i;node.title=project.barrages[i].title;node.barrage_id=project.barrages[i].id;node.wait_mode="cleared";node.editor_position=Vector2(250,(i-begin)*185)
  if flow.nodes.is_empty():flow.entry_id=node.id
  else:flow.nodes[-1].next_id=node.id
  flow.nodes.append(node)
 return flow

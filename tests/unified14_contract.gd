extends SceneTree
const Fixture=preload("res://tests/unified14_fixture.gd")
const Copy=preload("res://stg/definitions/config_copy.gd")
const References=preload("res://stg/definitions/resource_references.gd")
const Compiler=preload("res://addons/stg_maker/build/compiler.gd")
var checks=0
var failures=0
class Probe:
 extends STGAttackProgram
 var p:Dictionary
 var reason:String
 func start(ctx:STGAttackContext,parameters:Dictionary):p=parameters
 func tick(ctx:STGAttackContext,dt:float):p["text"]="instance only"
 func cancel(value:String):reason=value
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func world(skill="homing"):
 var w=STGSimulation.new();root.add_child(w);w.reset(Fixture.project(),"barrages",skill);return w
func scene(particle=false,finite=true,gpu=false) -> PackedScene:
 var node=Node2D.new()
 if particle:
  for life in [.05,.4]:
   var p=GPUParticles2D.new() if gpu else CPUParticles2D.new()
   if gpu:p.process_material=ParticleProcessMaterial.new()
   p.one_shot=finite;p.lifetime=life;p.amount=4;node.add_child(p);p.owner=node
 var packed=PackedScene.new();packed.pack(node);node.free();return packed
func run():
 var definition=STGAttackProgramDefinition.new();definition.id="contract";definition.implementation=Probe
 definition.fields.assign([
  {"name":"text","type":"string","default":"asset"},
  {"name":"direction","type":"vector2","default":Vector2(0,20)},
  {"name":"tint","type":"color","default":Color.WHITE},
  {"name":"choice","type":"enum","values":["a","b"],"default":"a"},
  {"name":"reference","type":"resource_id","collection":"bullets","default":"material_moving"}])
 check(definition.validate({}).is_empty(),"完整类型声明可校验")
 check(not definition.validate({"direction":Vector2.INF}).is_empty() and not definition.validate({"choice":"invalid"}).is_empty(),"拒绝非有限向量与无效枚举")
 var p=Fixture.project();var preset=STGAttackPreset.new();preset.id="wrapper";preset.program=definition;preset.reference_id="material_moving";preset.exposed_parameters=PackedStringArray(["text"])
 preset.default_parameters=definition.default_parameters()
 check(preset.validate(p).is_empty() and not preset.validate(p,{"choice":"b"}).is_empty(),"人工开放字段约束")
 var skill=STGBarrageSkill.new();skill.id="probe";skill.attack_preset=preset;p.barrages.append(skill)
 var copied=Copy.copy(skill);copied.attack_preset.default_parameters.text="snapshot"
 check(preset.default_parameters.text=="asset","预设快照与具体招式隔离")
 var refs=References.collect(skill)
 check(refs.any(func(ref):return ref.key=="reference" and ref.id=="material_moving"),"库内资源参数接入删除保护引用图")
 var compiled=Compiler.compile_library(p,[{"collection":"barrages","id":"probe"}])
 check(compiled.issue.is_empty() and compiled.library.bullets.size()==1,"声明引用进入构建闭包")
 var w=STGSimulation.new();root.add_child(w);w.reset(p,"barrages","probe");w.step()
 var a=w.barrages[0];var context=a.context;var implementation=a.session.implementation
 var b=w.play_barrage("probe",Vector2.ZERO);w.step()
 check(implementation!=b.session.implementation and preset.default_parameters.text=="asset","每次释放独立实例且不改写参数资产")
 a.cancel();a.cancel();check(not context.active() and implementation.reason=="stopped","清理只调用一次且关闭上下文")
 check(context.spawn_body(Vector2.ZERO,Vector2.ZERO,1)==null,"关闭后的上下文不能再生成攻击")
 w.free()
 w=world("straight");w.clear_attacks();w.project.find("barrages","straight").program_parameters={"count":5,"rounds":2,"interval":.2,"group_size":2,"group_interval":.05,"duration":2.0,"speed":0.0};w.play_barrage("straight",Vector2.ZERO);w.step()
 check(w.actors.size()==2,"分组发射首批数量由声明参数决定")
 w.step(.05);check(w.actors.size()==4,"组间隔后生成下一批")
 w.step(.05);check(w.actors.size()==5,"末批保留余数")
 w.step(.1);check(w.actors.size()==7,"第二轮按轮间隔开始")
 w.clear_attacks();check(w.battle_budget.actors==0,"整场实体预算在清屏时释放");w.free()
 var texture=GradientTexture2D.new();var frames=SpriteFrames.new();frames.add_frame("default",texture)
 var material=p.bullets[0];material.visual.mode="texture";material.visual.texture=texture;material.visual.run_clip=frames
 var options=STGAttackEntityOptions.from_parameters({"texture_override":{"mode":"disabled","value":null},"run_clip_override":{"mode":"custom","value":frames},"damage":7.0})
 var duplicate=Copy.copy(material);options.apply(duplicate)
 check(material.visual.texture==texture and material.visual.run_clip==frames and duplicate.visual.run_clip==frames and duplicate.visual.texture==null,"资源沿用/禁用/自定义只影响单次外观副本")
 check(options.lifecycle.damage==7 and Copy.copy(skill).attack_preset.program==definition,"运行选项与只读程序声明分离")
 var field={"name":"texture_override","type":"resource_override","resource_class":"Texture2D","default":{"mode":"inherit","value":null}}
 check(not STGParameterSchema.validate(field,{"mode":"custom","value":AudioStreamWAV.new()}).is_empty() and not STGParameterSchema.validate(field,{"mode":"custom","value":null}).is_empty(),"资源类型约束与自定义空值校验")
 field={"name":"spawn_particles_override","type":"resource_override","resource_class":"PackedScene","default":{"mode":"inherit","value":null}}
 check(not STGParameterSchema.validate(field,{"mode":"custom","value":scene(true,false)}).is_empty() and STGParameterSchema.validate(field,{"mode":"custom","value":scene(true,true)}).is_empty(),"一次性粒子校验包含参数覆盖")
 w=world("straight");w.clear_attacks();w.project.find("barrages","straight").program_parameters={"speed":0.0,"damage":7.0};var damage=[];w.player_hit.connect(func(v):damage.append(v));w.play_barrage("straight",w.player);w.step()
 check(damage==[7.0],"伤害参数实际进入碰撞执行")
 w.clear_attacks();damage.clear();w.project.find("barrages","straight").program_parameters.damage_on_contact=false;w.play_barrage("straight",w.player);w.step();check(damage.is_empty(),"关闭接触伤害实际生效");w.free()
 w=world("rotating_beam");w.step();a=w.barrages[0];b=w.play_barrage("rotating_beam",Vector2.ZERO);w.step()
 var handle=a.context.create_beam(Vector2.ZERO,Vector2(100,0),12,.2)
 check(a.context.valid(handle) and not b.context.valid(handle) and not b.context.destroy(handle),"句柄禁止跨释放实例修改")
 var sound=AudioStreamWAV.new();sound.mix_rate=8000;sound.data=PackedByteArray();sound.data.resize(8000)
 w.muted=false;w.set_presentation_clock(false,1.5)
 var voice=a.context.play_sound(sound,Vector2.ZERO,true,handle);var node=a.presentations.get(voice._ticket)
 check(a.context.valid(voice) and node.audio!=null and node.audio.stream_paused and is_equal_approx(node.audio.pitch_scale,1.5),"持续表现句柄有效且继承暂停/倍速")
 a.context.destroy(handle);w.step();check(not a.context.valid(voice),"实体结束时停止跟随循环音效")
 var effect=a.context.play_effect(scene(),Vector2.ZERO,2)
 check(a.context.valid(effect) and not b.context.stop_presentation(effect),"特效句柄受归属约束")
 w.stop_owner(a.owner_id);check(w.effects.all(func(e):return e.get("owner",-1)!=a.owner_id),"归属清屏立即移除声音与特效")
 w.clear_attacks();check(w.actors.is_empty() and w.effects.is_empty(),"强制清屏不执行正常收尾");w.free()
 w=world("straight");w.clear_attacks();w.project.find("barrages","straight").program_parameters={"duration":.05,"speed":0.0,"end_effect":scene(),"effect_duration":.4,"expire_clip_override":{"mode":"custom","value":frames}}
 w.play_barrage("straight",Vector2.ZERO)
 for i in 7:w.step()
 check(w.actors.is_empty() and w.effects.size()==2,"停止判伤后独立播放结束动画与特效")
 for i in 150:w.step()
 check(w.completed and w.effects.is_empty(),"正常收尾按模拟时间完成回收");w.free()
 w=world("summon");w.clear_attacks();var summoned=w.spawn_summon("enemy",Vector2.ZERO,1,10,{"launch":.2,"velocity":Vector2(100,0)})
 w.step(.1);check(summoned.pending and summoned.world.boss_player==null and summoned.world.boss.is_equal_approx(Vector2(10,0)),"召唤入场阶段尚未运行敌人AI")
 w.step(.1);check(not summoned.pending and summoned.world.boss_player!=null and summoned.world.boss.is_equal_approx(Vector2(20,0)),"入场结束交还原敌人行为节点")
 w.destroy_summon(summoned);check(w.battle_budget.summons==0,"召唤回收释放整场配额")
 for i in 64:w.spawn_summon("enemy",Vector2.ZERO,1,10)
 check(w.summons.size()==64 and w.spawn_summon("enemy",Vector2.ZERO,1,10).is_empty(),"整场最多64个召唤")
 w.issue="";var child=w.summons[0].world
 check(child.spawn_summon("enemy",Vector2.ZERO,1,10).is_empty(),"嵌套召唤共享64个配额")
 w.clear_attacks();w.issue="";w.summon_depth=8
 check(w.spawn_summon("enemy",Vector2.ZERO,1,10).is_empty() and w.battle_budget.summons==0,"嵌套最多8层且清屏释放所有配额");w.free()
 var particles=load("res://stg/runtime/attacks/projectile_presentation.gd").new();root.add_child(particles);particles.configure(scene(true,true));particles.tick(.15)
 check(not particles.is_finished(),"多粒子不同寿命不会被首个发射器提前回收")
 particles.tick(1);check(particles.is_finished(),"所有粒子结束后可回收");particles.free()
 var gpu=load("res://stg/runtime/attacks/projectile_presentation.gd").new();root.add_child(gpu);gpu.configure(scene(true,true,true));gpu.tick(.15)
 check(not gpu.is_finished(),"GPU 多发射器不会提前回收")
 for i in 3:await process_frame
 gpu.tick(1);check(gpu.is_finished(),"GPU 粒子使用同一模拟时钟自然完成");gpu.free()
 for i in 3:await process_frame
 print("UNIFIED14 CONTRACT RESULT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

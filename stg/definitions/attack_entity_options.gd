@tool
class_name STGAttackEntityOptions
extends Resource
## 由程序参数构造的单次执行选项，不能作为招式资产的第二份配置保存。
var lifecycle=STGAttackLifecycle.new()
var overrides:Dictionary={}
var run_sound:AudioStream
static func from_parameters(p:Dictionary) -> STGAttackEntityOptions:
 var o=STGAttackEntityOptions.new()
 for key in ["damage","damage_on_contact","hit_interval","hit_mode","damage_falloff_start","damage_falloff_scale","exit_mode","ground_y","bounds_margin","spawn_sound","hit_sound","spawn_effect","hit_effect"]:
  if p.has(key):o.lifecycle.set(key,p[key])
 o.lifecycle.expire_sound=p.get("end_sound");o.lifecycle.expire_effect=p.get("end_effect");o.lifecycle.effect_duration=p.get("effect_duration",2.0)
 o.run_sound=p.get("run_sound")
 for key in ["texture","spawn_clip","run_clip","hit_clip","expire_clip","spawn_particles","run_particles","hit_particles"]:
  if p.has(key+"_override"):o.overrides[key]=p[key+"_override"]
 if p.has("tint"):o.overrides["tint"]=p.tint
 return o
func apply(material:STGBulletDefinition) -> void:
 for key in overrides:
  if key=="tint":material.visual.color*=overrides[key];continue
  var entry=overrides[key]
  if entry.get("mode","inherit")=="inherit":continue
  var value=entry.get("value") if entry.mode=="custom" else null
  if key.ends_with("particles"):material.set(key,value)
  else:
   material.visual.set(key,value)
   if value!=null:material.visual.mode="texture"
   if key=="texture" and value!=null:material.visual.run_clip=null
   if key=="run_clip" and value!=null:material.visual.texture=null

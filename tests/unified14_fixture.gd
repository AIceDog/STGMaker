extends RefCounted
const D=preload("res://stg/definitions/definition_factory.gd")
const Catalog=preload("res://addons/stg_maker/authoring/attack_presets.gd")
static func project() -> STGProject:
 var p=STGProject.create()
 for form in ["moving","laser","trail","area"]:
  var material=D.bullet(form);material.id="material_"+form;p.bullets.append(material)
 var enemy=D.boss();enemy.id="enemy";p.bosses.append(enemy)
 for program in Catalog.definitions():
  if program.id.get_slice(".",1) not in ["straight","fan","ring","spiral","area","summon","homing","rotating_beam","lightning","dynamic_trail"]:continue
  var preset=Catalog.preset(program)
  preset.reference_id="enemy" if program.capability=="SummonEnemy" else "material_"+{"Body2D":"moving","Beam2D":"laser","Polyline2D":"laser","Trail2D":"trail","Area2D":"area"}[program.capability]
  var skill=Catalog.skill(preset);skill.id=program.id.get_slice(".",1);p.barrages.append(skill)
 return p

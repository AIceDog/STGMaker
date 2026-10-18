extends SceneTree
## 新弹道、单次判伤、事件分裂与归属回收的运行回归。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
var failures: PackedStringArray = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(result: bool, label: String) -> void:
	checks += 1
	if not result:
		failures.append(label)

func _project() -> STGProject:
	var result = STGProject.create()
	result.schema_version = STGProject.VERSION
	return result

func _world(project: STGProject, id: String) -> STGSimulation:
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, "barrages", id)
	world.clear_attacks()
	world.completed = false
	world.emit_projectile(id, world.boss, 0, 1)
	_expect(world.issue.is_empty(), "valid project: " + world.issue)
	return world

func _attack(project: STGProject, form: String = "moving") -> STGBarrageSkill:
	var material = Defaults.bullet(form)
	project.bullets.append(material)
	var attack = Defaults.barrage(material.id)
	attack.fire_pattern.count = 1
	attack.fire_pattern.rounds = 1
	attack.projectile.motion_stages.assign([Defaults.stage("wait")])
	project.barrages.append(attack)
	return attack

func _advance(world: STGSimulation, seconds: float) -> void:
	for i in int(round(seconds / STGSimulation.STEP)):
		world.step()

func _run() -> void:
	_test_velocity_and_ballistic()
	_test_activation()
	_test_falloff()
	_test_delayed_successor()
	_test_hit_successor()
	_test_explosion_contact()
	_test_ground()
	_test_cycle()
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_velocity_and_ballistic() -> void:
	var project = _project()
	var bullet = _attack(project)
	bullet.projectile.motion_stages[0] = Defaults.stage("velocity")
	bullet.projectile.motion_stages[0].duration = 2
	bullet.projectile.motion_stages[0].speed = 230
	var world = _world(project, bullet.id)
	world.player = Vector2(-1000, -1000)
	world.actors[0].rotation = PI / 4
	_advance(world, 1)
	_expect(world.actors[0].position.is_equal_approx(Vector2(320, 0) + Vector2.from_angle(PI / 4) * 230), "velocity preserves emission heading")
	world.free()
	bullet.projectile.motion_stages[0] = Defaults.stage("ballistic")
	bullet.projectile.motion_stages[0].flight_time = 1
	world = _world(project, bullet.id)
	world.step()
	world.player = Vector2(-1000, -1000)
	_advance(world, 1 - STGSimulation.STEP)
	_expect(world.actors[0].position.distance_to(Vector2(-320, 0)) < 0.0001, "ballistic reaches locked target despite later player movement")
	world.free()

func _test_activation() -> void:
	var project = _project()
	var bullet = _attack(project, "area")
	bullet.projectile.lifecycle.warning = 0
	bullet.projectile.lifecycle.hit_mode = "activation"
	var world = _world(project, bullet.id)
	world.step()
	world.player = world.actors[0].position
	world.step()
	_expect(world.hits == 0, "activation attack cannot hit when player enters later")
	world.free()
	bullet.projectile.lifecycle.hit_mode = "persistent"
	world = _world(project, bullet.id)
	world.step()
	world.player = world.actors[0].position
	world.step()
	_expect(world.hits == 1, "persistent area still hits later")
	world.free()

func _test_delayed_successor() -> void:
	var project = _project()
	var parent = _attack(project)
	parent.projectile.lifecycle.fade = 0
	parent.projectile.motion_stages[0] = Defaults.stage("wait")
	parent.projectile.motion_stages[0].duration = 0.05
	var child = _attack(project)
	child.projectile.lifecycle.fade = 0
	child.projectile.motion_stages[0] = Defaults.stage("wait")
	child.projectile.motion_stages[0].duration = 0.1
	var split = Defaults.barrage(child.projectile.bullet_id)
	split.projectile = child.projectile.duplicate(true)
	split.fire_pattern.at = 0.1
	split.fire_pattern.count = 2
	split.fire_pattern.rounds = 1
	parent.projectile.lifecycle.on_expire_barrage_id = split.id
	project.barrages.append(split)
	var world = _world(project, parent.id)
	_advance(world, 0.06)
	_expect(world.actors.is_empty() and not world.completed and world.count_owned(1) == 1, "delayed successor keeps parent ownership alive")
	_advance(world, 0.1)
	_expect(world.actors.size() == 2 and world.actors[0].owner_id == 1, "successor inherits parent owner")
	_advance(world, 0.15)
	_expect(world.completed, "finite split finishes without owner deadlock")
	world.free()

func _test_falloff() -> void:
	var project = _project()
	var bullet = _attack(project, "area")
	bullet.projectile.lifecycle.warning = 0
	project.bullets[0].visual.geometry.size = Vector2(200, 200)
	project.bullets[0].collision.size = Vector2(200, 200)
	bullet.projectile.lifecycle.damage = 20
	bullet.projectile.lifecycle.damage_falloff_start = 0.55
	bullet.projectile.lifecycle.damage_falloff_scale = 0.6
	var world = _world(project, bullet.id)
	_expect(is_equal_approx(world.actors[0]._contact_damage(Vector2(330, 0)), 20), "explosion center keeps full damage")
	_expect(is_equal_approx(world.actors[0]._contact_damage(Vector2(390, 0)), 12), "explosion outer ring applies configured falloff")
	world.free()

func _test_hit_successor() -> void:
	var project = _project()
	var parent = _attack(project)
	parent.projectile.lifecycle.fade = 0
	parent.projectile.motion_stages[0] = Defaults.stage("wait")
	var child = _attack(project)
	child.projectile.motion_stages[0] = Defaults.stage("wait")
	var hit_split = Defaults.barrage(child.projectile.bullet_id)
	hit_split.projectile = child.projectile.duplicate(true)
	hit_split.fire_pattern.count = 3
	hit_split.fire_pattern.rounds = 1
	var timeout_split = Defaults.barrage(child.projectile.bullet_id)
	timeout_split.projectile = child.projectile.duplicate(true)
	timeout_split.fire_pattern.count = 1
	timeout_split.fire_pattern.rounds = 1
	parent.projectile.lifecycle.on_hit_barrage_id = hit_split.id
	parent.projectile.lifecycle.on_expire_barrage_id = timeout_split.id
	project.barrages.append_array([hit_split, timeout_split])
	var world = _world(project, parent.id)
	world.player = world.boss
	world.step()
	world.player = Vector2(-1000, -1000)
	world.step()
	_expect(world.actors.size() == 3 and world.hits == 1, "hit split fires once and suppresses timeout split")
	world.free()

func _test_ground() -> void:
	var project = _project()
	var parent = _attack(project)
	parent.projectile.lifecycle.fade = 0
	parent.projectile.lifecycle.exit_mode = "ground"
	parent.projectile.motion_stages[0] = Defaults.stage("ballistic")
	parent.projectile.motion_stages[0].ballistic_aim = false
	parent.projectile.motion_stages[0].initial_velocity = Vector2(70, 40)
	parent.projectile.motion_stages[0].gravity = 520
	var child = _attack(project, "area")
	child.projectile.lifecycle.warning = 0
	project.find("bullets", child.projectile.bullet_id).collision.size = Vector2(2, 2)
	var split = Defaults.barrage(child.projectile.bullet_id, "area")
	split.projectile = child.projectile.duplicate(true)
	split.fire_pattern.anchor = "origin"
	parent.projectile.lifecycle.on_expire_barrage_id = split.id
	project.barrages.append(split)
	var world = _world(project, parent.id)
	_advance(world, 0.9)
	_expect(world.actors.size() == 1 and is_equal_approx(world.actors[0].position.y, 220), "ground successor uses crossing world position")
	world.free()

func _test_explosion_contact() -> void:
	var project = _project()
	var parent = _attack(project)
	parent.projectile.lifecycle.damage_on_contact = false
	parent.projectile.motion_stages[0] = Defaults.stage("wait")
	var explosion = _attack(project, "area")
	explosion.projectile.lifecycle.warning = 0
	explosion.projectile.lifecycle.hit_mode = "activation"
	var split = Defaults.barrage(explosion.projectile.bullet_id)
	split.projectile = explosion.projectile.duplicate(true)
	split.fire_pattern.count = 1
	split.fire_pattern.rounds = 1
	parent.projectile.lifecycle.on_hit_barrage_id = split.id
	project.barrages.append(split)
	var world = _world(project, parent.id)
	world.player = world.boss
	world.step()
	_expect(world.hits == 0, "explosive carrier suppresses contact damage")
	world.step()
	world.step()
	_expect(world.hits == 1, "explosion alone deals one activation hit")
	world.free()

func _test_cycle() -> void:
	var project = _project()
	var bullet = _attack(project)
	var loop = Defaults.barrage(bullet.projectile.bullet_id)
	loop.projectile.lifecycle.on_expire_barrage_id = loop.id
	bullet.projectile.lifecycle.on_expire_barrage_id = loop.id
	project.barrages.append(loop)
	_expect(not project.validate().is_empty(), "successor cycles are rejected")

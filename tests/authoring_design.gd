extends SceneTree
## 待实施设计第一版：整轮分组、独立生成模式、阶段贴图、GIF 导入及资产闭包。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Frames = preload("res://stg/definitions/texture_frames.gd")
const Gif = preload("res://addons/stg_maker/authoring/gif_import.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Store = preload("res://addons/stg_maker/authoring/asset_store.gd")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func fixture(form: String = "moving") -> STGProject:
	var project = STGProject.create()
	var material = Factory.bullet(form)
	project.bullets.append(material)
	var attack = Factory.barrage(material.id)
	attack.fire_pattern.count = 12
	attack.fire_pattern.rounds = 1
	attack.fire_pattern.angle = 0
	attack.fire_pattern.spread = 110
	attack.projectile.motion_stages[0].duration = 5
	project.barrages.append(attack)
	return project

func world_for(project: STGProject) -> STGSimulation:
	var world = STGSimulation.new()
	root.add_child(world)
	world.reset(project, "barrages", project.barrages[0].id)
	world.player = Vector2(-10000, -10000)
	check(world.issue.is_empty(), "新配置通过正式校验：" + world.issue)
	return world

func run() -> void:
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	_test_groups()
	_test_delivery()
	_test_summons()
	_test_trail_length()
	_test_gif()
	_test_frame_clock_and_particles()
	_test_public_binding_and_frame_transition()
	_test_simultaneous_random_order()
	await _test_exported_gif()
	print("AUTHORING DESIGN RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_groups() -> void:
	var project = fixture()
	var pattern = project.barrages[0].fire_pattern
	pattern.rotation_per_projectile = 7
	var simultaneous = world_for(project)
	simultaneous.step(0)
	var headings = simultaneous.actors.map(func(actor): return actor.rotation)
	var grouped_project = project.snapshot()
	grouped_project.barrages[0].fire_pattern.group_size = 3
	grouped_project.barrages[0].fire_pattern.group_interval = 0.1
	var grouped = world_for(grouped_project)
	grouped.step(0)
	check(grouped.actors.size() == 3, "0 秒发出第一批 3 颗")
	grouped.step(0.099)
	check(grouped.actors.size() == 3, "组间等待不提前发出")
	grouped.step(0.001)
	check(grouped.actors.size() == 6, "0.1 秒发出第二批")
	grouped.step(0.1)
	check(grouped.actors.size() == 9, "0.2 秒发出第三批")
	grouped.step(0.1)
	check(grouped.actors.size() == 12, "0.3 秒发完第四批")
	for i in 12: check(is_equal_approx(grouped.actors[i].rotation, headings[i]), "第 %d 颗方向与整轮齐射一致" % i)
	check(grouped.barrages[0].emission_finished(), "最后一批发完关闭发射会话")
	simultaneous.free()
	grouped.free()
	grouped_project.barrages[0].fire_pattern.count = 10
	grouped = world_for(grouped_project)
	grouped.step(0.3)
	check(grouped.actors.size() == 10, "末组保留一颗余数，不补发或丢弃")
	grouped.free()
	grouped = world_for(grouped_project)
	grouped.step(0)
	var owner = grouped.barrages[0].owner_id
	grouped.stop_owner(owner)
	grouped.step(1)
	check(grouped.actors.is_empty() and grouped.barrages.is_empty(), "中断取消未来分组，不留下待发射队列")
	grouped.free()
	grouped_project.barrages[0].fire_pattern.group_interval = 0
	grouped = world_for(grouped_project)
	grouped.step(0)
	check(grouped.actors.size() == 10, "零组间隔在同一时刻发完")
	grouped.free()

func _test_public_binding_and_frame_transition() -> void:
	var typed: STGExtensionBinding = STGExtensionBinding.create(null)
	var inferred := STGExtensionBinding.create(null)
	check(typed is STGExtensionBinding and inferred.parameters == {}, "工厂保留实际绑定类型及常用推断变量的参数访问")
	var imported = Gif.new().load_clip("res://tests/fixtures/phase_gif/disposal.gif")
	if not imported.issue.is_empty(): return
	var project = fixture()
	var visual = project.bullets[0].visual
	visual.mode = "texture"
	visual.spawn_clip = imported.clip
	visual.run_clip = SpriteFrames.new()
	visual.run_clip.set_animation_speed(&"default", 1.0)
	visual.run_clip.add_frame(&"default", imported.clip.get_frame_texture(&"default", 0), 0.03)
	visual.run_clip.add_frame(&"default", imported.clip.get_frame_texture(&"default", 1), 0.03)
	var world = world_for(project)
	world.step(0)
	var actor = world.actors[0]
	actor.age = Frames.duration(visual.spawn_clip) + 0.025
	check(actor.current_texture() == visual.run_clip.get_frame_texture(&"default", 0), "无前摇时发射动画播完，运行动画从自己的零时刻开始")
	world.free()

func _test_simultaneous_random_order() -> void:
	var project = fixture()
	var enemy = Factory.boss()
	enemy.phases[0].behavior_flow = Factory.flow([Factory.action()])
	project.bosses.append(enemy)
	var pattern = project.barrages[0].fire_pattern
	pattern.enemy_id = enemy.id
	pattern.direction = "random"
	pattern.count = 3
	var expected = RandomNumberGenerator.new()
	expected.seed = 42
	for i in 3:
		expected.randf_range(0, TAU)
		expected.randi()
	var world = world_for(project)
	world.step(0)
	check(world.rng.state == expected.state, "默认齐射保留方向随机与召唤种子的逐颗取样顺序")
	world.free()

func _test_delivery() -> void:
	var project = fixture("laser")
	var attack = project.barrages[0]
	attack.fire_pattern.count = 1
	attack.fire_pattern.spread = 0
	attack.projectile.lifecycle.warning = 0.1
	attack.projectile.delivery = "position"
	var fixed = world_for(project)
	fixed.step(0.05)
	var initial: Vector2 = fixed.actors[0].position
	check(fixed.actors[0].stage_index == -1, "指定位置生成仍经历前摇")
	fixed.step(0.1)
	check(fixed.actors[0].position == initial, "指定位置模式不执行运动")
	fixed.free()
	attack.projectile.delivery = "trajectory"
	var moving = world_for(project)
	moving.step(0.15)
	check(moving.actors[0].position.x > moving.boss.x, "相同激光使用同一运行器沿弹道运动")
	moving.free()

func _test_summons() -> void:
	var project = fixture()
	var enemy = Factory.boss()
	var wait = Factory.action()
	wait.duration = 10
	enemy.phases[0].behavior_flow = Factory.flow([wait])
	project.bosses.append(enemy)
	var attack = project.barrages[0]
	attack.fire_pattern.enemy_id = enemy.id
	attack.fire_pattern.count = 1
	attack.fire_pattern.spread = 0
	attack.projectile.lifecycle.warning = 0.1
	attack.fire_pattern.summon_mode = "launch"
	attack.fire_pattern.summon_launch_speed = 100
	attack.fire_pattern.summon_launch_duration = 0.2
	var compiled = Compiler.compile_library(project, [{"collection": "barrages", "id": attack.id}])
	check(compiled.issue.is_empty() and compiled.library.bullets.is_empty(), "召唤依赖敌人，不带入未使用的子弹素材")
	var world = world_for(project)
	world.step(0.05)
	check(world.summons.size() == 1 and world.summons[0].world.boss_player == null, "前摇尚未启动敌人 AI")
	var initial: Vector2 = world.summons[0].world.boss
	world.step(0.1)
	check(world.summons[0].world.boss.is_equal_approx(initial + Vector2(5, 0)), "前摇结束后只推进剩余入场时间")
	check(world.summons[0].world.boss_player == null, "入场期间敌人 AI 不争抢位置")
	world.step(0.2)
	check(not world.summons[0].pending and world.summons[0].world.boss_player != null, "入场完成后启动正式敌人行为运行器")
	check(world.summons[0].world.boss.is_equal_approx(initial + Vector2(20, 0)), "接管保持入场终点，无坐标跳变")
	world.free()
	attack.projectile.lifecycle.on_hit_barrage_id = "unused_projectile_successor"
	compiled = Compiler.compile_library(project, [{"collection": "barrages", "id": attack.id}])
	check(compiled.issue.is_empty(), "召唤不读取未使用的弹体命中后继")
	world = world_for(project)
	check(world.emit_projectile(attack.id, Vector2.ZERO, 0) == null and world.issue.contains("play_barrage"), "公开单弹体接口明确拒绝召唤类型")
	world.free()
	var source = Factory.barrage(project.bullets[0].id)
	var transform = Factory.stage("transform")
	transform.transform_attack_id = attack.id
	source.projectile.motion_stages.assign([transform])
	project.barrages.append(source)
	check(Array(project.validate()).any(func(issue): return issue.contains("召唤不能作为弹体变形目标")), "变形引用在执行前检查招式类型")

func _test_exported_gif() -> void:
	var imported = Gif.new().load_clip("res://tests/fixtures/phase_gif/disposal.gif")
	if not imported.issue.is_empty(): return
	# 三个独立冷目录各自构建、导入、启动及释放；不以重试吞掉非零退出。
	for pass_index in 3:
		var game = preload("res://tests/game_fixture.gd").create()
		var material = game.library.bullets[0]
		material.visual.mode = "texture"
		material.visual.run_clip = imported.clip
		game.library.bosses[0].phases[0].behavior_flow = Factory.flow([Factory.action("fire", game.library.barrages[0].id)])
		var builder = preload("res://addons/stg_maker/build/project_builder.gd")
		var output = "user://phase_gif_export_%d" % Time.get_ticks_usec()
		var built = builder.build(game, output)
		check(built.issue.is_empty(), "GIF 素材能构建独立游戏：" + built.issue)
		if not built.issue.is_empty(): return
		check(not FileAccess.file_exists(output.path_join("addons/stg_maker/authoring/gif_import.gd")), "成品只带帧资源和正式运行器，不带 GIF 导入工具")
		var runner = preload("res://tests/export_runtime.gd")
		var log: Array = []
		var code = runner.import_project(built.path, log)
		check(code == 0 and not builder._has_errors(log), "GIF 独立工程可冷导入，退出码 %d：" % code + "\n".join(log))
		log.clear()
		code = runner.run(built.path, log)
		check(code == 0 and not builder._has_errors(log), "GIF 独立工程可用实际图形后端启动，退出码 %d：" % code + "\n".join(log))

func _test_trail_length() -> void:
	var project = fixture("trail")
	var attack = project.barrages[0]
	attack.fire_pattern.count = 1
	attack.trail_max_length = 25
	project.bullets[0].trail_offset = 0
	var world = world_for(project)
	world.step(0)
	for i in 10:
		world.boss.x += 10
		world.step(0.01)
	var length = 0.0
	for segment in world.actors[0].segments: length += segment.a.distance_to(segment.b)
	check(is_equal_approx(length, 25), "路径按距离裁剪最旧段，精确保留最大长度")
	world.free()

func _test_gif() -> void:
	var expected = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/phase_gif/expected.json"))
	for name in ["disposal", "lzw"]:
		var imported = Gif.new().load_clip("res://tests/fixtures/phase_gif/" + name + ".gif")
		check(imported.issue.is_empty(), name + "：GIF 解码成功：" + imported.issue)
		if not imported.issue.is_empty(): continue
		var clip: SpriteFrames = imported.clip
		check(clip.get_frame_count(&"default") == expected[name].size(), name + "：保留全部帧")
		for i in clip.get_frame_count(&"default"):
			check(is_equal_approx(clip.get_frame_duration(&"default", i) / clip.get_animation_speed(&"default"), expected[name][i].duration), "GIF 帧时长与独立解码结果一致")
			var image = clip.get_frame_texture(&"default", i).get_image()
			image.convert(Image.FORMAT_RGBA8)
			check(image.get_data().hex_encode().sha256_text() == expected[name][i].hash, "GIF 合成像素与 Pillow 一致：%s/%d" % [name, i])
	var invalid = "user://invalid_phase.gif"
	var file = FileAccess.open(invalid, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([71, 73, 70]))
	file.close()
	check(not Gif.new().load_clip(invalid).issue.is_empty(), "损坏 GIF 返回错误，不进入资源库")
	DirAccess.remove_absolute(invalid)

func _test_frame_clock_and_particles() -> void:
	var imported = Gif.new().load_clip("res://tests/fixtures/phase_gif/disposal.gif")
	if not imported.issue.is_empty(): return
	var project = fixture()
	var material = project.bullets[0]
	material.visual.mode = "texture"
	material.visual.run_clip = imported.clip
	material.visual.spawn_clip = imported.clip
	material.visual.expire_clip = imported.clip
	material.visual.hit_clip = imported.clip
	material.run_particles = load("res://examples/presentation/pulse_sparks.tscn")
	material.spawn_particles = material.run_particles
	material.hit_particles = material.run_particles
	var attack = project.barrages[0]
	attack.fire_pattern.count = 1
	attack.projectile.lifecycle.warning = 0.2
	attack.projectile.lifecycle.fade = 0.3
	var world = world_for(project)
	world.step(0.1)
	var actor = world.actors[0]
	check(actor.current_texture() == Frames.texture_at(imported.clip, Frames.duration(imported.clip) / 2), "前摇动画按配置时长适配进度")
	check(actor.particle_presentation != null and not actor.particle_presentation.particles[0].node.emitting, "贴图子弹在前摇期间不开运行粒子")
	var selected = actor.current_texture()
	check(actor.current_texture() == selected, "读取动画帧不会推进时钟")
	world.step(0.15)
	check(actor.particle_presentation.particles[0].node.emitting, "前摇结束后开始运行粒子")
	check(Frames.duration(material.visual.run_clip) > 0 and imported.clip.get_frame_count(&"default") == 4, "播放不改共享帧数据")
	var save_path = "user://phase_roundtrip_%d/library.tres" % Time.get_ticks_usec()
	check(Store.save_library(project, save_path).is_empty(), "GIF 帧通过正式资产事务保存")
	var restored: STGProject = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored != null and restored.validate().is_empty(), "重开导入动画资源通过校验")
	check(restored.bullets[0].visual.run_clip.get_frame_texture(&"default", 2).get_image().get_data() == imported.clip.get_frame_texture(&"default", 2).get_image().get_data(), "保存与重开保留合成帧像素")
	var second_path = save_path.get_base_dir().path_join("resaved.tres")
	check(Store.save_library(restored, second_path).is_empty(), "重开的原生帧素材可以再次保存")
	var resaved: STGProject = ResourceLoader.load(second_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(resaved.bullets[0].visual.run_clip.get_frame_texture(&"default", 2).get_image().get_data() == imported.clip.get_frame_texture(&"default", 2).get_image().get_data(), "再次保存没有丢失原生纹理的压缩源数据")
	world.present_material_hit(actor)
	check(world.effects.any(func(entry): return entry.node.get_script() == preload("res://stg/runtime/attacks/material_frame_effect.gd")), "命中动画在原弹体外独立收尾")
	world.free()
	project = fixture()
	material = project.bullets[0]
	material.run_particles = load("res://examples/presentation/pulse_sparks.tscn")
	world = world_for(project)
	world.step(0)
	check(world.actors[0].particle_presentation != null, "几何子弹同样可以使用运行粒子")
	world.free()

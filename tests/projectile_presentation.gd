extends SceneTree
## 表现使用正式实例与固定时钟；同一美术场景供子弹、激光、拖尾、区域引用。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Store = preload("res://addons/stg_maker/authoring/asset_store.gd")
const Art = preload("res://examples/presentation/pulse_sparks.tscn")
var checks = 0
var failures = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	for form in ["moving", "laser", "trail", "area"]:
		var project = STGProject.create()
		var material = Factory.bullet(form)
		material.visual_scene = Art
		material.visual_animation = "pulse"
		material.show_base_visual = false
		project.bullets.append(material)
		var skill = Factory.barrage(material.id)
		skill.projectile.motion_stages[0].mode = "wait"
		skill.projectile.motion_stages[0].duration = 5
		project.barrages.append(skill)
		check(project.validate().is_empty(), form + "：表现场景通过正式配置校验")
		var world = STGSimulation.new()
		root.add_child(world)
		world.reset(project, "bullets", material.id)
		var actor = world.emit_projectile(skill.id, Vector2.ZERO, 0)
		if actor is STGBulletTrailActor: actor.recording = true
		check(actor != null and actor.presentation != null, form + "：正式运行创建独立表现实例")
		var player: AnimationPlayer = actor.presentation.animations[0]
		check(player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, form + "：动画没有独立自动计时")
		world.step(0.125)
		check(is_equal_approx(player.current_animation_position, 0.125), form + "：动画按正式模拟步长推进")
		var scale_value: Vector2 = actor.presentation.get_node("PulseSparks/Glow").scale
		check(scale_value.is_equal_approx(Vector2.ONE), form + "：美术节点实际应用动画插值")
		for i in 5: await process_frame
		check(is_equal_approx(player.current_animation_position, 0.125), form + "：只刷新画面不推进动画")
		var particles: CPUParticles2D = actor.presentation.particles[0].node
		check(particles.speed_scale == 0 and particles.has_method("request_particles_process"), form + "：粒子由同一模拟时钟请求更新")
		particles.emitting = false
		world.step(0.01)
		check(not particles.emitting, form + "：停止发射后只推进残留粒子，不重新开启发射")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var before_pause = root.get_texture().get_image().get_data()
			for i in 5: await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().get_data() == before_pause, form + "：真实渲染中暂停画面保持一致")
		var second = world.emit_projectile(skill.id, Vector2(40, 20), 0)
		check(second.presentation != actor.presentation and second.presentation.animations[0] != player, form + "：共享定义没有共享播放状态")
		check(is_zero_approx(second.presentation.animations[0].current_animation_position), form + "：新实例从零播放")
		check(actor.definition == material and material.visual_scene == Art, form + "：播放不改写共享素材")
		var before = actor.collision
		material.show_base_visual = true
		check(actor.collision == before, form + "：显示基础外观不改变碰撞")
		var compiled = Compiler.compile_library(project, [{"collection": "barrages", "id": skill.id}])
		check(compiled.issue.is_empty() and compiled.library.bullets[0].visual_scene == Art, form + "：构建保留表现场景依赖")
		var saved = "user://presentation_%s_%d/library.tres" % [form, Time.get_ticks_usec()]
		check(Store.save_library(project, saved).is_empty(), form + "：表现场景随素材通过正式事务保存")
		var restored: STGProject = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(restored.bullets[0].visual_scene == Art and restored.bullets[0].visual_animation == "pulse", form + "：重新加载保留场景和动画引用")
		world.restart_selected(material.id)
		check(is_zero_approx(world.actors[0].presentation.animations[0].current_animation_position), form + "：重新测试重建表现状态")
		world.free()
	await _test_gpu_clock()
	await _test_exported_presentation()
	var bad = Factory.bullet()
	bad.visual_scene = Art
	bad.visual_animation = "missing"
	var invalid = STGProject.create()
	invalid.bullets.append(bad)
	check(Array(invalid.validate()).any(func(issue): return issue.contains("缺少动画")), "错误动画名在试玩和构建前被校验")
	print("PROJECTILE PRESENTATION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_gpu_clock() -> void:
	var art = Node2D.new()
	var sparks = GPUParticles2D.new()
	var process = ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.spread = 180
	process.initial_velocity_min = 30
	process.initial_velocity_max = 50
	sparks.process_material = process
	sparks.amount = 24
	sparks.lifetime = 1
	sparks.local_coords = true
	sparks.use_fixed_seed = true
	sparks.seed = 42
	art.add_child(sparks)
	sparks.owner = art
	var packed = PackedScene.new()
	packed.pack(art)
	art.free()
	var project = STGProject.create()
	var material = Factory.bullet()
	material.visual_scene = packed
	material.show_base_visual = false
	project.bullets.append(material)
	var world = STGSimulation.new()
	root.add_child(world)
	world.position = Vector2(100, 150)
	world.reset(project, "bullets", material.id)
	check(world.issue.is_empty() and world.actors[0].presentation.particles[0].node is GPUParticles2D, "GPU 粒子通过同一素材与正式预览入口创建")
	for i in 24: world.step()
	if DisplayServer.get_name() != "headless":
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var paused = root.get_texture().get_image().get_data()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_data() == paused, "GPU 粒子暂停后真实画面保持一致")
		for i in 24: world.step()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_data() != paused, "同帧多个固定步长累计后 GPU 粒子继续运动")
	world.free()

func _test_exported_presentation() -> void:
	var game = preload("res://tests/game_fixture.gd").create()
	game.library.bullets[0].visual_scene = Art
	game.library.bullets[0].visual_animation = "pulse"
	game.library.bosses[0].phases[0].behavior_flow = Factory.flow([Factory.action("fire", game.library.barrages[0].id)])
	var output = "user://presentation_export_%d" % Time.get_ticks_usec()
	var builder = preload("res://addons/stg_maker/build/project_builder.gd")
	var built = builder.build(game, output)
	check(built.issue.is_empty(), "带有表现场景的独立游戏可构建：" + built.issue)
	if not built.issue.is_empty(): return
	check(FileAccess.file_exists(output.path_join("examples/presentation/pulse_sparks.tscn")), "已引用的表现场景进入独立工程")
	check(FileAccess.file_exists(output.path_join("examples/presentation/spark.svg")), "场景的贴图依赖一并收集")
	var log: Array = []
	var runner = preload("res://tests/export_runtime.gd")
	var code = runner.import_project(built.path, log)
	check(code == 0 and not builder._has_errors(log), "带动画和粒子的全新工程可冷导入：" + "\n".join(log))
	log.clear()
	code = runner.run(built.path, log)
	check(code == 0 and not builder._has_errors(log), "带表现场景的独立工程使用实际图形后端正常启动：" + "\n".join(log))

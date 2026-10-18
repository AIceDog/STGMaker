extends SceneTree
## 轨迹回归：正式运动一致性、局部飞行配置、固定目标 / 随机种子、资源隔离与取消。
const Factory = preload("res://stg/definitions/definition_factory.gd")
const Sampler = preload("res://addons/stg_maker/ui/trajectory_preview.gd")
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Transport = preload("res://addons/stg_maker/ui/preview_transport.gd")
var checks = 0
var failures: PackedStringArray = []

class RecordingMotion:
	extends STGMotionExtension
	static var instances: Array = []
	var cancellations: PackedStringArray = []
	func start(_context: STGMotionContext, _parameters: Dictionary) -> void:
		instances.append(self)
	func tick(context: STGMotionContext, dt: float) -> void:
		context.set_position(context.position() + Vector2(-20, 0) * dt)
	func cancel(reason: String) -> void:
		cancellations.append(reason)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func project(form: String = "moving") -> STGProject:
	var result = STGProject.create()
	result.schema_version = STGProject.VERSION
	var bullet = Factory.bullet(form)
	result.bullets.append(bullet)
	var barrage = Factory.trail_attack(bullet.id) if form == "trail" else Factory.barrage(bullet.id)
	barrage.fire_pattern.count = 1
	barrage.fire_pattern.rounds = 1
	barrage.fire_pattern.direction = "parallel"
	barrage.fire_pattern.angle = 180
	var stage = Factory.stage("velocity" if form == "moving" else "wait")
	stage.speed = 120
	stage.duration = 1
	barrage.projectile.motion_stages.assign([stage])
	barrage.projectile.lifecycle.warning = 0
	barrage.projectile.lifecycle.fade = 0
	result.barrages.append(barrage)
	return result

func finish(sampler) -> void:
	var batches = 0
	while sampler.running and batches < 100:
		sampler.advance(96, 0)
		batches += 1
	check(not sampler.running, "采样在有限批次内结束")

func _run() -> void:
	var library = project()
	var bullet = library.bullets[0]
	var shot = library.barrages[0].fire_pattern
	check(library.validate().is_empty(), "轨迹测试资源有效")
	var sampler = Sampler.new()
	sampler.start(library, library.barrages[0].id, Vector2(-400, 180))
	finish(sampler)
	check(sampler.paths.size() == 1 and sampler.issue.is_empty(), "普通弹采样完整飞行路径")
	var last: Vector2 = sampler.paths[0].points[-1]
	check(last.distance_to(CombatSpace.ENEMY_SPAWN + Vector2(-120, 0)) < 0.001, "虚线路径终点使用正式 120 Hz 直线运动")
	check(library.barrages[0].projectile.motion_stages[0].duration == 1 and library.barrages[0].projectile.motion_stages[0].speed == 120, "采样不改原始资源运动参数")
	check(library.find("barrages", library.barrages[0].id).fire_pattern == shot, "采样不替换原资源引用")
	library.barrages[0].projectile.motion_stages.assign([Factory.stage("velocity")])
	library.barrages[0].projectile.motion_stages[0].speed = 80
	library.barrages[0].projectile.motion_stages[0].duration = 1
	sampler.start(library, library.barrages[0].id, Vector2(-400, 180))
	finish(sampler)
	last = sampler.paths[0].points[-1]
	check(last.is_equal_approx(CombatSpace.ENEMY_SPAWN + Vector2(-80, 0)), "招式局部飞行规则与实际运行一致")
	check(library.barrages[0].projectile.motion_stages[0].speed == 80 and bullet.visual.geometry.size == Vector2(20, 20), "采样不改写招式参数或静态素材")
	shot.angle_jitter = 35
	shot.speed_scale_min = 0.7
	shot.speed_scale_max = 1.3
	shot.count = 7
	sampler.start(library, library.barrages[0].id, Vector2(-400, 180))
	finish(sampler)
	var first_paths = sampler.paths.duplicate(true)
	sampler.start(library, library.barrages[0].id, Vector2(-400, 180))
	finish(sampler)
	check(sampler.paths == first_paths, "独立随机种子使随机散射轨迹可复现")
	seed(9182)
	var expected = randi()
	seed(9182)
	sampler.start(library, library.barrages[0].id, Vector2(-400, 180))
	finish(sampler)
	check(randi() == expected, "采样不消耗全局随机流")
	shot.count = 1
	shot.angle_jitter = 0
	shot.speed_scale_min = 1
	shot.speed_scale_max = 1
	shot.direction = "aim"
	shot.aim_lock = "call_start"
	var target = Vector2(-250, 160)
	sampler.start(library, library.barrages[0].id, target)
	finish(sampler)
	var delta: Vector2 = sampler.paths[0].points[1] - sampler.paths[0].points[0]
	check(delta.normalized().is_equal_approx((target - CombatSpace.ENEMY_SPAWN).normalized()), "开始即锁定的瞄准使用当前预览玩家位置")
	var previous = sampler.paths[0].points.duplicate()
	sampler.start(library, library.barrages[0].id, Vector2(-250, -160))
	finish(sampler)
	check(sampler.paths[0].points != previous, "移动目标后重新采样方向改变")
	for form in ["laser", "area", "trail"]:
		var special = project(form)
		sampler.start(special, special.barrages[0].id, target)
		finish(sampler)
		check(sampler.paths.is_empty() and sampler.omitted_forms, "不把 %s 范围伪装成飞行弹道" % form)
	library = project()
	shot = library.barrages[0].fire_pattern
	shot.count = 256
	shot.spread = 360
	sampler.start(library, library.barrages[0].id, target)
	finish(sampler)
	check(sampler.paths.size() == Sampler.MAX_PATHS and sampler.limited, "密集弹幕限制可视路径与模拟实例数")
	check("截取" in sampler.status(), "截取结果明确显示限制")
	library = project()
	library.barrages[0].projectile.motion_stages[0].duration = 60
	library.barrages[0].projectile.motion_stages[0].speed = 1
	sampler.start(library, library.barrages[0].id, target)
	finish(sampler)
	check(sampler.limited and sampler._steps == 960, "超长弹道按八秒预览窗口截止")
	var extension = STGExtensionDefinition.new()
	extension.id = "trajectory_cancel_test"
	var declaration = RecordingMotion.new()
	extension.implementation = declaration.get_script()
	RecordingMotion.instances.clear()
	var stage = library.barrages[0].projectile.motion_stages[0]
	stage.mode = "extension"
	stage.extension = STGExtensionBinding.create(extension)
	sampler.start(library, library.barrages[0].id, target)
	sampler.advance(8, 0)
	check(sampler.running and RecordingMotion.instances.size() == 1, "分批采样拥有独立扩展实例")
	var execution = RecordingMotion.instances[0]
	sampler.cancel()
	sampler.cancel()
	check(execution.cancellations == PackedStringArray(["stopped"]), "取消预估仅结束一次运动扩展")
	check(not sampler.advance(8, 0), "取消后不会继续执行采样")
	RecordingMotion.instances.clear()
	await _test_canvas()
	print("TRAJECTORY PREVIEW RESULT: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_canvas() -> void:
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://trajectory_preview_checks.cfg"
	root.add_child(studio)
	for i in 8: await process_frame
	studio.set_process(false)
	var canvas = studio.canvas
	canvas.request_trajectories()
	finish(canvas.trajectory)
	check(not canvas.trajectory.paths.is_empty() and not studio.playing, "暂停状态也能看到整段招式轨迹")
	var live_time = canvas.world.time
	var live_rng = canvas.world.rng.state
	var live_hits = canvas.world.hits
	canvas.request_trajectories()
	finish(canvas.trajectory)
	check(canvas.world.time == live_time and canvas.world.rng.state == live_rng and canvas.world.hits == live_hits, "独立预估不推进真实预览时钟、随机流或命中状态")
	canvas.world.player += Vector2(0, 100)
	canvas._trajectory_last_request = -10000
	canvas._process(0)
	check(canvas.trajectory.target == canvas.world.player, "画布移动玩家自动更新预估")
	canvas.set_trajectories_visible(false)
	check(canvas.trajectory.paths.is_empty() and not canvas.trajectory.running, "关闭轨迹清空结果并取消后台模拟")
	canvas.set_trajectories_visible(true)
	canvas.hide()
	canvas._process(0)
	check(not canvas.trajectory.running and canvas.trajectory.paths.is_empty(), "隐藏预览停止采样")
	canvas.show()
	canvas._process(0)
	check(canvas.trajectory.running, "恢复同一招式预览时重新建立轨迹")
	studio.set_tool("flight_path")
	check(canvas.path != null and canvas.path_scope == studio.motion_scope(), "招式曲线路径工具指向当前招式的飞行配置")
	var original: Curve2D = studio.motion_stage().path
	var original_point = original.get_point_position(1)
	var changed: Curve2D = canvas.path.duplicate(true)
	changed.set_point_position(1, original_point + Vector2(10, 40))
	studio.edit_path(canvas.path_scope, "path", changed, true)
	for i in 4: await process_frame
	check(not studio.current().projectile.motion_stages.is_empty(), "编辑飞行路径按需建立招式局部过程")
	check(original.get_point_position(1) == original_point and studio.motion_stage().path.get_point_position(1) != original_point, "曲线手柄不改变其他招式共享的招式路径")
	var second = Factory.barrage(studio.current().projectile.bullet_id)
	second.projectile.motion_stages[0].mode = "path"
	second.projectile.motion_stages[0].path = Factory.path([Vector2.ZERO, Vector2(120, 40), Vector2(160, 160)])
	studio.session.project.barrages.append(second)
	studio.show_collection("barrages", second.id)
	studio.set_tool("flight_path")
	for i in 4: await process_frame
	check(canvas.path_scope == studio.motion_scope() and canvas.path.get_point_position(1) == Vector2(120, 40), "切换招式更新曲线与提交范围")
	await _test_seeking(studio)
	studio.switch_collection("bullets")
	check(canvas.trajectory.paths.is_empty(), "离开招式工作区清空轨迹")
	studio.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://trajectory_preview_checks.cfg"))

func _finish_seek(canvas) -> void:
	var batches = 0
	while canvas.is_seeking() and batches < 100:
		canvas._advance_seek()
		batches += 1
	check(not canvas.is_seeking(), "时间定位在有限批次内完成")

func _test_seeking(studio) -> void:
	var canvas = studio.canvas
	studio.set_tool("none")
	var target: Vector2 = canvas.world.player
	var undo_size = studio.session.undo_stack.size()
	canvas.seek_preview(0.5)
	check(canvas.is_seeking() and not studio.playing and canvas.world.time == 0, "时间定位暂停并分帧重放")
	_finish_seek(canvas)
	check(absf(canvas.world.time - 0.5) < 0.00001 and canvas.world.player == target, "时间定位保留当前目标并到达正确固定帧")
	var reference = STGSimulation.new()
	reference.reset(studio.session.project, "barrages", studio.selected_id, Sampler.SEED)
	reference.player = target
	reference.previous_player = target
	for barrage in reference.barrages: barrage.locked_player = target
	for i in 60: reference.step()
	check(canvas.world.actors.size() == reference.actors.size(), "时间定位与独立正式模拟的实例数一致")
	var equal_positions = canvas.world.actors.size() == reference.actors.size()
	for i in mini(canvas.world.actors.size(), reference.actors.size()):
		equal_positions = equal_positions and canvas.world.actors[i].position.distance_to(reference.actors[i].position) < 0.001
	check(equal_positions, "时间定位与独立正式模拟的位置一致")
	for actor in reference.actors: actor.stop()
	reference.free()
	check(studio.session.undo_stack.size() == undo_size, "拖动预览时间不产生资源撤销记录")
	canvas.seek_preview(0.25)
	_finish_seek(canvas)
	check(absf(canvas.world.time - 0.25) < 0.00001, "向后拖动重新计算而非保留旧实例")
	if not studio.has_meta(Transport.UI_KEY): Transport.build(studio, studio)
	var ui: Dictionary = studio.get_meta(Transport.UI_KEY)
	Transport.update(studio)
	check(not canvas.is_seeking(), "程序同步滑块不触发重放")
	ui.slider.drag_started.emit()
	ui.slider.value = 0.75
	check(not canvas.is_seeking(), "滑块拖动过程只更新目标标签")
	ui.slider.drag_ended.emit(true)
	check(canvas.is_seeking(), "滑块释放提交一次时间定位")
	_finish_seek(canvas)
	check(absf(canvas.world.time - 0.75) < 0.00001, "滑块提交到所选时刻")
	canvas.seek_preview(0)
	check(not canvas.is_seeking() and canvas.world.time == 0 and canvas.world.actors.is_empty(), "拖回起点清除之前的攻击实例")
	canvas.set_trajectories_visible(false)
	var library = project()
	var extension = STGExtensionDefinition.new()
	extension.id = "seek_cancel_test"
	var declaration = RecordingMotion.new()
	extension.implementation = declaration.get_script()
	var stage = library.barrages[0].projectile.motion_stages[0]
	stage.mode = "extension"
	stage.duration = 60
	stage.extension = STGExtensionBinding.create(extension)
	studio.session.project = library
	studio.selected_id = library.barrages[0].id
	studio.refresh(true)
	for i in 4: await process_frame
	var old_execution = canvas.world.actors[0].motion_session.implementation
	canvas.seek_preview(0.5)
	_finish_seek(canvas)
	check(old_execution.cancellations.size() == 1, "向前定位只取消一次旧扩展实例")
	var new_execution = canvas.world.actors[0].motion_session.implementation
	canvas.seek_preview(0.1)
	_finish_seek(canvas)
	check(new_execution.cancellations.size() == 1 and old_execution.cancellations.size() == 1, "向后定位不重复结束已释放的扩展")
	canvas.seek_preview(8)
	canvas.step_preview()
	check(not canvas.is_seeking(), "播放或单步覆盖未完成的定位任务")
	RecordingMotion.instances.clear()

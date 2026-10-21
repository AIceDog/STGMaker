extends SceneTree
## 实际射击、碰撞、暂停、解锁与存档组成完整游戏流程测试，不通过直接扣敌人血模拟胜利。
const Fixture = preload("res://tests/game_fixture.gd")
const Session = preload("res://stg/runtime/game/session.gd")
const Progress = preload("res://stg/runtime/game/progress_store.gd")
const SAVE = "res://tests/.game_flow_progress.json"
const CORRUPT = "res://tests/.game_flow_corrupt.json"
const RECOVERY = "res://tests/.game_flow_recovery.json"
const OVERFLOW = "res://tests/.game_flow_overflow.json"
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func advance(session: STGGameSession, seconds: float, firing: bool = false, movement: Vector2 = Vector2.ZERO) -> void:
	for _tick in ceili(seconds / STGSimulation.STEP):
		session.advance(STGSimulation.STEP, movement, firing)

func remove_test_files(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

func run() -> void:
	remove_test_files(SAVE)
	remove_test_files(CORRUPT)
	remove_test_files(RECOVERY)
	remove_test_files(OVERFLOW)
	var game = Fixture.create()
	check(game.validate().is_empty(), "测试游戏资源有效：%s" % "；".join(game.validate()))
	var session = Session.new()
	root.add_child(session)
	session.configure(game, SAVE)
	check(session.state == "menu" and session.progress.currency == 0, "启动进入菜单并加载独立局外存档")
	session.show_map()
	check(session.state == "map", "菜单进入地图")
	check(not session.enter_location("valley"), "未通关前无法进入锁定地点")
	check(session.enter_location("coast"), "开放地点可进入真实战斗")
	check(session.health == 3 and session.simulation.player_radius == game.player.hit_radius, "主角配置应用于生命和碰撞")
	advance(session, 0.2, false, Vector2(-1, -1))
	check(session.simulation.player.y < 0 and session.simulation.player.x < -320, "实际输入按速度移动主角")
	advance(session, 0.2, false, Vector2(1, 1))
	check(session.simulation.player.is_equal_approx(Vector2(-320, 0)), "对称输入回到射击路线")
	var frozen_time = session.simulation.time
	var frozen_player = session.simulation.player
	session.toggle_pause()
	advance(session, 1, true, Vector2.ONE)
	check(session.state == "paused" and session.simulation.time == frozen_time and session.simulation.player == frozen_player, "暂停冻结战斗和玩家输入")
	session.toggle_pause()
	advance(session, 3, true)
	check(session.state == "result" and session.result.victory, "真实玩家射击完成击败目标条件并进入胜利结算")
	check(session.player_modules.is_empty(), "结算立即关闭主角能力上下文，不等待返回地图")
	check(session.simulation.resolved_entities.values().has("died"), "关卡记录真实死亡，不以离场代替击败")
	check(session.result.reward == 100 and session.progress.currency == 100, "首次通关发放奖励")
	check(session.progress.is_unlocked(game.world.find("valley")), "通关解锁下一地点")
	check(FileAccess.file_exists(SAVE), "胜利后自动保存进度")
	session.return_to_map()
	check(session.state == "map" and session.simulation == null, "返回地图释放战斗运行实例")
	check(session.enter_location("coast"), "已通关地点可以重新挑战")
	advance(session, 3, true)
	check(session.result.victory and session.result.reward == 0 and session.progress.currency == 100, "重复通关不重复发奖")
	session.free()

	session = Session.new()
	root.add_child(session)
	session.configure(game, SAVE)
	check(session.progress.currency == 100 and session.progress.completed.has("coast"), "重建会话后读取通关和货币")
	check(session.enter_location("valley"), "重启后仍保留地点解锁")
	advance(session, 0.15)
	var world = session.simulation
	for hit_index in 3:
		var enemy_simulation = world.entities[0].simulation
		enemy_simulation.play_barrage("straight", world.player, enemy_simulation.allocate_owner(),PI)
		advance(session, 0.05)
		check(session.health == 2 - hit_index, "敌弹实际碰撞扣一格生命：%d" % hit_index)
		if hit_index < 2:
			# 同一无敌窗口再放一颗弹；不能因为敌弹密集而瞬间扣完生命。
			enemy_simulation.play_barrage("straight", world.player, enemy_simulation.allocate_owner(),PI)
			advance(session, 0.15)
			check(session.health == 2 - hit_index, "受击后无敌窗口阻止重复伤害")
			advance(session, 1.05)
	check(session.state == "result" and not session.result.victory, "真实碰撞耗尽生命进入失败结算")
	check(not session.progress.completed.has("valley") and session.progress.currency == 100, "失败不记录通关或奖励")
	check(session.retry() and session.health == 3 and session.elapsed == 0, "重试重建战斗并恢复主角状态")
	advance(session, 20, false, Vector2.ONE)
	check(session.simulation.player.x <= 468 and session.simulation.player.y <= 258, "玩家始终留在战斗边界内")
	session.free()

	var file = FileAccess.open(CORRUPT, FileAccess.WRITE)
	file.store_string("{broken-save")
	file.close()
	var store = Progress.new()
	store.load_progress(CORRUPT)
	check(store.write_blocked and not store.issue.is_empty(), "损坏存档明确报告并阻止自动覆盖")
	store.complete_location(game.world.locations[0])
	check(not store.save() and FileAccess.get_file_as_string(CORRUPT) == "{broken-save", "内存进度不会覆盖损坏原文件")
	check(store.archive_corrupt_and_save(), "显式重建先备份损坏存档，再保存内存进度")
	var restored = Progress.new()
	restored.load_progress(CORRUPT)
	check(restored.currency == 100 and not restored.write_blocked, "重建后的存档可正常读取")
	_test_interrupted_save(game)
	_test_currency_bounds(game)
	var cyclic = game.world.locations[0].requires_completion
	cyclic.assign(["valley"])
	check(not game.validate().is_empty(), "地图解锁循环在运行前被拒绝")
	cyclic.clear()
	game.player.fire_interval = 0
	check(not game.validate().is_empty(), "无效主角配置在运行前被拒绝")
	remove_test_files(SAVE)
	remove_test_files(CORRUPT)
	remove_test_files(RECOVERY)
	remove_test_files(OVERFLOW)
	# 只移除本测试固定文件名前缀下生成的损坏备份。
	var directory = DirAccess.open("res://tests")
	for filename in directory.get_files():
		if filename.begins_with(".game_flow_corrupt.json") and ".corrupt-" in filename or filename.begins_with(".game_flow_recovery.json") and ".corrupt-" in filename:
			directory.remove(filename)
	print("GAME FLOW RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _write_progress_document(path: String, completed: Array, currency: int) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": Progress.VERSION, "completed": completed, "currency": currency}))
	file.close()

func _test_interrupted_save(game: STGGameDefinition) -> void:
	var store = Progress.new()
	store.load_progress(RECOVERY)
	store.complete_location(game.world.locations[0])
	check(store.save(), "中断恢复测试先保存有效初始快照")
	_write_progress_document(RECOVERY + ".tmp", ["coast", "valley"], 180)
	check(DirAccess.rename_absolute(RECOVERY, RECOVERY + ".bak") == OK, "模拟主存档移入备份后发生中断")
	var recovered = Progress.new()
	recovered.load_progress(RECOVERY)
	check(recovered.completed.has("coast") and recovered.completed.has("valley") and recovered.currency == 180, "主存档缺失时恢复完整的最新临时快照")
	check(not recovered.write_blocked and not recovered.issue.is_empty(), "恢复中断快照后允许继续保存并报告恢复信息")
	check(FileAccess.file_exists(RECOVERY + ".bak") and not FileAccess.file_exists(RECOVERY), "恢复读取不会删除备份或隐式覆盖文件")
	check(recovered.save(), "恢复后的快照可正常重新保存")
	var reloaded = Progress.new()
	reloaded.load_progress(RECOVERY)
	check(reloaded.currency == 180 and reloaded.completed.has("valley"), "恢复后重启仍保留最新通关进度")
	DirAccess.remove_absolute(RECOVERY)
	var file = FileAccess.open(RECOVERY + ".tmp", FileAccess.WRITE)
	file.store_string("{incomplete-write")
	file.close()
	recovered.load_progress(RECOVERY)
	check(recovered.currency == 100 and recovered.completed.has("coast") and not recovered.completed.has("valley"), "临时文件损坏时恢复上一份有效备份")
	check(not recovered.write_blocked, "有效备份可恢复主存档缺失的写入中断")
	file = FileAccess.open(RECOVERY, FileAccess.WRITE)
	file.store_string("{corrupt-primary")
	file.close()
	recovered.load_progress(RECOVERY)
	check(recovered.currency == 100 and recovered.write_blocked, "主存档损坏时从有效备份读取，但阻止自动覆盖原文件")
	check(not recovered.save() and FileAccess.get_file_as_string(RECOVERY) == "{corrupt-primary", "恢复备份后自动保存仍保留损坏主存档")
	check(recovered.archive_corrupt_and_save(), "明确重建时归档主存档及恢复文件后保存")
	reloaded.load_progress(RECOVERY)
	check(reloaded.currency == 100 and not reloaded.write_blocked, "明确重建后的恢复进度可再次读取")
	remove_test_files(RECOVERY)
	file = FileAccess.open(RECOVERY + ".tmp", FileAccess.WRITE)
	file.store_string("{broken-recovery")
	file.close()
	recovered.load_progress(RECOVERY)
	check(recovered.write_blocked and not recovered.save(), "仅有损坏恢复文件时禁止当作全新进度自动写入")

func _test_currency_bounds(game: STGGameDefinition) -> void:
	var store = Progress.new()
	store.load_progress(OVERFLOW)
	store.currency = Progress.MAX_CURRENCY - 50
	var location: STGWorldLocation = game.world.locations[0].duplicate(true)
	check(store.complete_location(location) == 50 and store.currency == Progress.MAX_CURRENCY, "奖励只按货币上限剩余空间实际到账")
	check(store.complete_location(location) == 0, "达到货币上限仍记录通关，不重复发奖")
	check(store.save(), "达到上限的合法进度可保存")
	var reloaded = Progress.new()
	reloaded.load_progress(OVERFLOW)
	check(reloaded.currency == Progress.MAX_CURRENCY and not reloaded.write_blocked, "程序不会把自己写出的上限存档判为损坏")
	location.id = "huge_reward"
	location.reward = 9223372036854775807
	check(store.complete_location(location) == 0 and store.currency == Progress.MAX_CURRENCY, "极大奖励也不会造成整数加法溢出")
	store.currency += 1
	check(not store.save(), "非法外部进度修改不会写出无法读取的存档")
	reloaded.load_progress(OVERFLOW)
	check(reloaded.currency == Progress.MAX_CURRENCY, "拒绝非法进度保存时保持已有有效快照")


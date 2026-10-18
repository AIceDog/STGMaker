extends SceneTree
## 首版真实 FlyTiger 内容贯通测试：自动瞄准只传玩家移动与射击，不直接扣敌人生命。
const Session = preload("res://stg/runtime/game/session.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")
const GAME_PATH = "res://game/content/first_game.tres"
const SAVE = "res://tests/.first_game_progress.json"
var checks = 0
var failures = 0
var previous_positions: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE + suffix):
			DirAccess.remove_absolute(SAVE + suffix)

func aim_input(session: STGGameSession) -> Vector2:
	var world = session.simulation
	var target = null
	var nearest = INF
	for entity in world.entities:
		if entity.is_resolved() or entity.simulation == null or not entity.simulation.boss_visible:
			continue
		var priority = world.player.distance_squared_to(entity.location)
		if priority < nearest:
			nearest = priority
			target = entity
	if target == null:
		return Vector2.ZERO
	var velocity = Vector2.ZERO
	if previous_positions.has(target.instance_id):
		velocity = (target.location - previous_positions[target.instance_id]) / STGSimulation.STEP
	previous_positions[target.instance_id] = target.location
	# 估计水平弹飞到目标时的纵向位置；移动仍受正式主角速度与战斗边界限制。
	var flight_time = maxf(0, target.location.x - world.player.x) / session.definition.player.shot_speed
	var desired = Vector2(clampf(target.location.x - 220, -440, -140), clampf(target.location.y + velocity.y * minf(flight_time, 0.35), -245, 245))
	return (desired - world.player).limit_length(session.definition.player.move_speed * STGSimulation.STEP) / (session.definition.player.move_speed * STGSimulation.STEP)

func play_location(session: STGGameSession, id: String, limit_seconds: float) -> void:
	previous_positions.clear()
	check(session.enter_location(id), "真实地点可开始战斗：" + id)
	if session.state != "battle":
		return
	for _tick in ceili(limit_seconds / STGSimulation.STEP):
		if session.state != "battle":
			break
		session.advance(STGSimulation.STEP, aim_input(session), true)
	var positions: Array = []
	for entity in session.simulation.entities:
		positions.append({"id": entity.definition.enemy_id, "position": entity.location, "hp": entity.hp, "resolved": entity.resolved_reason})
	check(session.state == "result" and session.result.victory, "真实地点射击通关：%s / state=%s / time=%.2f / health=%d / issue=%s / entities=%s" % [id, session.state, session.elapsed, session.health, session.issue, positions])
	check(session.simulation.resolved_entities.values().has("died"), "真实地点至少记录一个射击造成的死亡：" + id)
	print("FIRST GAME LOCATION: %s / %.2fs / health=%d / resolved=%s" % [id, session.elapsed, session.health, session.simulation.resolved_entities])

func run() -> void:
	cleanup()
	var source = ResourceLoader.load(GAME_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as STGGameDefinition
	check(source != null and source.validate().is_empty(), "正式游戏定义合法")
	if source == null:
		quit(1)
		return
	var game_hash = FileAccess.get_sha256(GAME_PATH)
	var library_path = source.library.resource_path
	var library_hash = FileAccess.get_sha256(library_path)
	var game: STGGameDefinition = Copy.copy(source)
	game.player.max_health = 99 # 自动化聚焦实际射击与关卡推进，原五格生命资源不修改。
	var session = Session.new()
	root.add_child(session)
	session.configure(game, SAVE)
	check(not session.enter_location("gate"), "山门在巡航通关前锁定")
	play_location(session, "border", 180)
	check(session.progress.completed.has("border") and session.progress.is_unlocked(game.world.find("gate")), "真实巡航通关解锁山门")
	if session.state == "result" and session.result.victory:
		session.return_to_map()
		play_location(session, "gate", 180)
	check(session.progress.completed.has("gate") and session.progress.currency == 400, "两处实际通关记录首通奖励 100 + 300")
	session.free()
	session = Session.new()
	root.add_child(session)
	session.configure(game, SAVE)
	check(session.progress.completed.has("border") and session.progress.completed.has("gate") and session.progress.currency == 400, "完整真实内容的奖励与解锁在重启后保留")
	check(FileAccess.get_sha256(GAME_PATH) == game_hash and FileAccess.get_sha256(library_path) == library_hash and source.player.max_health == 5, "自动战斗不修改正式游戏、共享库或主角定义")
	session.free()
	cleanup()
	print("FIRST GAME CONTENT RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

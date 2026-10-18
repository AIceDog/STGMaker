@tool
class_name STGGameSession
extends Node
## 游戏流程的可测试入口。UI 只传入玩家输入，不另写敌人、子弹或关卡规则。
signal state_changed
signal message_changed
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Progress = preload("res://stg/runtime/game/progress_store.gd")
const INVULNERABILITY_SECONDS = 1.0
var player_modules: Dictionary = {}
var player_contexts: Dictionary = {}
var definition: STGGameDefinition
var progress = Progress.new()
var state: String = "menu"
var location_id: String = ""
var simulation: STGLevelSimulation
var simulation_parent: Node
var health: int = 0
var invulnerability: float = 0
var elapsed: float = 0
var result: Dictionary = {}
var issue: String = ""

func configure(game: STGGameDefinition, save_path: String = "user://stg_progress_v1.json") -> void:
	_release_battle()
	definition = game
	issue = "缺少游戏定义" if game == null else "；".join(game.validate())
	progress.load_progress(save_path)
	state = "menu" if issue.is_empty() else "error"
	result.clear()
	state_changed.emit()

func show_map() -> void:
	if definition == null or not issue.is_empty():
		return
	_release_battle()
	state = "map"
	state_changed.emit()

func show_menu() -> void:
	_release_battle()
	state = "menu" if issue.is_empty() else "error"
	state_changed.emit()

func enter_location(identifier: String) -> bool:
	if definition == null or not issue.is_empty():
		return false
	var location = definition.world.find(identifier)
	if location == null or not progress.is_unlocked(location):
		return false
	_release_battle()
	location_id = identifier
	health = definition.player.max_health
	invulnerability = 0
	elapsed = 0
	result.clear()
	simulation = STGLevelSimulation.new()
	(simulation_parent if simulation_parent != null else self).add_child(simulation)
	simulation.reset(definition.library, "levels", location.level_id)
	if not simulation.issue.is_empty():
		issue = simulation.issue
		_release_battle()
		state = "error"
		state_changed.emit()
		return false
	simulation.editor_markers = false
	simulation.player_radius = definition.player.hit_radius
	simulation.player_shots.fire_interval = definition.player.fire_interval
	simulation.player_shots.shot_speed = definition.player.shot_speed
	simulation.player_shots.shot_damage = definition.player.shot_damage
	simulation.player_shots.shot_lifetime = definition.player.shot_lifetime
	simulation.muted = false
	simulation.set_audio_paused(false)
	simulation.player_hit.connect(receive_hit)
	simulation.finished.connect(_win)
	simulation.audio_requested.connect(_play_sound)
	state = "battle"
	_start_player_modules()
	if not issue.is_empty():
		_release_battle()
		state = "error"
		state_changed.emit()
		return false
	state_changed.emit()
	return true

## dt 由固定步长游戏循环传入；暂停时完全不推进战斗、无敌时间与关卡计时。
func advance(dt: float, movement: Vector2 = Vector2.ZERO, firing: bool = false, using_ability: bool = false) -> void:
	if state != "battle" or simulation == null or dt <= 0:
		return
	elapsed += dt
	invulnerability = maxf(0, invulnerability - dt)
	for slot in ["controller", "weapon", "ability"]:
		var context: STGPlayerContext = player_contexts[slot]
		context.movement_input = movement
		context.firing = firing
		context.using_ability = using_ability
		player_modules[slot].tick(dt)
		if player_modules[slot].failed: simulation.issue = "主角能力执行失败：" + slot
	if not simulation.issue.is_empty():
		issue = simulation.issue
	simulation.step(dt)
	if not simulation.issue.is_empty():
		issue = simulation.issue
		state = "error"
		simulation.set_audio_paused(true)
		_stop_player_modules("failed")
		state_changed.emit()

func receive_hit(damage: float) -> void:
	if state != "battle" or damage <= 0 or invulnerability > 0:
		return
	health = maxi(0, health - 1)
	invulnerability = INVULNERABILITY_SECONDS
	if health == 0:
		_finish(false)
	message_changed.emit()

func toggle_pause() -> void:
	if state not in ["battle", "paused"]:
		return
	state = "paused" if state == "battle" else "battle"
	simulation.set_audio_paused(state == "paused")
	_pause_effects(state == "paused")
	simulation.reset_player_sample()
	state_changed.emit()

func retry() -> bool:
	return enter_location(location_id)

func return_to_map() -> void:
	show_map()

func _win() -> void:
	if state == "battle":
		_finish(true)

func _finish(victory: bool) -> void:
	var reward = 0
	if victory:
		reward = progress.complete_location(definition.world.find(location_id))
		progress.save()
	result = {"victory": victory, "location_id": location_id, "elapsed": elapsed, "reward": reward}
	state = "result"
	_stop_player_modules("completed" if victory else "stopped")
	simulation.set_audio_paused(true)
	_pause_effects(true)
	state_changed.emit()

func _play_sound(stream: AudioStream, _at: Vector2) -> void:
	if stream == null or simulation == null:
		return
	var audio = AudioStreamPlayer.new()
	audio.stream = stream
	simulation.add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()

func _pause_effects(paused: bool) -> void:
	for child in simulation.get_children():
		if child is AudioStreamPlayer:
			child.stream_paused = paused

func _release_battle() -> void:
	_stop_player_modules("removed")
	if is_instance_valid(simulation):
		simulation.clear()
		simulation.free()
	simulation = null

func _exit_tree() -> void:
	_release_battle()

func _start_player_modules() -> void:
	for slot in ["controller", "weapon", "ability"]:
		var context = STGPlayerContext.new(simulation)
		context.slot = slot
		context._player_definition = definition.player
		context._game = self
		var binding: STGExtensionBinding = definition.player.get(slot)
		var module = preload("res://stg/runtime/extensions/extension_session.gd").new()
		player_contexts[slot] = context
		player_modules[slot] = module
		var started = module.begin(binding.definition if binding != null else null, binding.parameters if binding != null else {}, "player", context, preload("res://stg/runtime/modules/player.gd").new() if binding == null else null)
		if not started or module.failed:
			issue = module.issue if not module.issue.is_empty() else "主角能力启动失败：" + slot
			return

func _stop_player_modules(reason: String) -> void:
	for module in player_modules.values(): module.cancel(reason)
	player_modules.clear()
	player_contexts.clear()

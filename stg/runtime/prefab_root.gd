@tool
extends Node2D
## 可实例化场景的游戏接入入口；只转换坐标、驱动固定时钟和转发信号。
## 攻击、敌人和关卡规则仍由各自的 Simulation 执行，编辑器内不自动开战。

const LEVEL_KINDS = ["levels", "waves", "obstacles"]

signal finished
signal failed(message: String)
signal player_hit(damage: float)
signal boss_action_event(node_id: String, event: String)
signal entity_resolved(instance_id: int, reason: String)

@export var library: STGProject
@export_enum("bullets", "barrages", "behaviors", "bosses", "waves", "levels", "obstacles") var kind: String = "barrages"
@export var resource_id: String = ""
@export var autoplay: bool = true

var simulation: Node2D
var accumulator: float = 0
var running: bool = false


func _ready() -> void: # Godot 回调：实例进入场景树后，根据 autoplay 启动。
	if not Engine.is_editor_hint() and autoplay:
		play()


func play() -> void:
	## 从头创建运行实例；接收编辑 / 构建入口准备好的资源，失败通过 failed 信号报告。
	stop()
	if library == null:
		failed.emit("缺少预制体资源库")
		return

	simulation = STGLevelSimulation.new() if kind in LEVEL_KINDS else STGSimulation.new()
	add_child(simulation)
	simulation.reset(library, kind, resource_id)

	if kind in ["bullets", "barrages", "behaviors"]:
		_align_attack_origin()
	_connect_game_signals()
	running = simulation.issue.is_empty()
	if not running:
		failed.emit(simulation.issue)


func _align_attack_origin() -> void:
	# 编辑器使用右侧 Boss 占位坐标；攻击预制体则以自身局部原点为发射原点。
	# 尾迹保存的是历史战斗坐标，因此必须通过 rebase 一并平移所有已采样段。
	for actor in simulation.actors:
		if actor is STGBulletTrailActor:
			actor.rebase(simulation.boss)
		else:
			actor.position -= simulation.boss
			actor.previous = actor.position
	for behavior in simulation.behaviors:
		behavior.origin = Vector2.ZERO
	for barrage in simulation.barrages:
		barrage.origin = Vector2.ZERO
	simulation.player -= simulation.boss
	simulation.previous_player = simulation.player
	simulation.boss = Vector2.ZERO


func _connect_game_signals() -> void:
	# 游戏实例启用声音并关闭编辑辅助标记。不同运行器的公共事件在此统一转发。
	simulation.muted = false
	simulation.editor_markers = false
	simulation.audio_requested.connect(_play_sound)
	simulation.player_hit.connect(player_hit.emit)
	if simulation is STGSimulation:
		simulation.boss_action_event.connect(boss_action_event.emit)
	else:
		simulation.entity_resolved.connect(entity_resolved.emit)
		simulation.set_audio_paused(false)


func set_player(world_position: Vector2, radius: float = 4) -> void:
	## 游戏每帧传入玩家全局位置与判定半径；模拟器使用预制体局部设计坐标。
	if simulation != null:
		simulation.player = to_local(world_position) # Godot 内置：世界坐标转局部坐标。
		simulation.player_radius = radius / maxf(0.001, absf(global_scale.x))


func damage_boss(percent: float) -> void:
	## percent 是最大生命值百分比；无敌与血量阶段规则由战斗运行器决定。
	if simulation is STGSimulation:
		simulation.damage_boss(percent)


func damage_entity(instance_id: int, percent: float) -> void:
	## 关卡内按实例 ID 扣除最大生命值百分比，不修改共享敌人定义。
	if simulation is STGLevelSimulation:
		simulation.damage_entity(instance_id, percent)


func shoot_player() -> void:
	## 调用关卡占位测试武器；正式游戏可以使用自己的射击系统。
	if simulation is STGLevelSimulation:
		simulation.shoot_player()


func set_boss(world_position: Vector2) -> void:
	## 调试接入入口：把外部世界位置转换为模拟器局部位置。
	if simulation != null:
		simulation.boss = to_local(world_position)


func stop() -> void:
	## 立即释放本场景的运行实例，重置时钟；制作资源仍保留在 library 中。
	running = false
	accumulator = 0
	if is_instance_valid(simulation):
		simulation.free() # Godot 内置：同步释放，避免重播时累积旧节点。
	simulation = null


func _physics_process(delta: float) -> void: # Godot 回调：delta 是本物理帧经过的秒数。
	if not running or Engine.is_editor_hint():
		return
	# 帧间时间先累积，再按统一的 1/120 秒步长推进；一帧可能执行多个逻辑步。
	accumulator += delta
	while accumulator >= STGSimulation.STEP:
		simulation.step()
		accumulator -= STGSimulation.STEP
		if simulation.completed or not simulation.issue.is_empty():
			running = false
			if simulation.issue.is_empty():
				finished.emit()
			else:
				failed.emit(simulation.issue)
			break


func _play_sound(stream: AudioStream, at: Vector2) -> void:
	# at 与本预制体使用同一局部坐标；每个短音效播放结束后自行释放节点。
	var audio = AudioStreamPlayer2D.new()
	audio.stream = stream
	audio.position = at
	add_child(audio)
	audio.finished.connect(audio.queue_free) # Godot 信号：完成播放后延迟回收。
	audio.play()


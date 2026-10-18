@tool
extends Node2D
## 表现接口 configure/enter/tick/reset。逻辑时钟驱动动画，不让动画另开一套前后摇计时。
const Scenes = preload("res://stg/definitions/scene_contract.gd")
var visual: Node2D
var animation_player: AnimationPlayer
var playback_rate: float = 1

## 自定义初始化：载入表现场景，改用手动动画更新，使动画与战斗固定步长共用时钟。
func configure(scene: PackedScene) -> void:
	if scene == null:
		return
	var instance = scene.instantiate() # Godot 内置：实例化用户制作的 Boss 表现场景。
	if not instance is Node2D:
		instance.free()
		return
	visual = instance
	add_child(visual)
	animation_player = Scenes.find_player(visual)
	if animation_player != null:
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animation_player.stop()

## 自定义切换：seconds 是逻辑时段秒数；前后摇可调整播放速率来对齐该长度。
func enter(name: String, seconds: float, align_length: bool) -> void:
	if animation_player == null:
		return
	animation_player.stop()
	if name.is_empty() or not animation_player.has_animation(name):
		return
	var clip = animation_player.get_animation(name)
	playback_rate = clip.length / seconds if align_length and seconds > 0 else 1.0
	animation_player.play(name)
	animation_player.advance(0) # Godot 内置：立即应用动画起始帧。
	if align_length and seconds <= 0:
		animation_player.advance(clip.length)

## 自定义更新：Godot AnimationPlayer.advance 手动推进，不能同时开启自动播放时钟。
func tick(dt: float) -> void:
	if animation_player != null:
		animation_player.advance(dt * playback_rate)

## 自定义还原：应用可选 RESET 动画初帧，再停播，避免上个动作遗留表现状态。
func reset() -> void:
	if animation_player == null:
		return
	if animation_player.has_animation("RESET"):
		animation_player.play("RESET")
		animation_player.advance(0)
	animation_player.stop()

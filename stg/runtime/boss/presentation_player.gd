@tool
extends Node2D
## 动画仅手动采样；逻辑时钟决定循环次数、末帧与速度，不改共享 Animation。
const Scenes=preload("res://stg/definitions/scene_contract.gd")
const Timing=preload("res://stg/definitions/behavior_timing.gd")
var visual:Node2D
var animation_player:AnimationPlayer
var playback_rate:float=1.0
var cycles:int=0
var _length:float=0
var _duration:float=0
var _elapsed:float=0
var _hold:bool=false
var _current:String=""
func configure(scene:PackedScene) -> void:
    # 召唤入场结束会重新配置同一敌人，旧表现场景必须先释放。
    if is_instance_valid(visual):visual.free()
    visual=null;animation_player=null;_current="";_elapsed=0;_length=0;_duration=0
    playback_rate=1;cycles=0
    if scene==null:return
    var instance=scene.instantiate()
    if not instance is Node2D:instance.free();return
    visual=instance;add_child(visual)
    animation_player=Scenes.find_player(visual)
    if animation_player!=null:
        animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
        animation_player.stop()
        for library_name in animation_player.get_animation_library_list():
            var library=animation_player.get_animation_library(library_name).duplicate(true)
            for clip_name in library.get_animation_list():
                var clip=library.get_animation(clip_name).duplicate(true)
                clip.loop_mode=Animation.LOOP_NONE
                library.remove_animation(clip_name);library.add_animation(clip_name,clip)
            animation_player.remove_animation_library(library_name)
            animation_player.add_animation_library(library_name,library)
func clip_length(name:String) -> float:
    return animation_player.get_animation(name).length if animation_player!=null and animation_player.has_animation(name) else 0.0
func enter_stage(name:String,duration:float,stage:String,mode:String="fit_cycles",manual:int=0) -> Dictionary:
    _current=name;_length=clip_length(name);_duration=duration;_elapsed=0
    var plan=Timing.animation_plan(_length,duration,stage,mode,manual)
    playback_rate=plan.rate;cycles=plan.cycles;_hold=plan.hold
    if animation_player==null:return plan
    animation_player.stop(true)
    if name.is_empty() or _length<=0 or duration<=0:return plan
    animation_player.play(name)
    animation_player.seek(0,true)
    return plan
func tick(dt:float) -> void:
    if animation_player==null or _current.is_empty() or _length<=0 or _duration<=0:return
    _elapsed=minf(_duration,_elapsed+dt)
    var position:float
    if _hold:position=minf(_length,_elapsed*playback_rate)
    elif _elapsed+0.000001>=_duration:position=_length
    else:position=fposmod(_elapsed*playback_rate,_length)
    # keep_state 避免阶段衔接中插入 RESET；循环片段的精确末帧按非循环副本取样。
    animation_player.seek(position,true)
func pause_pose() -> void:
    _current=""
    if animation_player!=null:animation_player.stop(true)
func reset() -> void:
    _current=""
    if animation_player==null:return
    if animation_player.has_animation("RESET"):
        animation_player.play("RESET");animation_player.seek(0,true)
    animation_player.stop(true)

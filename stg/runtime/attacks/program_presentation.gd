@tool
extends Node2D
## 声音/场景表现的持久实例。逻辑寿命与暂停/倍速由同一个模拟时钟控制。
var alive:bool=true
var looped:bool=false
var owner_id:int=0
var follow
var followed:bool=false
var world
var stream:AudioStream
var audio:AudioStreamPlayer
var visual
var remaining:float=2
var clock_playing:bool=true
var clock_speed:float=1
var speed_scale:float=1
var volume_db:float=0
func configure(simulation,at:Vector2,sound:AudioStream=null,scene:PackedScene=null,seconds:float=2,loop:bool=false) -> void:
 world=simulation;position=at;stream=sound;looped=loop;remaining=seconds
 if stream!=null:
  remaining=stream.get_length() if stream.get_length()>0 else INF
  if is_inside_tree():
   # 本地副本关闭素材自己的循环，由句柄控制，禁止修改共享资源。
   var local_stream=stream.duplicate()
   if local_stream is AudioStreamWAV:local_stream.loop_mode=AudioStreamWAV.LOOP_DISABLED
   elif local_stream is AudioStreamOggVorbis or local_stream is AudioStreamMP3:local_stream.loop=false
   audio=AudioStreamPlayer.new();audio.stream=local_stream;audio.volume_db=volume_db;audio.pitch_scale=speed_scale;add_child(audio);audio.play()
   audio.finished.connect(func():
    if looped and alive:audio.play()
    elif alive:stop())
 if scene!=null:
  visual=load("res://stg/runtime/attacks/projectile_presentation.gd").new();add_child(visual);visual.configure(scene,"")
func set_clock(playing:bool,speed:float) -> void:
 clock_playing=playing;clock_speed=speed
 if is_instance_valid(audio):audio.stream_paused=not playing or world.muted or speed<=0;audio.pitch_scale=speed*speed_scale if speed>0 else speed_scale
func tick(dt:float) -> void:
 if not alive:return
 if followed and not is_instance_valid(follow):stop();return
 if is_instance_valid(follow):
  if not follow.alive:stop();return
  position=follow.program_position() if follow.has_method("program_position") else follow.position
 if visual!=null:visual.tick(dt)
 if not looped:
  remaining-=dt*speed_scale
  if remaining<=0:stop()
func is_finished() -> bool:return not alive
func stop() -> void:
 alive=false
 if is_instance_valid(audio):audio.stop()
func _exit_tree() -> void:stop()

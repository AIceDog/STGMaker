@tool
extends Window
## 表现试听复用正式动画与音频服务，只推进一个固定模拟时钟。
const F=preload("res://addons/stg_maker/ui/fields.gd")
const Presentation=preload("res://stg/runtime/boss/presentation_player.gd")
const Sound=preload("res://stg/runtime/attacks/program_presentation.gd")
var parameters:Dictionary
var presentation
var voice
var status:Label
var phase_index:int=0
var elapsed:float=0
var accumulator:float=0
var playing:bool=true
var rate:float=1
var audio_world={"muted":false}
var viewport:SubViewport
const STAGES=["windup","active","recovery"]
func open_for(host,p:Dictionary,scene:PackedScene) -> void:
    parameters=p.duplicate(true);theme=host.theme;title="三段动画预览与试听"
    size=Vector2i(720,520);min_size=Vector2i(600,400)
    var body=VBoxContainer.new();body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(body)
    var tools=HFlowContainer.new();body.add_child(tools)
    F.button(tools,"重新播放",restart)
    F.button(tools,"播放 / 暂停",func():playing=not playing;_clock())
    F.toggle(tools,"静音",false,func(value):audio_world.muted=value;_clock())
    F.select(tools,"预览倍速","1",["0.5","1","2"],["0.5×","1×","2×"],func(value):rate=float(value);_clock())
    status=F.note(body,"")
    var container=SubViewportContainer.new();container.stretch=true;container.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(container)
    viewport=SubViewport.new();viewport.size=Vector2i(720,380);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
    presentation=Presentation.new();viewport.add_child(presentation);presentation.position=Vector2(360,190);presentation.configure(scene)
    container.resized.connect(func():presentation.position=container.size/2)
    if scene==null:F.note(body,"当前子流程未关联敌人表现场景；可试听声音，动画需在敌人中预览。")
    close_requested.connect(func():_stop_voice();queue_free())
    restart();popup_centered_clamped(size,.85)
func restart() -> void:
    _stop_voice();phase_index=0;elapsed=0;accumulator=0;playing=true;_enter()
func _duration() -> float:return float(parameters.execution_duration if STAGES[phase_index]=="active" else parameters[STAGES[phase_index]])
func _enter() -> void:
    _stop_voice();elapsed=0
    while phase_index<3 and _duration()<=0:phase_index+=1
    if phase_index>=3:playing=false;status.text="三段表现结束";presentation.reset();return
    var stage=STAGES[phase_index]
    var plan=presentation.enter_stage(str(parameters[stage+"_animation"]),_duration(),stage,str(parameters.active_animation_mode),int(parameters.active_cycles))
    status.text="%s · %.3f 秒 · %d 次 · 动画与音频 %.4f×"%[{"windup":"前摇","active":"执行中","recovery":"后摇"}[stage],_duration(),plan.cycles,plan.rate]
    var stream=parameters.get(stage+"_sound")
    if stream!=null:
        voice=Sound.new();add_child(voice);voice.speed_scale=plan.rate;voice.volume_db=float(parameters[stage+"_volume_db"])
        voice.configure(audio_world,Vector2.ZERO,stream,null,_duration(),bool(parameters[stage+"_sound_loop"]));_clock()
func _clock() -> void:
    if is_instance_valid(voice):voice.set_clock(playing,rate)
func _stop_voice() -> void:
    if is_instance_valid(voice):voice.stop();voice.free()
    voice=null
func _process(delta:float) -> void:
    if not playing or phase_index>=3:return
    accumulator+=minf(delta,.1)*rate
    while accumulator+0.000001>=STGSimulation.STEP and playing:
        accumulator-=STGSimulation.STEP
        advance(STGSimulation.STEP)
func advance(dt:float) -> void:
    var remaining=dt
    for transition in 3:
        if phase_index>=3:return
        var consumed=minf(remaining,maxf(0,_duration()-elapsed))
        elapsed+=consumed;remaining-=consumed;presentation.tick(consumed)
        if is_instance_valid(voice):voice.tick(consumed)
        if elapsed+0.000001<_duration():return
        phase_index+=1;_enter()
func _exit_tree() -> void:_stop_voice()

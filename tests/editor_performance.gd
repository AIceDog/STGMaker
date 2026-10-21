extends SceneTree
## 默认无诊断输出；受限进程下检查角度编辑、历史隔离、内存和空闲刷新。
const Session = preload("res://addons/stg_maker/ui/session.gd")
const Trace = preload("res://addons/stg_maker/ui/performance_trace.gd")
var checks = 0
var failures = 0
var studio
var draws = 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
 checks += 1
 if not ok: failures += 1; push_error(message)
func frames(count = 3):
 for i in count: await process_frame
func change(angle: float):
 studio.edit_path(["program_parameters"], "angle", angle)
 await process_frame
func run():
 root.size = Vector2i(1440,900)
 studio = load("res://addons/stg_maker/studio.tscn").instantiate()
 studio.restore_last_project = false
 studio.settings_path = "user://editor_performance_isolated.cfg"
 studio.show_trajectories = false
 root.add_child(studio)
 await frames()
 studio.session.project=preload("res://tests/unified14_fixture.gd").project();studio.collection="barrages";studio.selected_id="straight";studio.refresh(true);await frames()
 studio.playing = false
 await benchmark(0,50.0)
 await benchmark(1000,150.0)
 await history_and_idle()
 studio.session.recoverable_changes = false
 studio.queue_free()
 await frames()
 print("EDITOR PERFORMANCE RESULT: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
func benchmark(extra: int, limit: float):
 if extra:
  var project: STGProject = studio.session.project.duplicate(false)
  project.barrages = studio.session.project.barrages.duplicate()
  for i in extra:
   var skill = studio.session.Copy.copy(project.find("barrages","straight"))
   skill.id = "performance_%d"%i
   project.barrages.append(skill)
  studio.session.project = project
 for i in 8: await change(180.0 if i%2 else 90.0)
 var form = studio.inspector.get_child(0)
 var rebuilds = studio.get_meta("library_rebuild_count")
 var immutable = studio.session.project
 var unchanged = immutable.barrages[-1]
 var previous_angle = immutable.find("barrages","straight").program_parameters.angle
 var values = []
 var submit = []
 var memory_warm = 0
 for i in 100:
  var start = Time.get_ticks_usec()
  studio.edit_path(["program_parameters"],"angle",90.0 if i%2 else 180.0)
  submit.append((Time.get_ticks_usec()-start)/1000.0)
  await process_frame
  values.append((Time.get_ticks_usec()-start)/1000.0)
  if i == 49: memory_warm = OS.get_static_memory_usage()
 values.sort();submit.sort()
 var record = {"extra_resources":extra,"samples":100,"submit_p95_ms":submit[94],"total_p95_ms":values[94],"memory_after50":memory_warm,"memory_after100":OS.get_static_memory_usage(),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
 print("PERFORMANCE_MEASUREMENT ",JSON.stringify(record))
 check(values[94] <= limit,"参数提交与刷新 P95 达标：%s"%record)
 check(abs(OS.get_static_memory_usage()-memory_warm) < 2*1024*1024,"撤销栈淘汰后内存趋稳")
 check(studio.session.undo_stack.size()==40,"最多保留40次撤销")
 check(studio.session.project.barrages[-1]==unchanged,"未编辑资产保持共享")
 check(immutable.find("barrages","straight").program_parameters.angle==previous_angle,"历史快照未被后续数值修改污染")
 check(studio.inspector.get_child(0)==form,"连续数值编辑保留静态表单实例")
 check(studio.get_meta("library_rebuild_count")==rebuilds,"数值编辑不重建资源列表")
func history_and_idle():
 for angle in [180.0,90.0,0.0,-90.0,-180.0,360.0]:
  await change(angle)
  check(studio.current().program_parameters.angle==angle and studio.canvas.world.issue.is_empty(),"暂停、轨迹关闭时角度有效：%s"%angle)
 var form = studio.inspector.get_child(0)
 studio.undo_edit();await frames(1)
 check(studio.current().program_parameters.angle==-180 and studio.inspector.get_child(0)==form,"撤销角度并复用表单")
 studio.redo_edit();await frames(1)
 check(studio.current().program_parameters.angle==360,"重做角度")
 var session = Session.new();session.create();session.project=preload("res://tests/unified14_fixture.gd").project()
 var old = session.project
 var id = "straight"
 for angle in [80.0,70.0,60.0]:
  session.edit_asset("barrages",id,func(next):next.find("barrages","straight").program_parameters.angle=angle,{"structure":false},"same_number_gesture")
 check(session.undo_stack.size()==1,"连续数值手势合并一次撤销")
 session.undo();check(session.project==old,"合并手势可完整撤销")
 session.redo();check(session.project.find("barrages","straight").program_parameters.angle==60,"合并手势可重做")
 var saved = "user://performance_angle_%d/library.tres"%Time.get_ticks_usec()
 check(session.save(saved).is_empty() and session.open(saved).is_empty() and session.project.find("barrages","straight").program_parameters.angle==60,"角度保存重开保持一致")
 studio.canvas.draw.connect(func():draws+=1)
 await frames(4)
 draws=0
 var rebuilds = studio.get_meta("library_rebuild_count")
 var nodes = studio.inspector.find_children("*","Control",true,false).size()
 await frames(25)
 check(draws==0,"暂停且关闭轨迹时不持续重绘画布：%s"%draws)
 check(studio.get_meta("library_rebuild_count")==rebuilds and studio.inspector.find_children("*","Control",true,false).size()==nodes,"空闲不重建列表或控件")
 # 真实 SpinBox 信号链路与连续手势，不仅调用配置 API。
 var angle_control
 for node in studio.inspector.find_children("*", "SpinBox", true, false):
  if node.get_meta("program_parameter", "") == "angle":angle_control=node;break
 check(angle_control != null,"中心方向静态控件已绑定")
 if angle_control != null:
  var before = studio.session.undo_stack.size()
  angle_control.get_line_edit().grab_focus()
  for value in [180.0,90.0,0.0,-90.0,-180.0,360.0]:
   angle_control.value=value
   await process_frame
   check(studio.current().program_parameters.angle==value,"真实数值信号不重复提交并同步角度")
  check(studio.session.undo_stack.size()<=mini(40,before+1),"真实数值控件的连续调整合并")
  angle_control.get_line_edit().release_focus()
 # 未使用的坏资源不干扰局部预览；全量校验仍发现问题。
 var bad = studio.session.Copy.copy(studio.session.project.find("barrages","straight"))
 bad.id="unrelated_invalid";bad.attack_preset.reference_id="missing"
 studio.session.project.barrages.append(bad)
 await change(90)
 check(studio.canvas.world.issue.is_empty() and not studio.session.project.validate().is_empty(),"局部预览和全量检查职责分离")
 studio.accumulator=0
 studio.canvas._budget_frame=-1
 var previous_time = studio.canvas.world.time
 studio.playing=true;studio._advance_preview(0.1)
 var advanced = studio.canvas.world.time-previous_time
 check(advanced<=8*STGSimulation.STEP+0.000001 and is_equal_approx(studio.accumulator,0.1-advanced),"每帧最多八步，未处理时间保留，不跳过逻辑步骤")
 studio.playing=true;studio._advance_preview(0.3)
 check(not studio.playing and studio.preview_notice.contains("0.25") and not studio.message_dialog.visible,"超额积压暂停且状态栏提示不阻塞编辑器")
 studio.message_dialog.hide()

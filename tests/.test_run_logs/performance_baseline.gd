extends SceneTree
var host
func _initialize(): run.call_deferred()
func run():
 host=load("res://addons/stg_maker/studio.tscn").instantiate()
 host.restore_last_project=false
 host.settings_path="user://performance_isolated.cfg"
 host.show_trajectories=false
 root.add_child(host)
 for i in 3: await process_frame
 host.playing=false
 print("BASE_START nodes=",root.get_child_count()," resources=",Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)," memory=",OS.get_static_memory_usage())
 for count in [0,1000]:
  if count:
   for i in count:
    var item=host.session.project.barrages[0].duplicate(true)
    item.id="synthetic_%d"%i
    host.session.project.barrages.append(item)
  var times=[]
  for i in 100:
   var before=Time.get_ticks_usec()
   host.edit_path(["fire_pattern"],"angle",90.0 if i%2 else 180.0)
   var submitted=Time.get_ticks_usec()
   await process_frame
   times.append((Time.get_ticks_usec()-before)/1000.0)
   print("EDIT count=",count," i=",i," submit_ms=",(submitted-before)/1000.0," total_ms=",times[-1]," resources=",Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)," nodes=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT)," memory=",OS.get_static_memory_usage())
  times.sort()
  print("P95 count=",count," ms=",times[94])
 host.session.recoverable_changes=false
 host.queue_free()
 await process_frame
 quit()


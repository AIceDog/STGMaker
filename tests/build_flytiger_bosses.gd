extends SceneTree
## 只更新独立 Boss 预设；不会覆盖 working.tres 或既有小怪模板库。
func _initialize() -> void:
	var project = preload("res://addons/stg_maker/authoring/templates/flytiger_boss_library.gd").new().build()
	var issues = project.validate()
	for issue in issues: push_error(issue)
	if not issues.is_empty(): quit(1); return
	var result = ResourceSaver.save(project, "res://presets/flytiger_bosses.tres")
	print("Boss library: %d entities, %d skills, %d bullets; save=%d" % [project.bosses.size(), project.barrages.size(), project.bullets.size(), result])
	quit(result)

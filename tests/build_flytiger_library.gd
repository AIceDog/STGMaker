extends SceneTree
## 生成独立预设；此脚本只在显式运行时写文件，不参与插件启动或用户项目保存。
const Factory = preload("res://addons/stg_maker/authoring/templates/flytiger_enemy_library.gd")

func _initialize() -> void:
	var project = Factory.new().build()
	var issues = project.validate()
	if not issues.is_empty():
		for issue in issues: push_error(issue)
		quit(1)
		return
	var error = ResourceSaver.save(project, "res://presets/flytiger_enemies.tres")
	print("FLYTIGER LIBRARY: %d enemies, %d skills, %d bullets; save=%s" % [project.bosses.size(), project.barrages.size(), project.bullets.size(), error_string(error)])
	quit(0 if error == OK else 1)

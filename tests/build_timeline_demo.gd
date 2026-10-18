extends SceneTree
## 新版示例使用新文件名；旧关卡与敌人库保持原样，重复生成必须显式指定开发参数。
const Factory = preload("res://addons/stg_maker/authoring/templates/level_demo.gd")
const PrefabRoot = preload("res://stg/runtime/prefab_root.gd")

func _initialize() -> void: # Godot 回调
	build.call_deferred()

func build() -> void:
	var path = "res://presets/timeline_demo.tres"
	if FileAccess.file_exists(path) and "--replace-generated" not in OS.get_cmdline_user_args():
		push_error("已存在完整时间轴示例；请先备份，或显式传入 --replace-generated。")
		quit(1)
		return
	var project = Factory.new().build()
	var issues = project.validate()
	if not issues.is_empty():
		push_error("；".join(issues)); quit(1); return
	var result = ResourceSaver.save(project, path) # Godot 内置：保存配置资源。
	if result != OK: push_error(error_string(result)); quit(1); return
	project = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var node = Node2D.new()
	node.set_script(PrefabRoot)
	node.name = "TimelineLevelDemo"
	node.library = project
	node.kind = "levels"
	node.resource_id = project.levels[-1].id
	var scene = PackedScene.new()
	result = scene.pack(node)
	DirAccess.make_dir_recursive_absolute("res://examples/levels")
	if result == OK: result = ResourceSaver.save(scene, "res://examples/levels/timeline_demo.tscn")
	node.free()
	print("TIMELINE BUILD RESULT: %d levels, %d waves; error=%d" % [project.levels.size(), project.waves.size(), result])
	quit(0 if result == OK else 1)

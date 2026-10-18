extends SceneTree
## 开发用示例生成器：追加关卡到敌人库的副本。已有关卡文件默认不覆盖。
const Factory = preload("res://addons/stg_maker/authoring/templates/level_demo.gd")
const PrefabRoot = preload("res://stg/runtime/prefab_root.gd")

func _initialize() -> void: # Godot 回调
	build.call_deferred()

func build() -> void:
	var path = "res://presets/level_demo.tres"
	if FileAccess.file_exists(path) and "--replace-generated" not in OS.get_cmdline_user_args():
		push_error("已有示例关卡，请先备份；需要重新生成时传入 --replace-generated。")
		quit(1)
		return
	var project = Factory.new().build()
	var errors = project.validate()
	if not errors.is_empty(): push_error("；".join(errors)); quit(1); return
	var result = ResourceSaver.save(project, path)
	if result != OK: push_error(error_string(result)); quit(1); return
	project = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var node = Node2D.new()
	node.set_script(PrefabRoot)
	node.name = "LevelDemo"
	node.library = project
	node.kind = "levels"
	node.resource_id = project.levels[-1].id
	var scene = PackedScene.new()
	result = scene.pack(node)
	DirAccess.make_dir_recursive_absolute("res://examples/levels")
	if result == OK: result = ResourceSaver.save(scene, "res://examples/levels/level_demo.tscn")
	node.free()
	print("LEVEL BUILD RESULT: %d levels, %d waves; error=%d" % [project.levels.size(), project.waves.size(), result])
	quit(0 if result == OK else 1)

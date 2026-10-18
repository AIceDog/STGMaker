extends SceneTree
## 开发用生成器：把配置工厂保存成策划资源库，并创建引用同一资源库的 10 个场景。
## 已有文件必须显式传入 --replace-generated，普通测试不会运行这个生成器。
const Factory = preload("res://addons/stg_maker/authoring/templates/enemy_library.gd")
const PrefabRoot = preload("res://stg/runtime/prefab_root.gd")
const LIBRARY_PATH = "res://presets/enemy_library.tres"

func _initialize() -> void: # Godot 回调
	build.call_deferred()

func build() -> void:
	var project = Factory.new().build()
	var errors = project.validate()
	if not errors.is_empty():
		push_error("；".join(errors))
		quit(1)
		return
	var replace = "--replace-generated" in OS.get_cmdline_user_args()
	var output_paths: Array[String] = [LIBRARY_PATH]
	for enemy in project.bosses:
		output_paths.append("res://examples/enemies/" + enemy.id + ".tscn")
	for path in output_paths:
		if FileAccess.file_exists(path) and not replace:
			push_error("已有文件，停止生成：" + path + "。请先备份，确认后使用 --replace-generated。")
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute("res://examples/enemies")
	# 保存后重新加载：明确使用外部 .tres，避免场景各自内嵌十份攻击库。
	var result = ResourceSaver.save(project, LIBRARY_PATH, ResourceSaver.FLAG_CHANGE_PATH)
	if result != OK:
		push_error("保存敌人库失败：" + error_string(result))
		quit(1)
		return
	project = ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	for enemy in project.bosses:
		var actor = Node2D.new()
		actor.set_script(PrefabRoot) # Godot 内置：为节点附加运行入口脚本。
		actor.name = enemy.id
		actor.library = project
		actor.kind = "bosses"
		actor.resource_id = enemy.id
		var scene = PackedScene.new()
		result = scene.pack(actor) # Godot 内置：将节点打包成场景。
		if result == OK:
			result = ResourceSaver.save(scene, "res://examples/enemies/" + enemy.id + ".tscn")
		actor.free()
		if result != OK:
			push_error("保存敌人场景失败：" + enemy.title)
			quit(1)
			return
	print("ENEMY BUILD RESULT: %d enemies, %d skills, %d bullets" % [project.bosses.size(), project.barrages.size(), project.bullets.size()])
	quit(0)

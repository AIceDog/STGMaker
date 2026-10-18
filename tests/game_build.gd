extends SceneTree
## 游戏构建回归：依赖闭包、只读迁移、坏的未使用模板隔离和输出保护。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Builder = preload("res://addons/stg_maker/build/project_builder.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture() -> STGGameDefinition:
	var game = STGGameDefinition.new()
	game.title = "构建测试"
	game.library = STGProject.create()
	Defaults.populate(game.library)
	var wave = Defaults.wave(game.library.bosses[0].id)
	game.library.waves.append(wave)
	var level = Defaults.level(wave.id)
	game.library.levels.append(level)
	game.player = STGPlayerDefinition.new()
	game.world = STGWorldDefinition.new()
	var location = STGWorldLocation.new()
	location.id = "first"
	location.level_id = level.id
	game.world.locations.append(location)
	game.start_location_id = location.id
	return game

func run() -> void:
	var game = fixture()
	var source_bullets = game.library.bullets.size()
	var unused = Defaults.bullet()
	unused.id = "unused_invalid"
	unused.collision.size.x = -10
	game.library.bullets.append(unused)
	check(not game.library.validate().is_empty(), "原制作库确实包含坏模板")
	var compiled = Compiler.compile(game)
	check(compiled.issue.is_empty(), "未引用的坏模板不会阻止当前游戏：" + compiled.issue)
	if compiled.has("game"):
		check(compiled.game.library.find("bullets", "unused_invalid") == null, "闭包删除未引用资源")
		check(compiled.game.library.bullets.size() < source_bullets + 1, "实际选中资源少于完整制作库")
		check(compiled.game.library != game.library and compiled.game.player != game.player, "定义和参数均为独立配置副本")
		compiled.game.player.max_health = 9
		check(game.player.max_health == 3, "编译结果可修改，不影响制作源")
		check(compiled.game.library.validate().is_empty(), "编译库无悬空引用")
	check(game.library.bullets.size() == source_bullets + 1 and unused.collision.size.x == -10, "编译没有修写或裁剪源资源")
	game.world.locations[0].level_id = "missing_level"
	check("missing_level" in Compiler.compile(game).issue, "缺少根关卡明确报告 ID")
	game = fixture()
	game.library.waves[0].enemy_id = "missing_enemy"
	check("missing_enemy" in Compiler.compile(game).issue, "递归依赖缺失明确报告 ID")
	game = fixture()
	var copy = game.library.bosses[0].duplicate(true)
	game.library.bosses.append(copy)
	check("重复" in Compiler.compile(game).issue, "选中的重复 ID 阻止编译")
	game = fixture()
	game.library.bullets.append(unused)
	var root_result = Compiler.compile_library(game.library, [{"collection": "barrages", "id": game.library.barrages[0].id}])
	check(root_result.issue.is_empty() and root_result.library.barrages.size() == 1, "单招式预制体可复用闭包编译")
	check(root_result.library.bosses.is_empty() and root_result.library.levels.is_empty(), "单招式不带入无关敌人和关卡")
	check(not Builder._safe_relative("../other/project.godot") and not Builder._safe_relative("C:/project.godot"), "输出清单拒绝目录逃逸")
	check(not Builder._check_destination(ProjectSettings.globalize_path("res://"), "project").issue.is_empty(), "不能覆盖源项目")
	check(Builder._absolute("exports/FirstGame").begins_with(ProjectSettings.globalize_path("res://").replace("\\", "/")), "相对输出路径属于当前源项目")
	var output = "user://game_build_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file = FileAccess.open(output.path_join("user_file.txt"), FileAccess.WRITE)
	file.store_string("保留用户文件")
	file.close()
	check(not Builder._check_destination(ProjectSettings.globalize_path(output), "project").issue.is_empty(), "非空非构建目录拒绝写入")
	check(FileAccess.get_file_as_string(output.path_join("user_file.txt")) == "保留用户文件", "输出保护不改用户文件")
	var marker = FileAccess.open(output.path_join(Builder.MARKER), FileAccess.WRITE)
	marker.store_string(JSON.stringify({"kind": "project", "files": "bad_format"}))
	marker.close()
	check(not Builder._check_destination(ProjectSettings.globalize_path(output), "project").issue.is_empty(), "损坏的构建清单正常报告错误")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output.path_join(Builder.MARKER)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output.path_join("user_file.txt")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
	if FileAccess.file_exists("res://game/game_shell.gd"):
		var unused_path = "res://game/extensions/unused_build_fixture_%s.gd" % Time.get_ticks_usec()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(unused_path.get_base_dir()))
		var unused_script = FileAccess.open(unused_path, FileAccess.WRITE)
		unused_script.store_string("extends RefCounted\n# \"res://addons/nonexistent_editor_dependency.gd\"\n")
		unused_script.close()
		var extended_game = fixture()
		var selected_extension = "res://game/extensions/accelerated_straight.tres"
		if FileAccess.file_exists(selected_extension):
			var projectile = extended_game.library.barrages[0].projectile
			var stage = projectile.motion_stages[0]
			stage.mode = "extension"
			stage.extension = STGExtensionBinding.create(load(selected_extension))
		var built = Builder.build(extended_game, "user://independent_build_%s" % Time.get_ticks_usec())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(unused_path))
		check(built.issue.is_empty(), "生成独立 Godot 项目：" + built.issue)
		if built.has("path"):
			check(not FileAccess.file_exists(built.path.path_join(unused_path.trim_prefix("res://"))), "未引用的扩展不会进入游戏或阻止构建")
			if FileAccess.file_exists(selected_extension):
				check(FileAccess.file_exists(built.path.path_join("game/extensions/accelerated_straight.gd")), "选中扩展的实现脚本进入文件依赖闭包")
				check("motion_stages" in FileAccess.get_file_as_string(built.path.path_join("game/content/first_game.tres")), "招式飞行过程进入独立游戏配置")
				check(extended_game.library.barrages[1].projectile.motion_stages[0].mode != "extension", "独立飞行导出不改另一份共用素材的招式运动")
			check(FileAccess.file_exists(built.path.path_join("project.godot")), "独立项目具有游戏入口配置")
			check(not DirAccess.dir_exists_absolute(built.path.path_join("addons")) and not DirAccess.dir_exists_absolute(built.path.path_join("tools")), "独立目录不含编辑器和迁移工具")
			check(not DirAccess.dir_exists_absolute(built.path.path_join("stg/definitions/legacy")), "独立目录不含旧模型")
			check("res://game/main.tscn" in FileAccess.get_file_as_string(built.path.path_join("project.godot")), "主场景为实际游戏")
			check(not FileAccess.file_exists(built.path.path_join(".godot/global_script_class_cache.cfg")), "新构建项目不依赖源项目缓存")
			var output_log: Array = []
			var exit_code = preload("res://tests/export_runtime.gd").import_project(built.path, output_log)
			check(exit_code == 0 and not Builder._has_errors(output_log), "独立项目没有原编辑器即可导入，退出码 %s，错误检测 %s：" % [exit_code, Builder._has_errors(output_log)] + "\n".join(output_log))
			check(FileAccess.file_exists(built.path.path_join(".godot/global_script_class_cache.cfg")), "首次导入生成独立全局类型缓存")
			output_log.clear()
			exit_code = preload("res://tests/export_runtime.gd").run(built.path, output_log)
			check(exit_code == 0 and not Builder._has_errors(output_log), "独立项目主场景可运行，退出码 %s，错误检测 %s：" % [exit_code, Builder._has_errors(output_log)] + "\n".join(output_log))
	print("GAME BUILD RESULT: %s checks, %s failures" % [checks, failures])
	print("Windows templates: ", Builder.template_status())
	quit(1 if failures else 0)


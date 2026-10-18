extends SceneTree
## 无 UI 构建入口。所有相对输出路径相对于当前 Godot 项目；不会覆盖非构建目录。
const Builder = preload("res://addons/stg_maker/build/project_builder.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var options = {}
	var index = 0
	while index < args.size():
		if not args[index].begins_with("--") or index + 1 >= args.size():
			push_error("参数格式：--definition game/content/first_game.tres --output exports/FirstGame [--windows exports/Release/Game.exe] [--engine 引擎路径]")
			quit(1)
			return
		options[args[index].trim_prefix("--")] = args[index + 1]
		index += 2
	for key in options:
		if key not in ["definition", "output", "windows", "engine"]:
			push_error("未知构建参数：--" + key)
			quit(1)
			return
	var path: String = options.get("definition", "res://game/content/first_game.tres")
	if not path.is_absolute_path() and not path.begins_with("res://"):
		path = "res://" + path
	var definition = ResourceLoader.load(path)
	if not definition is STGGameDefinition:
		push_error("无法读取游戏定义：" + path)
		quit(1)
		return
	var output: String = options.get("output", "res://exports/FirstGame")
	var result = Builder.build(definition, output)
	if not result.issue.is_empty():
		push_error(result.issue)
		quit(1)
		return
	print("独立游戏项目：", result.path)
	print("资源闭包：", result.counts)
	var engine: String = options.get("engine", "")
	if options.has("windows"):
		result = Builder.export_windows(output, options.windows, engine)
		if not result.issue.is_empty():
			push_error(result.issue)
			quit(1)
			return
		print("Windows 游戏：", result.path)
	quit(0)

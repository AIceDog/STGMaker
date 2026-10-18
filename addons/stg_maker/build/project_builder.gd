@tool
extends RefCounted
## 生成不含制作工具的独立 Godot 项目；导出只写入空目录或本工具登记过的文件。
const Compiler = preload("res://addons/stg_maker/build/compiler.gd")
const Policy = preload("res://addons/stg_maker/build/dependency_policy.gd")
const MARKER = ".stgmaker_build.json"
const CONTENT = "game/content/first_game.tres"
const TEXT_EXTENSIONS = ["gd", "tscn", "tres", "cfg", "godot", "uid", "svg", "json", "gdshader"]

static func build(game: STGGameDefinition, destination: String) -> Dictionary:
	var compiled = Compiler.compile(game)
	if not compiled.issue.is_empty():
		return compiled
	var target = _absolute(destination)
	var check = _check_destination(target, "project")
	if not check.issue.is_empty():
		return check
	var files = {}
	_gather("res://stg", files, [])
	_gather("res://game", files, ["game/content", "game/extensions"])
	# 先序列化到临时文件，整个依赖检查成功之后才写目的目录。
	var temporary = "user://compiled_game_%s.tres" % Time.get_ticks_usec()
	var error = ResourceSaver.save(compiled.game, temporary)
	if error != OK:
		return {"issue": "无法序列化游戏定义：" + error_string(error)}
	var text = FileAccess.get_file_as_string(temporary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	files[CONTENT] = {"text": text}
	files["game/main.tscn"] = {"text": "[gd_scene load_steps=3 format=3]\n\n[ext_resource type=\"Script\" path=\"res://game/game_shell.gd\" id=\"1\"]\n[ext_resource type=\"Resource\" path=\"res://%s\" id=\"2\"]\n\n[node name=\"Game\" type=\"Control\"]\nlayout_mode = 3\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\nscript = ExtResource(\"1\")\ndefinition = ExtResource(\"2\")\n" % CONTENT}
	var dependencies = _resolve_dependencies(files)
	if not dependencies.issue.is_empty():
		return dependencies
	files = dependencies.files
	var config = ConfigFile.new()
	config.set_value("application", "config/name", compiled.game.title)
	config.set_value("application", "run/main_scene", "res://game/main.tscn")
	config.set_value("application", "config/features", PackedStringArray(["4.7", "GL Compatibility"]))
	config.set_value("application", "config/use_custom_user_dir", true)
	config.set_value("application", "config/custom_user_dir_name", "STGMakerGames/" + compiled.game.title.validate_filename())
	config.set_value("display", "window/size/viewport_width", 1280)
	config.set_value("display", "window/size/viewport_height", 800)
	config.set_value("display", "window/stretch/mode", "canvas_items")
	config.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
	files["project.godot"] = {"text": "config_version=5\n\n" + config.encode_to_text()}
	files["export_presets.cfg"] = {"text": _export_preset()}
	files["Open Game Editor.cmd"] = {"text": _launcher("--editor --path \"%~dp0.\"")}
	files["Run Game.cmd"] = {"text": _launcher("--path \"%~dp0.\"", true)}
	files["Prepare Game.ps1"] = {"text": _preparation_script()}
	files["README.txt"] = {"text": "STGMaker 独立游戏项目\n启动场景：game/main.tscn\n此目录包含游戏定义和运行代码，不需要 STGMaker 编辑器插件。\n运行 Run Game.cmd；启动器先查找 GODOT_PATH 环境变量，再使用生成时的引擎位置。\n首次启动自动在隐藏窗口中导入，生成 Godot 类型与资产缓存，成功后启动游戏并关闭启动器。\n导入失败时查看 first_import.log；无 .godot 缓存的源项目不要直接用 Godot --path 启动。\nWindows 正式导出需要与引擎版本一致的 Godot Windows 导出模板。\n"}
	var written = _write(files, target, check.owned, "project")
	if not written.issue.is_empty():
		return written
	return {"issue": "", "path": target, "counts": compiled.counts, "files": files.size(), "templates": template_status()}

static func template_status() -> Dictionary:
	var version = Engine.get_version_info()
	var folder = "%s.%s.%s.%s" % [version.major, version.minor, version.patch, version.status]
	var root = OS.get_environment("APPDATA").path_join("Godot/export_templates")
	if OS.get_name() != "Windows":
		root = OS.get_environment("HOME").path_join(".local/share/godot/export_templates")
	var directory = root.path_join(folder)
	return {"available": FileAccess.file_exists(directory.path_join("windows_release_x86_64.exe")), "version": folder, "path": directory}

static func export_windows(project_directory: String, output_exe: String, engine_path: String = "") -> Dictionary:
	var status = template_status()
	if not status.available:
		return {"issue": "缺少 %s 的 Windows 导出模板：%s。已生成独立项目，可使用现有 Godot 引擎运行。" % [status.version, status.path], "templates": status}
	var destination = _absolute(output_exe)
	if destination.get_extension().to_lower() != "exe":
		return {"issue": "Windows 导出目标必须以 .exe 结尾。"}
	var check = _check_destination(destination.get_base_dir(), "windows")
	if not check.issue.is_empty():
		return check
	var temporary_directory = ProjectSettings.globalize_path("user://windows_export_%s" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(temporary_directory)
	var temporary = temporary_directory.path_join(destination.get_file())
	var log: Array = []
	var engine = engine_path if not engine_path.is_empty() else OS.get_executable_path()
	var code = OS.execute(engine, ["--headless", "--path", _absolute(project_directory), "--export-release", "Windows", temporary], log, true)
	if code != 0 or _has_errors(log) or not FileAccess.file_exists(temporary):
		return {"issue": "Windows 导出失败：\n" + "\n".join(log), "exit_code": code}
	var files = {}
	_gather(temporary_directory, files, [])
	files["GODOT_LICENSE.txt"] = {"text": _license_notice()}
	files["Run Game.cmd"] = {"text": "@echo off\r\nstart \"\" /D \"%~dp0\" \"%~dp0{GAME}\"\r\n".replace("{GAME}", destination.get_file())}
	var written = _write(files, destination.get_base_dir(), check.owned, "windows")
	for relative in files:
		if files[relative].has("source"):
			DirAccess.remove_absolute(files[relative].source)
	DirAccess.remove_absolute(temporary_directory)
	if not written.issue.is_empty():
		return written
	return {"issue": "", "path": destination}

static func _resolve_dependencies(files: Dictionary) -> Dictionary:
	var pending = files.keys()
	var visited = {}
	var pattern = RegEx.new()
	pattern.compile("[\\\"'](res://[^\\\"']+)[\\\"']")
	while not pending.is_empty():
		var relative: String = pending.pop_front()
		if visited.has(relative):
			continue
		visited[relative] = true
		var entry: Dictionary = files[relative]
		var text: String = entry.get("text", "")
		if relative.get_extension() in TEXT_EXTENSIONS and entry.has("source"):
			text = FileAccess.get_file_as_string(entry.source)
		if relative.ends_with(".gd"):
			var architecture_issues = Policy.check_source(relative, text)
			if not architecture_issues.is_empty(): return {"issue": "\n".join(architecture_issues)}
		var paths: Array[String] = []
		if relative.get_extension() in ["gd", "gdshader"]:
			paths.append_array(preload("res://addons/stg_maker/build/script_dependencies.gd").collect("res://" + relative, text))
		for match_result in pattern.search_all(text):
			paths.append(match_result.get_string(1))
		if entry.has("source") and relative.get_extension() in ["gd", "tscn", "tres", "scn", "res", "gdshader"]:
			for dependency in ResourceLoader.get_dependencies(entry.source):
				paths.append(dependency.get_slice("::", dependency.get_slice_count("::") - 1))
		for path in paths:
			var dependency: String = path.trim_prefix("res://")
			if not _safe_relative(dependency.trim_suffix("/")):
				return {"issue": "%s 包含非法运行依赖路径：%s" % [relative, path]}
			if dependency.ends_with("/"):
				continue
			if Policy.editor_only(dependency):
				return {"issue": "%s 引用了不能进入成品的制作代码：%s" % [relative, dependency]}
			var direction_issue = Policy.issue(relative, path)
			if not direction_issue.is_empty(): return {"issue": "%s → %s：%s" % [relative, dependency, direction_issue]}
			if files.has(dependency):
				continue
			var source = "res://" + dependency
			if not FileAccess.file_exists(source):
				return {"issue": "%s 的文件依赖不存在：%s" % [relative, source]}
			files[dependency] = {"source": source}
			pending.append(dependency)
			if FileAccess.file_exists(source + ".uid"):
				files[dependency + ".uid"] = {"source": source + ".uid"}
	return {"issue": "", "files": files}

static func _gather(directory: String, files: Dictionary, excluded: Array, base: String = "", imports: bool = false) -> void:
	var dir = DirAccess.open(directory)
	if dir == null:
		return
	var prefix = directory.trim_prefix("res://") if directory.begins_with("res://") else base
	for name in dir.get_files():
		var relative = prefix.path_join(name) if not prefix.is_empty() else name
		if relative in excluded or (name.ends_with(".import") and not imports):
			continue
		files[relative] = {"source": directory.path_join(name)}
	for name in dir.get_directories():
		var relative = prefix.path_join(name) if not prefix.is_empty() else name
		if relative in excluded or name.begins_with("."):
			continue
		_gather(directory.path_join(name), files, excluded, relative, imports)

static func _check_destination(target: String, kind: String) -> Dictionary:
	var source = _absolute("res://")
	var comparison = target.to_lower() if OS.get_name() == "Windows" else target
	var original = source.to_lower() if OS.get_name() == "Windows" else source
	if target.is_empty() or comparison == original or target == target.get_base_dir():
		return {"issue": "构建目录不能覆盖源项目、运行代码或磁盘根目录。"}
	for directory in ["stg", "game", "addons", "tools", "tests", "assets", "presets", "docs"]:
		if comparison == original + "/" + directory or comparison.begins_with(original + "/" + directory + "/"):
			return {"issue": "构建目录不能位于源项目内容目录中。"}
	if FileAccess.file_exists(target):
		return {"issue": "构建目标是文件：" + target}
	if not DirAccess.dir_exists_absolute(target):
		return {"issue": "", "owned": []}
	var dir = DirAccess.open(target)
	if dir.get_files().is_empty() and dir.get_directories().is_empty():
		return {"issue": "", "owned": []}
	var marker = target.path_join(MARKER)
	if not FileAccess.file_exists(marker):
		return {"issue": "构建目录已有内容且不属于 STGMaker，未写入：" + target}
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(marker))
	if not manifest is Dictionary or manifest.get("kind", "") != kind:
		return {"issue": "构建标记无效或构建类型不同：" + target}
	var owned = manifest.get("files", null)
	if not owned is Array:
		return {"issue": "构建文件清单格式无效：" + target}
	for relative in owned:
		if not relative is String or not _safe_relative(relative):
			return {"issue": "构建文件清单包含非法路径：" + target}
	return {"issue": "", "owned": owned}

static func _write(files: Dictionary, target: String, owned: Array, kind: String) -> Dictionary:
	for relative in files:
		if not _safe_relative(relative):
			return {"issue": "非法构建文件路径：" + relative}
		if FileAccess.file_exists(target.path_join(relative)) and relative not in owned:
			return {"issue": "目标包含未登记的同名文件，未覆盖：" + relative}
	var error = DirAccess.make_dir_recursive_absolute(target)
	if error != OK:
		return {"issue": "无法创建构建目录：" + error_string(error)}
	for relative in files:
		var path = target.path_join(relative)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var entry: Dictionary = files[relative]
		if entry.has("source"):
			error = DirAccess.copy_absolute(ProjectSettings.globalize_path(entry.source), path)
		else:
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return {"issue": "无法写入：" + path}
			file.store_string(entry.text)
			error = OK
		if error != OK:
			return {"issue": "复制失败：" + path + "：" + error_string(error)}
	# 仅删除上一次清单登记、且本次不再生成的文件；保留用户额外文件。
	for relative in owned:
		if _safe_relative(relative) and not files.has(relative):
			DirAccess.remove_absolute(target.path_join(relative))
	var marker = FileAccess.open(target.path_join(MARKER), FileAccess.WRITE)
	if marker == null:
		return {"issue": "无法保存构建文件清单。"}
	marker.store_string(JSON.stringify({"format": 1, "kind": kind, "files": files.keys()}, "\t"))
	return {"issue": ""}

static func _safe_relative(path: String) -> bool:
	return not path.is_empty() and not path.is_absolute_path() and not ".." in path.split("/") and not path.contains("\\") and not path.contains(":")

static func _absolute(path: String) -> String:
	if path.is_empty():
		return ""
	if not path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().trim_suffix("/")

static func _has_errors(log: Array) -> bool:
	for line in log:
		if "SCRIPT ERROR:" in str(line) or "ERROR:" in str(line):
			return true
	return false

static func _launcher(arguments: String, import_first: bool = false) -> String:
	var engine = OS.get_executable_path().replace("_console.exe", ".exe")
	var prepare = ""
	if import_first:
		prepare = "if not exist \"%~dp0.godot\\global_script_class_cache.cfg\" (\r\n echo Preparing game resources for the first run...\r\n powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%~dp0Prepare Game.ps1\" -Engine \"%STG_ENGINE%\"\r\n if errorlevel 1 (\r\n  echo Game preparation failed. See first_import.log.\r\n  pause\r\n  exit /b 1\r\n )\r\n)\r\nif not exist \"%~dp0.godot\\global_script_class_cache.cfg\" (\r\n echo Godot did not create its script cache. See first_import.log.\r\n pause\r\n exit /b 1\r\n)\r\n"
	return "@echo off\r\nsetlocal\r\nset \"STG_ENGINE=%GODOT_PATH%\"\r\nif not defined STG_ENGINE set \"STG_ENGINE={ENGINE}\"\r\nif not exist \"%STG_ENGINE%\" (\r\n echo Godot not found. Set GODOT_PATH to your Godot executable.\r\n pause\r\n exit /b 1\r\n)\r\n{PREPARE}start \"\" /D \"%~dp0\" \"%STG_ENGINE%\" {ARGUMENTS}\r\nexit /b 0\r\n".replace("{ENGINE}", engine).replace("{PREPARE}", prepare).replace("{ARGUMENTS}", arguments)


static func _preparation_script() -> String:
	# Windows 首次导入采用实际渲染器，隐藏辅助窗口并保留原始退出码。
	return '''param([Parameter(Mandatory = $true)][string]$Engine)
$ErrorActionPreference = 'Stop'
$taskOutput = Join-Path $PSScriptRoot 'first_import.stdout.log'
$taskError = Join-Path $PSScriptRoot 'first_import.stderr.log'
$taskLog = Join-Path $PSScriptRoot 'first_import.log'
$taskArguments = @('--path', ('"{0}"' -f $PSScriptRoot), '--import')
$taskProcess = Start-Process -FilePath $Engine -WindowStyle Hidden -PassThru -ArgumentList $taskArguments -RedirectStandardOutput $taskOutput -RedirectStandardError $taskError
if (-not $taskProcess.WaitForExit(60000)) {
    $taskProcess.Kill()
    Set-Content -LiteralPath $taskLog -Value 'ERROR: Resource preparation exceeded 60 seconds.'
    exit 1
}
$taskProcess.Refresh()
$taskMessages = @(Get-Content -LiteralPath $taskOutput) + @(Get-Content -LiteralPath $taskError)
$taskMessages | Set-Content -LiteralPath $taskLog
if ($taskProcess.ExitCode -ne 0) { exit $taskProcess.ExitCode }
if ($taskMessages | Select-String -Pattern 'SCRIPT ERROR|ERROR:') { exit 1 }
exit 0
'''

static func _license_notice() -> String:
	var notice = "Godot Engine\n\n" + Engine.get_license_text()
	for component in Engine.get_copyright_info():
		notice += "\n\n" + component.name + "\n"
		for part in component.parts:
			notice += "\n".join(part.copyright) + "\nLicense: " + part.license + "\n"
	for name in Engine.get_license_info():
		notice += "\n\n" + name + "\n" + Engine.get_license_info()[name]
	return notice

static func _export_preset() -> String:
	return "[preset.0]\nname=\"Windows\"\nplatform=\"Windows Desktop\"\nrunnable=true\nadvanced_options=false\ndedicated_server=false\ncustom_features=\"\"\nexport_filter=\"all_resources\"\ninclude_filter=\"\"\nexclude_filter=\"*.cmd,*.ps1,README.txt,.stgmaker_build.json\"\nexport_path=\"release/Game.exe\"\nencryption_include_filters=\"\"\nencryption_exclude_filters=\"\"\nencrypt_pck=false\nencrypt_directory=false\nscript_export_mode=2\n\n[preset.0.options]\ncustom_template/debug=\"\"\ncustom_template/release=\"\"\nbinary_format/embed_pck=true\nbinary_format/architecture=\"x86_64\"\ntexture_format/bptc=true\ntexture_format/s3tc=true\ntexture_format/etc2=false\ncodesign/enable=false\napplication/modify_resources=false\n"

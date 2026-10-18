extends RefCounted
## Windows 的游戏 UI 冒烟测试使用实际后端，避免 Dummy 在退出时的原生访问违例。
static func import_project(project: String, log: Array) -> int:
	if OS.get_name() != "Windows": return OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "--import"], log, true)
	var powershell = OS.get_environment("STG_TEST_POWERSHELL")
	if powershell.is_empty(): powershell = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var result = OS.execute(powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", project.path_join("Prepare Game.ps1"), "-Engine", OS.get_executable_path()], log, true)
	var path = project.path_join("first_import.log")
	if FileAccess.file_exists(path): log.append(FileAccess.get_file_as_string(path))
	return result

static func run(project: String, log: Array, script: String = "", frames: int = 30) -> int:
	if script.is_empty():
		# 实际实例化主场景，断言菜单已初始化；退出前先正常释放 UI，再结束引擎。
		# 这也验证产品场景自己的清理路径，而非只观察 --quit-after 的进程存活。
		var verifier = FileAccess.open(project.path_join(".verify_startup.gd"), FileAccess.WRITE)
		if verifier == null: return ERR_CANT_CREATE
		verifier.store_string('''extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene = load("res://game/main.tscn").instantiate()
	root.add_child(scene)
	for frame in 30: await process_frame
	var valid = scene.session != null and scene.session.state == "menu" and scene.session.issue.is_empty()
	scene.queue_free()
	for frame in 8: await process_frame
	valid = valid and not is_instance_valid(scene)
	print("EXPORTED STARTUP RESULT: 1 checks, %d failures" % (0 if valid else 1))
	quit(0 if valid else 1)
''')
		verifier.close()
		script = ".verify_startup.gd"
		frames = 2000
	if OS.get_name() == "Windows":
		var powershell = OS.get_environment("STG_TEST_POWERSHELL")
		if powershell.is_empty(): powershell = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
		var options: Array[String] = ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/run_hidden_game.ps1"), "-Engine", OS.get_executable_path(), "-Project", project, "-Frames", str(frames)]
		if not script.is_empty(): options.append_array(["-Script", script])
		return OS.execute(powershell, options, log, true)
	var arguments: Array[String] = ["--headless", "--path", project, "--quit-after", str(frames)]
	if not script.is_empty(): arguments.append_array(["--script", script])
	return OS.execute(OS.get_executable_path(), arguments, log, true)

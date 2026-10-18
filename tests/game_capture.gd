extends SceneTree
## 用实际 Godot 渲染确认菜单、地图入口、战斗 HUD、暂停和结算的布局。
const Fixture = preload("res://tests/game_fixture.gd")
const Shell = preload("res://game/game_shell.gd")
var shell
var images = 0

func _initialize() -> void:
	run.call_deferred()

func shot(name: String) -> void:
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/game_" + name + "_actual.png")
	images += 1

func run() -> void:
	root.size = Vector2i(1440, 900)
	shell = Shell.new()
	shell.definition = Fixture.create()
	shell.save_path = "res://tests/.game_capture_progress.json"
	if FileAccess.file_exists(shell.save_path):
		DirAccess.remove_absolute(shell.save_path)
	root.add_child(shell)
	await shot("menu")
	shell.session.show_map()
	await shot("map")
	shell.session.enter_location("coast")
	await shot("battle")
	shell.session.toggle_pause()
	await shot("paused")
	shell.session.toggle_pause()
	for _tick in 360:
		shell.session.advance(STGSimulation.STEP, Vector2.ZERO, true)
	await shot("result")
	shell.session.return_to_map()
	await shot("unlocked_map")
	root.size = Vector2i(1100, 760)
	await shot("small_map")
	shell.queue_free()
	for _frame in 8:
		await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists("res://tests/.game_capture_progress.json" + suffix):
			DirAccess.remove_absolute("res://tests/.game_capture_progress.json" + suffix)
	print("GAME CAPTURE RESULT: %d images saved" % images)
	quit(0)

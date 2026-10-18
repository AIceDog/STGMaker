extends SceneTree
## 横向预览集成：比例、窗口 / 字号适配、裁剪、默认方向、玩家边界和编辑控制点。
const CombatSpace = preload("res://stg/definitions/combat_space.gd")
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
var checks = 0
var failures = 0

func _initialize() -> void: # Godot 回调
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 8: await process_frame

func run() -> void:
	var studio = load("res://addons/stg_maker/studio.tscn").instantiate()
	studio.restore_last_project = false
	studio.settings_path = "user://horizontal_preview_checks.cfg"
	root.add_child(studio)
	await settle()
	studio.set_process(false)
	var canvas = studio.canvas
	for window_size in [Vector2i(1100, 760), Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = window_size
		await settle()
		var frame: Rect2 = canvas.screen_rect()
		check(is_equal_approx(frame.size.x / frame.size.y, 16.0 / 9), "不同窗口下虚拟屏幕保持 16:9")
		check(Rect2(Vector2.ZERO, canvas.size).encloses(frame), "完整虚拟屏幕放入画布，不裁切或撑大 UI")
		check(canvas.battle_screen.position.is_equal_approx(frame.position) and canvas.battle_screen.size.is_equal_approx(frame.size), "实际裁剪矩形与显示的屏幕边框一致")
		for point in [CombatSpace.BOUNDS.position, CombatSpace.BOUNDS.end, Vector2.ZERO]:
			check(canvas.value(canvas.screen(point)).is_equal_approx(point), "屏幕角点和中心的鼠标坐标转换可逆")
	studio.set_font_size(24, false)
	studio.set_ui_scale(150, false)
	await settle()
	check(canvas.battle_screen.position.is_equal_approx(canvas.screen_rect().position), "修改字号与缩放后同步裁剪区")
	check(canvas.battle_screen.clip_contents and canvas.world.get_parent() == canvas.battle_screen, "战斗实体裁剪在虚拟屏幕内部")
	studio.set_font_size(0, false)
	studio.set_ui_scale(0, false)
	root.size = Vector2i(1440, 900)
	await settle()
	studio.restart()
	check(canvas.world.player == CombatSpace.PLAYER_SPAWN and canvas.world.boss == CombatSpace.ENEMY_SPAWN, "重新测试时玩家在左、敌人在右")
	var middle = canvas.world.actors[4]
	var start: Vector2 = middle.position
	for i in 60: canvas.world.step()
	check(middle.position.x < start.x and absf(middle.position.y) < 60, "默认扇射的中心子弹朝左跨屏攻击")
	canvas.grab_focus()
	await settle()
	var event = InputEventKey.new()
	event.physical_keycode = KEY_D
	event.pressed = true
	canvas._gui_input(event)
	canvas.world.player = Vector2(475, 0)
	canvas.control_player(1, true)
	check(is_equal_approx(canvas.world.player.x, 476), "WASD 玩家被限制在屏幕碰撞半径内")
	canvas.release_player_controls()
	studio.switch_collection("bullets", "bullet_laser")
	await settle()
	check(canvas.handles.is_empty(), "激光素材不再提供外形拖拽手柄")
	studio.edit_path(["visual", "geometry"], "size", Vector2(500, studio.current().visual.geometry.size.y))
	await settle()
	check(is_equal_approx(studio.current().visual.geometry.size.x, 500), "激光长度由同页数值参数配置")
	studio.set_tool("path")
	studio.edit_beam = true
	studio.edit_path([], "beam_path", Defaults.path([Vector2.ZERO, Vector2(100, 80), Vector2(200, 0)]), true)
	await settle()
	canvas.rebuild()
	check(is_equal_approx(canvas.path_angle, PI) and canvas.handles[3].point.x < canvas.path_origin.x, "曲线激光路径手柄与真实发射方向一致")
	studio.switch_collection("bullets", "bullet_green")
	studio.set_tool("path")
	await settle()
	check(canvas.path == null and canvas.handles.is_empty(), "静态素材不再拥有独立运动路径")
	studio.switch_collection("barrages", studio.session.project.barrages[0].id)
	studio.edit_path(["projectile", "motion_stages", 0], "mode", "path", true)
	studio.edit_path(["projectile", "motion_stages", 0], "path", Defaults.path([Vector2.ZERO, Vector2(0, 100)]), true)
	studio.set_tool("flight_path")
	await settle()
	check(is_equal_approx(canvas.path_angle, PI / 2) and canvas.handles[3].point.x < canvas.path_origin.x, "招式中移动弹的局部 +Y 路径正确旋转为左向")
	var library: STGProject = load("res://presets/enemy_library.tres")
	check(library.bosses.all(func(enemy): return enemy.start_position.x > 0 and CombatSpace.BOUNDS.has_point(enemy.start_position)), "十个敌人都从屏幕右侧开始")
	check(library.barrages.filter(func(skill): return not skill.id.ends_with("_projectile") and library.find("bullets", skill.projectile.bullet_id).form != "trail").all(func(skill): return skill.fire_pattern.angle == 180), "示例的制作招式默认朝左，直接发射弹体和路径尾迹的朝向由调用方传入")
	studio.switch_collection("barrages", studio.session.project.barrages[-1].id)
	await settle()
	check(canvas.world.player == CombatSpace.PLAYER_SPAWN, "切换缩圈招式不再把玩家移到中央")
	studio.queue_free()
	await settle()
	print("HORIZONTAL PREVIEW RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

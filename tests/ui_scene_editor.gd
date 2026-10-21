@tool
extends EditorPlugin
## 真实 Godot 编辑器：设计模式无制作副作用，插件使用同一保存后的场景。
const SCENE = "res://addons/stg_maker/studio.tscn"
var checks = 0
var failures = 0
func _enter_tree(): run.call_deferred()
func check(ok: bool, message: String):
    checks += 1
    if not ok: failures += 1; push_error(message)
func settle():
    for frame in 30: await get_tree().process_frame
func run():
    await settle()
    await get_tree().create_timer(1.0).timeout
    var filesystem = EditorInterface.get_resource_filesystem()
    var start = Time.get_ticks_msec()
    while filesystem.is_scanning() and Time.get_ticks_msec() - start < 20000:
        await get_tree().create_timer(0.1).timeout
    var scene_hash = FileAccess.get_sha256(SCENE)
    var theme_hash = FileAccess.get_sha256("res://addons/stg_maker/ui/studio_theme.tres")
    var prefs = FileAccess.get_sha256("user://stg_maker.cfg") if FileAccess.file_exists("user://stg_maker.cfg") else ""
    EditorInterface.open_scene_from_path(SCENE)
    start = Time.get_ticks_msec()
    while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != SCENE) and Time.get_ticks_msec() - start < 10000:
        await get_tree().create_timer(0.1).timeout
    await settle()
    var design = EditorInterface.get_edited_scene_root()
    check(design != null and design.scene_file_path == SCENE, "真实编辑器可打开主界面场景；当前：%s；已打开：%s" % [design.scene_file_path if design != null else "null", str(EditorInterface.get_open_scenes())])
    if design != null and design.scene_file_path == SCENE:
        check(not design.workspace_active and design.session.project == null and design.canvas == null, "设计模式不创建会话或战斗预览")
        check(design.get_children().filter(func(node): return node is Timer).is_empty(), "设计模式不启动自动草稿计时器")
        check(design.get_node("%canvas_slot").get_child(0).visible, "设计模式展示静态占位提示")
        check(design.get_node("%HeaderPanel").size.x > 0 and design.get_node("%LibraryPanel").size.x > 0, "设计模式显示实际布局")
    EditorInterface.set_main_screen_editor("2D")
    await settle()
    RenderingServer.force_draw(false)
    get_tree().root.get_texture().get_image().save_png("res://tests/.test_run_logs/ui_scene_design_actual.png")
    EditorInterface.close_scene()
    await settle()
    var form_path = "res://addons/stg_maker/ui/forms/material_properties.tscn"
    var form_hash = FileAccess.get_sha256(form_path)
    EditorInterface.open_scene_from_path(form_path)
    var form_started = Time.get_ticks_msec()
    while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != form_path) and Time.get_ticks_msec() - form_started < 10000:
        await get_tree().create_timer(0.1).timeout
    await settle()
    var form = EditorInterface.get_edited_scene_root()
    check(form != null and form.scene_file_path == form_path, "真实编辑器可打开素材属性场景")
    if form != null and form.scene_file_path == form_path:
        check(form.get_meta("form_root", false) and not form.has_meta("form_registry"), "属性场景设计时不绑定制作数据")
        var fields = form.find_children("*", "Control", true, false).filter(func(node): return node.has_meta("form_key"))
        check(fields.size() > 30, "属性场景包含真实固定字段")
        var authored = load(form_path).instantiate()
        var flags = {}
        for node in authored.find_children("*", "Control", true, false):
            if node.has_meta("form_key"): flags[str(node.get_meta("form_key"))] = node.visible
        check(fields.all(func(node): return node.visible == flags[str(node.get_meta("form_key"))]), "设计时保留用户保存的条件字段可见性")
        authored.free()
    EditorInterface.set_main_screen_editor("2D")
    await settle()
    RenderingServer.force_draw(false)
    get_tree().root.get_texture().get_image().save_png("res://tests/.test_run_logs/property_form_editor_actual.png")
    EditorInterface.close_scene()
    await settle()
    check(FileAccess.get_sha256(form_path) == form_hash, "打开关闭属性场景不改写资源")
    var screen = EditorInterface.get_editor_main_screen()
    var active = screen.find_children("*", "", true, false).filter(func(node): return node.get_script() == load("res://addons/stg_maker/ui/studio_workspace.gd") and node.workspace_active)
    check(active.size() == 1, "插件只有一个已激活场景实例")
    if active.size() == 1:
        var studio = active[0]
        check(studio.scene_file_path == SCENE and studio.canvas.world != null, "插件实例化同一场景并启动预览")
        studio.session.project=preload("res://tests/unified14_fixture.gd").project()
        studio.switch_collection("barrages","fan");studio.refresh(true);await settle()
        check(studio.inspector.find_children("*","Control",true,false).any(func(n):return n.get_meta("program_parameter","")=="angle"),"真实插件装配声明参数")
        var count = studio.get_child_count()
        studio.activate_workspace()
        check(studio.get_child_count() == count, "真实编辑器重复激活安全")
        EditorInterface.set_main_screen_editor("STGMaker")
        await settle()
        RenderingServer.force_draw(false)
        get_tree().root.get_texture().get_image().save_png("res://tests/.test_run_logs/ui_scene_plugin_actual.png")
    # 保存一份修改后的场景，再在真实插件宿主中激活，验证设计值确实进入插件。
    var folder = "user://ui_scene_editor_checks"
    DirAccess.make_dir_recursive_absolute(folder)
    var authored = load(SCENE).instantiate()
    var custom_theme: Theme = authored.theme.duplicate(true)
    custom_theme.default_font_size = 21
    var normal: StyleBoxFlat = custom_theme.get_stylebox("normal", "STGPrimaryButton").duplicate()
    normal.bg_color = Color("6753a1")
    custom_theme.set_stylebox("normal", "STGPrimaryButton", normal)
    ResourceSaver.save(custom_theme, folder + "/theme.tres")
    authored.theme = load(folder + "/theme.tres")
    authored.get_node("%library_panel").custom_minimum_size.x = 241
    authored.get_node("%layout_outer").add_theme_constant_override("separation", 13)
    var packed = PackedScene.new()
    packed.pack(authored); ResourceSaver.save(packed, folder + "/studio.tscn")
    authored.free()
    var variant = load(folder + "/studio.tscn").instantiate()
    variant.restore_last_project = false
    variant.settings_path = folder + "/unused.cfg"
    screen.add_child(variant)
    check(not variant.workspace_active, "编辑器中的实例需要显式激活")
    variant.activate_workspace()
    variant.set_font_size(0, false)
    for scale in [100, 150, 100]:
        variant.set_ui_scale(scale, false)
        await settle()
        var unit = float(variant.theme.default_font_size) / 21
        check(is_equal_approx(variant.library_panel.custom_minimum_size.x, 241 * unit) and variant.layout_outer.get_theme_constant("separation") == roundi(13 * unit), "插件保留保存后的宽度与间距：%d" % scale)
        check(variant.save_button.get_theme_stylebox("normal").bg_color == normal.bg_color, "插件保留保存后的主题颜色：%d" % scale)
        check(variant.save_button.get_theme_font_size("font_size") == variant.theme.default_font_size, "主题基础字号可编辑：%d" % scale)
    variant.free()
    for file in ["studio.tscn", "theme.tres"]: DirAccess.remove_absolute(folder + "/" + file)
    check(FileAccess.get_sha256(SCENE) == scene_hash and FileAccess.get_sha256("res://addons/stg_maker/ui/studio_theme.tres") == theme_hash, "编辑设计场景不改写源资源")
    check((FileAccess.get_sha256("user://stg_maker.cfg") if FileAccess.file_exists("user://stg_maker.cfg") else "") == prefs, "打开关闭设计场景不写入用户偏好")
    print("UI SCENE EDITOR RESULT: %d checks, %d failures" % [checks, failures])
    finish.call_deferred()

func finish():preload("res://tests/editor_shutdown.gd").request(self)


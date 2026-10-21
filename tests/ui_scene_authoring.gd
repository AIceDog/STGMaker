extends SceneTree
## 保存后的设计必须在实例化、刷新和反复缩放后保留，且不改写源资源。
const SCENE = "res://addons/stg_maker/studio.tscn"
const FOLDER = "user://ui_scene_authoring_checks"
var checks = 0
var failures = 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
    checks += 1
    if not ok: failures += 1; push_error(message)
func settle():
    for frame in 12: await process_frame
func run():
    root.size = Vector2i(1440, 900)
    DirAccess.make_dir_recursive_absolute(FOLDER)
    var scene_hash = FileAccess.get_sha256(SCENE)
    var theme_hash = FileAccess.get_sha256("res://addons/stg_maker/ui/studio_theme.tres")
    var authored = load(SCENE).instantiate()
    check(authored.session.project == null and not authored.workspace_active, "未激活的设计实例不创建制作会话")
    var theme: Theme = authored.theme.duplicate(true)
    var normal: StyleBoxFlat = theme.get_stylebox("normal", "STGPrimaryButton").duplicate()
    normal.bg_color = Color("6753a1")
    theme.set_stylebox("normal", "STGPrimaryButton", normal)
    check(ResourceSaver.save(theme, FOLDER + "/theme.tres") == OK, "主题设计可保存")
    authored.theme = load(FOLDER + "/theme.tres")
    var width = authored.get_node("%library_panel").custom_minimum_size.x + 28
    authored.get_node("%library_panel").custom_minimum_size.x = width
    authored.get_node("%layout_outer").add_theme_constant_override("separation", 17)
    authored.get_node("%save_button").add_theme_color_override("font_color", Color("ffe19a"))
    # Change hierarchy without breaking the unique-name behavior bindings.
    var brand = authored.get_node("%brand")
    var wrapper = HBoxContainer.new()
    brand.get_parent().add_child(wrapper); wrapper.owner = authored
    brand.owner = null
    brand.reparent(wrapper)
    brand.owner = authored
    brand.unique_name_in_owner = true
    var packed = PackedScene.new()
    check(packed.pack(authored) == OK and ResourceSaver.save(packed, FOLDER + "/studio.tscn") == OK, "布局、局部样式与节点层级修改可保存")
    authored.free()
    var studio = load(FOLDER + "/studio.tscn").instantiate()
    studio.restore_last_project = false
    studio.settings_path = FOLDER + "/preferences.cfg"
    studio.session.recovery_folder = FOLDER + "/drafts"
    root.add_child(studio)
    studio.set_font_size(0, false); studio.set_ui_scale(100, false)
    await settle()
    studio.session.project=preload("res://tests/unified14_fixture.gd").project();studio.selected_id="fan";studio.collection="barrages";studio.refresh(true);await settle()
    var count = studio.find_children("*", "", true, false).size()
    studio.activate_workspace(); studio.activate_workspace()
    check(count == studio.find_children("*", "", true, false).size(), "重复激活不重复装配或连接")
    for scale in [150, 200, 100, 150, 100]:
        studio.set_ui_scale(scale, false)
        studio.refresh(true)
        await settle()
        var unit = scale / 100.0
        check(is_equal_approx(studio.library_panel.custom_minimum_size.x, width * unit), "侧栏设计宽度缩放后保留：%d" % scale)
        check(studio.layout_outer.get_theme_constant("separation") == roundi(17 * unit), "局部间距没有被写死值覆盖：%d" % scale)
        check(studio.save_button.get_theme_stylebox("normal").bg_color == normal.bg_color, "保存的按钮颜色保留：%d" % scale)
        check(studio.save_button.get_theme_color("font_color") == Color("ffe19a"), "局部颜色覆盖保留：%d" % scale)
    studio.bullet_button.pressed.emit(); await settle()
    check(studio.collection == "bullets" and studio.asset_list.item_count > 0, "静态节点的资源导航与列表已连接")
    studio.library_search.text = "不存在的资源名称"
    studio.library_search.text_changed.emit(studio.library_search.text); await settle()
    check(studio.asset_list.item_count == 0 and studio.library_empty.visible, "搜索与空列表反馈保留")
    studio.library_search.text = ""
    studio.library_search.text_changed.emit(""); await settle()
    var previous = studio.current().title
    studio.edit_path([], "title", previous + " 测试", true); await settle()
    check(studio.current().title != previous, "属性修改仍进入会话")
    studio.undo_button.pressed.emit(); await settle()
    check(studio.current().title == previous, "静态撤销按钮已连接")
    studio.redo_button.pressed.emit(); await settle()
    check(studio.current().title != previous, "静态重做按钮已连接")
    studio.session.recoverable_changes = false
    studio.queue_free(); await settle()
    check(FileAccess.get_sha256(SCENE) == scene_hash and FileAccess.get_sha256("res://addons/stg_maker/ui/studio_theme.tres") == theme_hash, "运行、刷新、缩放没有改写源场景和主题")
    for file in ["studio.tscn", "theme.tres", "preferences.cfg"]:
        if FileAccess.file_exists(FOLDER + "/" + file): DirAccess.remove_absolute(FOLDER + "/" + file)
    print("UI SCENE AUTHORING RESULT: %d checks, %d failures" % [checks, failures])
    quit(1 if failures else 0)

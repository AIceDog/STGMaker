@tool
extends EditorPlugin
## Godot 主工作区的挂载入口；独立运行 studio.tscn 使用完全相同的制作工作台。
## 本模块只管理界面的生命周期，玩法与制作数据不依赖 EditorInterface。

const Studio = preload("res://addons/stg_maker/ui/studio_workspace.gd")
var screen: Control


func _enter_tree() -> void: # Godot 回调：启用插件时挂载工作台。
	screen = Control.new()
	screen.set_script(Studio)
	# 主工作区是 VBoxContainer；Expand 让 Godot 容器分配完整高度。
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_visible(false)


func _exit_tree() -> void: # Godot 回调：卸载插件时释放界面。
	if is_instance_valid(screen):
		screen.queue_free()


func _has_main_screen() -> bool: # Godot EditorPlugin 回调：注册独立主工作区。
	return true


func _make_visible(value: bool) -> void: # Godot EditorPlugin 回调：切换顶部工作区。
	if is_instance_valid(screen):
		screen.visible = value


func _get_plugin_name() -> String: # Godot EditorPlugin 回调：顶部标签名称。
	return "STGMaker"


func _get_plugin_icon() -> Texture2D: # Godot EditorPlugin 回调：复用编辑器主题图标。
	return EditorInterface.get_editor_theme().get_icon("GPUParticles2D", "EditorIcons")

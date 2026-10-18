@tool
extends RefCounted
## 真实编辑器通过关闭通知收尾；手工发射 Window 信号不会产生系统关闭通知。
static func request(plugin: EditorPlugin) -> void:
	var settings = EditorInterface.get_editor_settings()
	var key = "interface/editor/quit_confirmation"
	var previous = settings.get_setting(key)
	settings.set_setting(key, false)
	plugin.tree_exiting.connect(func(): settings.set_setting(key, previous), CONNECT_ONE_SHOT)
	EditorInterface.get_base_control().get_parent().notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

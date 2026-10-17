@tool
extends Control
## 屏幕内的编辑层：放在战斗内容上方，继承虚拟屏幕裁剪，控制点不会遮挡旁边的 UI。
var canvas

func _ready() -> void: # Godot 回调
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void: # Godot 回调；实际绘制目标是本编辑层。
	if canvas != null: canvas.draw_edit_overlay(self)

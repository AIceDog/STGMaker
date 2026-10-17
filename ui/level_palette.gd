@tool
extends ItemList
## Godot 拖放源：携带类型和资源 ID，落点由时间轴 / 战斗画面转为关卡事件。
var host

func _ready() -> void: # Godot 回调
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item_activated.connect(func(index):
		var data = get_item_metadata(index)
		host.edit_reference(data.kind, data.id))

func refresh() -> void:
	clear()
	for collection in ["bosses", "waves", "obstacles"]:
		for item in host.session.project.get(collection):
			var label = {"bosses": "敌人", "waves": "编队", "obstacles": "障碍"}[collection]
			add_item("⋮⋮ " + label + " · " + item.title)
			set_item_metadata(item_count - 1, {"kind": collection, "id": item.id})
			var scope = {"bosses": "敌人的移动、攻击和离场由敌人定义负责。", "waves": "编队负责出场数量、排列与生成间隔，复用敌人的自身行为。", "obstacles": "障碍复用自己的外观、碰撞与生命周期设置。"}[collection]
			set_item_tooltip(item_count - 1, item.title + "\n拖到时间轴安排出场；拖到画面设置本阶段的出生点。\n" + scope + "双击编辑共享定义，会影响所有引用它的出场事件。")

func _get_drag_data(at: Vector2): # Godot Control 拖放回调
	var index = get_item_at_position(at, true)
	if index < 0: return null
	var preview = Label.new()
	preview.text = get_item_text(index)
	set_drag_preview(preview) # Godot 内置拖放预览。
	return get_item_metadata(index)

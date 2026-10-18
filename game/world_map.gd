extends Control
## 地图入口使用标准 Button；连接线与背景刻度只是信息显示。
signal location_selected(identifier: String)
var world: STGWorldDefinition
var progress: STGProgressStore
var selected_id: String = ""
var buttons: Dictionary = {}

func configure(definition: STGWorldDefinition, store: STGProgressStore, selected: String) -> void:
	world = definition
	progress = store
	selected_id = selected
	for location in world.locations:
		var button = Button.new()
		button.custom_minimum_size = Vector2(180, 88)
		var state = "已通关" if progress.completed.has(location.id) else "可挑战"
		if not progress.is_unlocked(location):
			state = "尚未解锁"
		button.text = location.title + "\n" + state
		button.disabled = not progress.is_unlocked(location)
		button.tooltip_text = location.description
		button.pressed.connect(func(): location_selected.emit(location.id))
		add_child(button)
		buttons[location.id] = button
	resized.connect(_layout_buttons)
	_layout_buttons()

func _location_point(location: STGWorldLocation) -> Vector2:
	var minimum = Vector2(INF, INF)
	var maximum = Vector2(-INF, -INF)
	for item in world.locations:
		minimum = minimum.min(item.map_position)
		maximum = maximum.max(item.map_position)
	var extent = maximum - minimum
	var fraction = Vector2(0.5, 0.5)
	if extent.x > 0:
		fraction.x = (location.map_position.x - minimum.x) / extent.x
	if extent.y > 0:
		fraction.y = (location.map_position.y - minimum.y) / extent.y
	return Vector2(115, 100) + fraction * (size - Vector2(230, 200)).max(Vector2.ZERO)

func _layout_buttons() -> void:
	if world == null:
		return
	for location in world.locations:
		var button: Button = buttons[location.id]
		button.position = _location_point(location) - Vector2(90, 44)
		button.size = Vector2(180, 88)
		button.modulate = Color("8fe6ff") if location.id == selected_id else Color.WHITE
	queue_redraw()

func _draw() -> void:
	for x in range(24, int(size.x), 48):
		for y in range(24, int(size.y), 48):
			draw_circle(Vector2(x, y), 1.2, Color("273b52"))
	if world == null:
		return
	for location in world.locations:
		for previous in location.requires_completion:
			var source = world.find(previous)
			if source != null:
				var color = Color("64b7b0") if progress.is_unlocked(location) else Color("34445c")
				draw_line(_location_point(source), _location_point(location), color, 3, true)

@tool
extends RefCounted
## 预览时间条：拖动时只显示目标时刻，释放后才分批重放；程序同步不会触发 seek。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const MAX_SECONDS = 8.0
const UI_KEY = "preview_transport"

static func build(host, parent: Node) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	F.help(F.label(row, "预览时间"), "当前招式从开始到现在的测试时间；只用于查看效果，与关卡时间轴的出场安排无关。")
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = MAX_SECONDS
	slider.step = 1.0 / 120.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 60
	slider.tooltip_text = "拖动并释放：重放到前 8 秒的指定时刻，保持当前玩家位置。只改变测试进度。"
	row.add_child(slider)
	var time = F.note(row, "0.00 / 8.00 s")
	F.help(time, "左侧是当前测试时间，8 秒是可拖动回看的范围。定位时显示重放进度；正常测试可以继续超过 8 秒。")
	time.custom_minimum_size.x = 135
	var ui = {"row": row, "slider": slider, "time": time, "dragging": false}
	host.set_meta(UI_KEY, ui)
	slider.drag_started.connect(func(): ui.dragging = true)
	slider.value_changed.connect(func(value):
		ui.time.text = "%.2f / 8.00 s" % value
		if not ui.dragging: host.canvas.seek_preview(value))
	slider.drag_ended.connect(func(changed):
		ui.dragging = false
		if changed: host.canvas.seek_preview(slider.value))

static func update(host) -> void:
	if not host.has_meta(UI_KEY):
		return
	var ui: Dictionary = host.get_meta(UI_KEY)
	ui.row.visible = host.collection == "barrages" and host.canvas.visible
	if not ui.row.visible or ui.dragging:
		return
	var canvas = host.canvas
	ui.slider.editable = canvas.world.issue.is_empty()
	var seconds = canvas.seek_destination() if canvas.is_seeking() else canvas.world.time
	ui.slider.set_value_no_signal(minf(MAX_SECONDS, seconds))
	if canvas.is_seeking():
		ui.time.text = "计算中 %.2f / %.2f s" % [canvas.world.time, seconds]
	else:
		ui.time.text = "%.2f / 8.00 s" % seconds if seconds <= MAX_SECONDS else "%.2f s" % seconds

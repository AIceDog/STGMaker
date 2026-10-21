@tool
extends RefCounted
## 预览时间条：拖动时只显示目标时刻，释放后才分批重放；程序同步不会触发 seek。
const MAX_SECONDS = 8.0
const UI_KEY = "preview_transport"

static func bind(host) -> void:
	var row = host.Layout.node(host, "transport_row")
	var slider = host.Layout.node(host, "transport_slider")
	var time = host.Layout.node(host, "transport_time")
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

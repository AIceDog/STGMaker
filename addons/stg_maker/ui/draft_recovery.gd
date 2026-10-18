@tool
extends RefCounted
## 恢复是明确的选择：只读取本机副本，恢复后另存，绝不写回原资源库。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const DIALOG_KEY = "draft_recovery_dialog"

static func setup(host) -> void:
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	host.add_child(timer)
	timer.timeout.connect(func():
		var issue = host.session.save_recovery()
		if not issue.is_empty(): host.file_status.text = issue)
	host.session.changed.connect(func(): timer.start())
	if host.restore_last_project and not host.session.available_drafts().is_empty():
		# 插件挂载时主工作区可能尚未显示，不能自动创建会锁住整个编辑器的原生模态窗。
		var notice = HBoxContainer.new()
		host.layout_outer.add_child(notice)
		host.layout_outer.move_child(notice, 2)
		var caption = F.note(notice, "发现本机未保存草稿，可查看并恢复。")
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		F.button(notice, "查看草稿…", func(): show_drafts(host); notice.hide())
		F.button(notice, "稍后", notice.hide)

static func show_drafts(host) -> void:
	var existing = host.get_meta(DIALOG_KEY) if host.has_meta(DIALOG_KEY) else null
	if is_instance_valid(existing) and not existing.is_queued_for_deletion():
		_popup(host, existing)
		return
	var entries = host.session.available_drafts()
	var dialog = AcceptDialog.new()
	dialog.title = "恢复本机草稿"
	host.add_child(dialog)
	host.set_meta(DIALOG_KEY, dialog)
	dialog.get_ok_button().text = "关闭"
	dialog.confirmed.connect(func(): _close(host, dialog))
	dialog.canceled.connect(func(): _close(host, dialog))
	# 所有说明和条目都放进滚动区，长路径、大字号和多份草稿不能扩大窗口最小高度。
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	F.note(list, "恢复后请另存确认。来源文件不会被自动覆盖；当前未保存修改会先保留为另一份草稿。")
	if entries.is_empty(): F.note(list, "没有待恢复的本机资源库草稿。")
	for entry in entries:
		var row = HBoxContainer.new()
		list.add_child(row)
		var time = Time.get_datetime_string_from_unix_time(int(entry.saved_at)).replace("T", " ") + " UTC"
		var caption = F.label(row, (entry.source if not entry.source.is_empty() else "未命名资源库") + "\n本机备份时间：" + time)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		F.button(row, "恢复", func():
			var issue = host.session.recover_draft(entry.path)
			# 新提示弹出前先释放旧窗口的原生模态锁，不能只等 queue_free。
			_close(host, dialog)
			if not issue.is_empty(): host.message(issue); return
			host.navigation.parents.clear()
			host.library_search.text = ""
			host.reset_selection()
			host.refresh(true)
			host.message("\n".join(host.session.notes)), "primary")
	_popup(host, dialog)

static func _popup(host, dialog: AcceptDialog) -> void:
	var unit = maxf(1.0, host.theme.default_font_size / 18.0) if host.theme != null else 1.0
	dialog.popup_centered_clamped(Vector2i(Vector2(720, 460) * unit))

static func _close(host, dialog: AcceptDialog) -> void:
	if host.has_meta(DIALOG_KEY) and host.get_meta(DIALOG_KEY) == dialog: host.remove_meta(DIALOG_KEY)
	dialog.hide()
	dialog.queue_free()

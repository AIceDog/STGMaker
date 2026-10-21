@tool
extends RefCounted
## 编辑会话：文件和编辑历史；玩法不依赖此模块。每次编辑替换快照，撤销不回写磁盘。
signal changed
const Assets = preload("res://addons/stg_maker/authoring/asset_store.gd")
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const Documents = preload("res://addons/stg_maker/authoring/document_loader.gd")
const Drafts = preload("res://addons/stg_maker/authoring/draft_store.gd")
var disk_revision: Dictionary = {}
var project: STGProject
var saved_project: STGProject
var file_path: String = ""
var undo_stack: Array[STGProject] = []
var redo_stack: Array[STGProject] = []
var notes: PackedStringArray = []
var recovery_folder: String = Drafts.ROOT
var recovery_source: String = ""
var recovery_slot: String = ""
var last_recovery_project: STGProject
var recoverable_changes: bool = false
const Copy = preload("res://stg/definitions/config_copy.gd")
const Trace = preload("res://addons/stg_maker/ui/performance_trace.gd")
var last_change: Dictionary = {"structure": true}
var undo_details: Array[Dictionary] = []
var redo_details: Array[Dictionary] = []
var _merge_key: String = ""
var _merge_time: int = 0

func edit_asset(collection: String, id: String, change: Callable, detail: Dictionary = {}, merge_key: String = "") -> void:
    var started = Time.get_ticks_usec()
    var next: STGProject = project.duplicate(false)
    var entries: Array = project.get(collection).duplicate()
    var index = entries.find(project.find(collection, id))
    if index < 0: return
    entries[index] = Copy.copy(entries[index])
    next.set(collection, entries)
    change.call(next)
    var now = Time.get_ticks_msec()
    # 只有同一数值控件的连续手势合并；导航、保存和撤销均切断手势。
    var merge = not merge_key.is_empty() and merge_key == _merge_key and now - _merge_time < 400 and project != saved_project and not undo_stack.is_empty()
    if not merge:
        undo_stack.append(project)
        undo_details.append(detail.duplicate())
        if undo_stack.size() > 40:
            undo_stack.pop_front()
            if not undo_details.is_empty(): undo_details.pop_front()
    redo_stack.clear()
    redo_details.clear()
    project = next
    last_change = detail.duplicate()
    _merge_key = merge_key
    _merge_time = now
    recoverable_changes = true
    Trace.record("asset_transaction", started, project)
    changed.emit()

func create() -> String:
    var issue = save_recovery()
    if not issue.is_empty(): return issue
    project = STGProject.create()
    Defaults.populate(project)
    saved_project = null
    disk_revision.clear()
    file_path = ""
    recovery_source = ""
    recovery_slot = Drafts.new_slot("")
    recoverable_changes = false
    undo_stack.clear()
    redo_stack.clear()
    undo_details.clear()
    redo_details.clear()
    _merge_key = ""
    last_change = {"structure": true}
    notes.clear()
    changed.emit()
    return ""

func edit(change: Callable) -> void:
    # change 只写 next；保存旧对象后整体替换。一个回调中的关联修改只占一次撤销。
    _merge_key = ""
    last_change = {"structure": true}
    var next = project.snapshot()
    change.call(next)
    undo_stack.append(project)
    undo_details.append(last_change.duplicate())
    if undo_stack.size() > 40:
        undo_stack.pop_front()
        if not undo_details.is_empty(): undo_details.pop_front()
    redo_stack.clear()
    redo_details.clear()
    project = next
    recoverable_changes = true
    changed.emit()

func undo() -> void:
    if undo_stack.is_empty():
        return
    _merge_key = ""
    last_change = undo_details.pop_back() if not undo_details.is_empty() else {"structure": true}
    redo_details.append(last_change.duplicate())
    redo_stack.append(project)
    project = undo_stack.pop_back()
    recoverable_changes = true
    changed.emit()

func redo() -> void:
    if redo_stack.is_empty():
        return
    _merge_key = ""
    last_change = redo_details.pop_back() if not redo_details.is_empty() else {"structure": true}
    undo_details.append(last_change.duplicate())
    undo_stack.append(project)
    project = redo_stack.pop_back()
    recoverable_changes = true
    changed.emit()

func dirty() -> bool: return project != saved_project

func open(path: String) -> String:
    var loading = Documents.library(path)
    if not loading.issue.is_empty(): return loading.issue
    var loaded = loading.resource
    if not loaded is STGProject:
        return "文件不是 STGMaker 项目。"
    Assets.refresh_library(loaded)
    var converted: STGProject = loaded.snapshot()
    # 未完成的属性、引用和空列表仍是可编辑文档。运行与导出单独执行严格校验。
    var issue = save_recovery()
    if not issue.is_empty(): return issue
    project = converted
    notes.clear()
    file_path = loading.path
    disk_revision = Assets.capture(loading.path)
    recovery_source = loading.path
    recovery_slot = Drafts.new_slot(loading.path)
    recoverable_changes = false
    saved_project = null if file_path.is_empty() else project
    undo_stack.clear()
    redo_stack.clear()
    undo_details.clear()
    redo_details.clear()
    _merge_key = ""
    last_change = {"structure": true}
    changed.emit()
    return ""

func save(path: String) -> String:
    _merge_key = ""
    var expected = disk_revision if ProjectSettings.globalize_path(path) == ProjectSettings.globalize_path(file_path) else {}
    var issue = Assets.save_library(project, path, expected)
    if not issue.is_empty(): return issue
    disk_revision = Assets.capture(path)
    file_path = path
    Drafts.discard(recovery_folder, "library", recovery_slot)
    recovery_source = path
    recovery_slot = Drafts.new_slot(path)
    saved_project = project
    recoverable_changes = false
    last_recovery_project = project
    changed.emit()
    return ""

func save_recovery() -> String:
    # UI 以单次延时调用；只在快照改变后序列化，刷新和预览不会反复拷贝或写盘。
    if project == null or not recoverable_changes: return ""
    if not dirty():
        Drafts.discard(recovery_folder, "library", recovery_slot)
        last_recovery_project = null
        return ""
    if project == last_recovery_project: return ""
    var issue = Drafts.write(project, recovery_folder, "library", recovery_source, "战斗资源库", recovery_slot)
    if issue.is_empty(): last_recovery_project = project
    return issue

func available_drafts() -> Array[Dictionary]:
    return Drafts.list_drafts(recovery_folder, "library")

func recover_draft(path: String) -> String:
    var entry: Dictionary = {}
    for candidate in available_drafts():
        if candidate.path == path: entry = candidate
    if entry.is_empty(): return "恢复草稿不存在。"
    var loaded = Drafts.load_draft(path)
    if not loaded is STGProject: return "恢复草稿不是 STGMaker 资源库。"
    # 先读取目标，再把当前未保存内容放入独立位置；相同来源也不能相互覆盖。
    if project != null and dirty() and recoverable_changes and (project != last_recovery_project or entry.slot != recovery_slot):
        var backup_slot = "before_restore_" + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_usec())
        var issue = Drafts.write(project, recovery_folder, "library", recovery_source, "恢复前的未保存资源库", backup_slot)
        if not issue.is_empty(): return issue
    if loaded.schema_version != STGProject.VERSION: return "恢复草稿不是当前格式。"
    project = loaded.snapshot()
    saved_project = null
    disk_revision.clear()
    file_path = "" # 恢复后显式另存；绝不静默覆盖来源文件。
    recovery_source = entry.source
    recovery_slot = entry.slot
    last_recovery_project = project
    recoverable_changes = true
    undo_stack.clear()
    redo_stack.clear()
    undo_details.clear()
    redo_details.clear()
    _merge_key = ""
    last_change = {"structure": true}
    notes = PackedStringArray(["已恢复本机草稿；请另存确认。来源：" + (entry.source if not entry.source.is_empty() else "未命名资源库")])
    changed.emit()
    return ""

func discard_draft(path: String) -> void:
    for entry in available_drafts():
        if entry.path == path:
            Drafts.discard(recovery_folder, "library", entry.slot)
            return


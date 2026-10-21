@tool
extends RefCounted
## 本机恢复副本与原文件分开保存。只记录编辑快照，不参与运行、导出或资源校验。
const ROOT = "user://stg_maker_drafts"

static func new_slot(source: String) -> String:
    # 同一来源在不同编辑会话中的未确认草稿分开保留，稍后恢复不会被新编辑覆盖。
    return source + "@" + str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_usec())

static func key_for(kind: String, source: String) -> String:
    return kind + "_" + (source if not source.is_empty() else "untitled").sha256_text()

static func write(resource: Resource, folder: String, kind: String, source: String, title: String, slot: String = "") -> String:
    var error = DirAccess.make_dir_recursive_absolute(folder)
    if error != OK: return "无法创建本机草稿目录：" + error_string(error)
    var stem = folder.path_join(key_for(kind, slot if not slot.is_empty() else source))
    var temporary = stem + ".new.tres"
    error = ResourceSaver.save(resource, temporary)
    if error != OK: return "无法保存本机恢复草稿：" + error_string(error)
    # 保留上一份完整副本，替换失败时仍可恢复；不向原资源路径写入任何内容。
    var previous = stem + ".previous.tres"
    if FileAccess.file_exists(previous): DirAccess.remove_absolute(previous)
    if FileAccess.file_exists(stem + ".tres"):
        error = DirAccess.rename_absolute(stem + ".tres", previous)
        if error != OK: return "无法更新本机恢复草稿：" + error_string(error)
    error = DirAccess.rename_absolute(temporary, stem + ".tres")
    if error != OK:
        if FileAccess.file_exists(previous): DirAccess.rename_absolute(previous, stem + ".tres")
        return "无法替换本机恢复草稿：" + error_string(error)
    var metadata = ConfigFile.new()
    metadata.set_value("draft", "kind", kind)
    metadata.set_value("draft", "schema_version", STGProject.VERSION)
    metadata.set_value("draft", "source", source)
    metadata.set_value("draft", "slot", slot if not slot.is_empty() else source)
    metadata.set_value("draft", "title", title)
    metadata.set_value("draft", "saved_at", Time.get_unix_time_from_system())
    error = metadata.save(stem + ".cfg")
    return "" if error == OK else "无法记录本机草稿信息：" + error_string(error)

static func list_drafts(folder: String, kind: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var directory = DirAccess.open(folder)
    if directory == null: return result
    for file in directory.get_files():
        if not file.begins_with(kind + "_") or not file.ends_with(".cfg"): continue
        var metadata = ConfigFile.new()
        if metadata.load(folder.path_join(file)) != OK: continue
        if metadata.get_value("draft", "schema_version", -1)!=STGProject.VERSION: continue
        var path = folder.path_join(file.get_basename() + ".tres")
        if not FileAccess.file_exists(path): continue
        var source: String = metadata.get_value("draft", "source", "")
        result.append({"path": path, "source": source, "slot": metadata.get_value("draft", "slot", source), "title": metadata.get_value("draft", "title", ""), "saved_at": metadata.get_value("draft", "saved_at", 0.0)})
    result.sort_custom(func(a, b): return a.saved_at > b.saved_at)
    return result

static func discard(folder: String, kind: String, source: String) -> void:
    var stem = folder.path_join(key_for(kind, source))
    for suffix in [".tres", ".cfg", ".new.tres", ".previous.tres"]:
        if FileAccess.file_exists(stem + suffix): DirAccess.remove_absolute(stem + suffix)

static func load_draft(path: String) -> Resource:
    return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

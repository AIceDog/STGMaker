@tool
extends RefCounted
## 文档是资产索引；顶层内容逐个保存。先序列化/检查全部文件，再提交，失败时回滚。
## 不改输入快照和资源缓存；只更新本工具登记的资产，外部修改通过磁盘修订检测保护。
const Copy = preload("res://stg/definitions/config_copy.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const TYPES = {"behavior_presets":"behavior_preset", "attack_presets": "attack_preset", "bullets": "bullet_definition", "barrages": "barrage_skill", "behaviors": "behavior_flow", "bosses": "boss_definition", "waves": "wave_definition", "levels": "level_definition", "obstacles": "obstacle_definition"}
const MARKER = ".stgmaker_assets.json"

static func save_library(project: STGProject, path: String, expected: Dictionary = {}) -> String:
    var plan = _library_plan(project, path)
    if not plan.issue.is_empty(): return plan.issue
    return _commit(plan.files, plan.owned, expected, [path])

static func save_game(game: STGGameDefinition, path: String, library_path: String, expected: Dictionary = {}) -> String:
    if game == null or game.library == null: return "游戏缺少资源库。"
    if path.get_extension().to_lower() != "tres" or _absolute(path).to_lower() == _absolute(library_path).to_lower(): return "游戏与资源库必须使用不同的 .tres 索引。"
    var plan = _library_plan(game.library, library_path)
    if not plan.issue.is_empty(): return plan.issue
    var directory = path.get_basename() + ".assets"
    var files: Dictionary = plan.files
    var owned: Dictionary = plan.owned
    var read_marker = _read_marker(directory, path)
    if not read_marker.issue.is_empty(): return read_marker.issue
    owned.merge(read_marker.owned)
    var shell: STGGameDefinition = game.duplicate(false)
    shell.library = null
    shell.player = null
    shell.world = null
    var serialized = _serialize(shell)
    if not serialized.issue.is_empty(): return serialized.issue
    var declarations = '[ext_resource type="Resource" path=%s id="asset_library"]\n' % _quote(library_path)
    var properties = '\nlibrary = ExtResource("asset_library")\n'
    var managed = {}
    for key in ["player", "world"]:
        var value = game.get(key)
        if value == null: continue # 未完成的游戏配置仍可保存草稿。
        var relative = ("players" if key == "player" else "worlds") + "/main.tres"
        var asset_path = directory.path_join(relative)
        var asset = _serialize(Copy.copy(value))
        if not asset.issue.is_empty(): return asset.issue
        files[asset_path] = asset.text
        managed[relative] = asset.text.sha256_text()
        declarations += '[ext_resource type="Resource" path=%s id="asset_%s"]\n' % [_quote(asset_path), key]
        properties += '%s = ExtResource("asset_%s")\n' % [key, key]
    files[path] = _index_text(serialized.text, declarations, properties)
    files[directory.path_join(MARKER)] = _marker_text(path, managed, read_marker.files)
    return _commit(files, owned, expected, [library_path, path])

static func _library_plan(project: STGProject, path: String) -> Dictionary:
    if project == null or path.get_extension().to_lower() != "tres": return {"issue": "资源库必须保存为 .tres。"}
    var directory = path.get_basename() + ".assets"
    var marker = _read_marker(directory, path)
    if not marker.issue.is_empty(): return marker
    var snapshot: STGProject = project.snapshot()
    var files = {}
    var managed = {}
    var declarations = ""
    var properties = "\n"
    for collection in References.COLLECTIONS:
        var values: Array = snapshot.get(collection).duplicate()
        snapshot.get(collection).clear()
        var ids = {}
        var entries: Array[String] = []
        var type_id = "type_" + collection
        declarations += '[ext_resource type="Script" path="res://stg/definitions/%s.gd" id="%s"]\n' % [TYPES[collection], type_id]
        for index in values.size():
            var asset: Resource = values[index]
            if asset == null:
                entries.append("null")
                continue
            var identifier = str(asset.id)
            var occurrence = int(ids.get(identifier, 0))
            ids[identifier] = occurrence + 1
            # ID 仍用于逻辑引用；文件名仅作安全编码，重复/空 ID 的草稿也能独立落盘。
            var name = identifier.validate_filename().left(60)
            if name.is_empty(): name = "unnamed"
            name += "-" + identifier.sha256_text().left(8) + ("-%d" % occurrence if occurrence > 0 else "")
            var relative = collection + "/" + name + ".tres"
            var asset_path = directory.path_join(relative)
            var serialized = _serialize(asset)
            if not serialized.issue.is_empty(): return serialized
            files[asset_path] = serialized.text
            managed[relative] = serialized.text.sha256_text()
            var key = collection + "_" + str(index)
            declarations += '[ext_resource type="Resource" path=%s id="%s"]\n' % [_quote(asset_path), key]
            entries.append('ExtResource("%s")' % key)
        properties += '%s = Array[ExtResource("%s")]([%s])\n' % [collection, type_id, ", ".join(entries)]
    var serialized = _serialize(snapshot)
    if not serialized.issue.is_empty(): return serialized
    files[path] = _index_text(serialized.text, declarations, properties)
    files[directory.path_join(MARKER)] = _marker_text(path, managed, marker.files)
    return {"issue": "", "files": files, "owned": marker.owned}

static func _index_text(shell: String, declarations: String, properties: String) -> String:
    return shell.replace("[resource]", declarations + "\n[resource]") + properties

static func _quote(value: String) -> String:
    # JSON 字符串引号与 Godot 文本资源的路径转义规则一致。
    return JSON.stringify(value.replace("\\", "/"))

static func _serialize(resource: Resource) -> Dictionary:
    var temporary = "user://asset_serialize_%s.tres" % Time.get_ticks_usec()
    var error = ResourceSaver.save(resource, temporary)
    if error != OK: return {"issue": "无法序列化资产：" + error_string(error)}
    var text = FileAccess.get_file_as_string(temporary)
    DirAccess.remove_absolute(temporary)
    return {"issue": "", "text": _canonical_ids(text)}

static func _canonical_ids(text: String) -> String:
    # ResourceSaver 为临时保存路径生成随机引用 ID；稳定编号避免未修改资产产生版本噪声。
    # 只替换资源声明及引用表达式，策划的字符串使用转义引号，不参与替换。
    var pattern = RegEx.new()
    pattern.compile(' id="([^"]+)"')
    var counts = {"Ext": 0, "Sub": 0}
    var replacements = {}
    var nonce = "stg_serial_" + str(Time.get_ticks_usec()) + "_"
    for line in text.split("\n"):
        var kind = "Ext" if line.begins_with("[ext_resource ") else ("Sub" if line.begins_with("[sub_resource ") else "")
        if kind.is_empty(): continue
        var match_result = pattern.search(line)
        if match_result == null: continue
        counts[kind] += 1
        var old = match_result.get_string(1)
        var temporary = nonce + kind + str(counts[kind])
        text = text.replace(line, line.replace(' id="%s"' % old, ' id="%s"' % temporary))
        text = text.replace('%sResource("%s")' % [kind, old], '%sResource("%s")' % [kind, temporary])
        replacements[temporary] = kind.to_lower() + "_" + str(counts[kind])
    for temporary in replacements: text = text.replace(temporary, replacements[temporary])
    return text

static func _read_marker(directory: String, index: String) -> Dictionary:
    var path = directory.path_join(MARKER)
    var result = {"issue": "", "owned": {}, "files": {}}
    if not FileAccess.file_exists(path): return result
    var marker = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not marker is Dictionary or marker.get("version", 0) != 1 or marker.get("owner", "") != index.get_file() or not marker.get("files") is Dictionary:
        return {"issue": "资产目录登记信息无效，未写入：" + directory}
    for relative in marker.files:
        if not _safe_relative(relative) or not marker.files[relative] is String:
            return {"issue": "资产目录登记包含非法路径，未写入：" + directory}
        result.owned[_absolute(directory.path_join(relative))] = marker.files[relative]
    result.files = marker.files
    result.owned[_absolute(path)] = FileAccess.get_sha256(path)
    return result

static func _marker_text(index: String, managed: Dictionary, previous: Dictionary) -> String:
    # 不自动删除已取消引用的独立资产；其他文档可能仍在复用它。
    var files = previous.duplicate()
    files.merge(managed, true)
    return JSON.stringify({"version": 1, "owner": index.get_file(), "files": files}, "\t") + "\n"

static func _safe_relative(value: Variant) -> bool:
    return value is String and not value.is_empty() and not value.is_absolute_path() and not value.contains("\\") and not value.contains(":") and not ".." in value.split("/")

static func _absolute(path: String) -> String:
    return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()

static func _commit(files: Dictionary, owned: Dictionary, expected: Dictionary, roots: Array) -> String:
    for path in expected:
        if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != expected[path]:
            return "磁盘文件已被其他操作修改，请重新打开后合并：" + path
    var root_paths = roots.map(func(path): return _absolute(path))
    for path in files:
        var absolute = _absolute(path)
        if not FileAccess.file_exists(path) or absolute in root_paths: continue
        if not owned.has(absolute): return "资产目录存在未登记的同名文件，未覆盖：" + path
        var baseline = expected.get(absolute, owned[absolute])
        if FileAccess.get_sha256(path) != baseline: return "独立资产已在外部修改，请重新打开后合并：" + path
    var staged = {}
    var previous = {}
    var token = str(Time.get_ticks_usec())
    for path in files:
        var error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        if error != OK:
            _cleanup(staged.values())
            return "无法创建资产目录：" + error_string(error)
        var temporary = path.get_base_dir().path_join(".stg-tmp-" + token + "-" + path.get_file())
        var file = FileAccess.open(temporary, FileAccess.WRITE)
        if file == null:
            _cleanup(staged.values())
            return "无法写入资产临时文件：" + path
        file.store_string(files[path])
        file.flush()
        var write_error = file.get_error()
        file.close()
        if write_error != OK:
            _cleanup(staged.values())
            DirAccess.remove_absolute(temporary)
            return "资产临时文件写入失败：" + path
        staged[path] = temporary
        previous[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
    var order: Array = files.keys().filter(func(path): return not _absolute(path) in root_paths)
    order.append_array(roots) # 索引最后提交，游戏索引在资源库索引之后。
    var written: Array = []
    for path in order:
        # 内容没有变化就不触碰文件，方便版本管理与外部工具观察实际改动。
        if previous[path] != null and previous[path] == str(files[path]).to_utf8_buffer():
            DirAccess.remove_absolute(staged[path])
            continue
        var error = DirAccess.rename_absolute(staged[path], path)
        if error != OK:
            var rollback_issues: Array[String] = []
            for changed in written:
                if previous[changed] == null:
                    if DirAccess.remove_absolute(changed) != OK: rollback_issues.append(changed)
                else:
                    var restore = FileAccess.open(changed, FileAccess.WRITE)
                    if restore == null: rollback_issues.append(changed)
                    else:
                        restore.store_buffer(previous[changed])
                        restore.flush()
                        if restore.get_error() != OK: rollback_issues.append(changed)
                        restore.close()
            _cleanup(staged.values())
            return "保存提交失败：%s。%s" % [path, "已回滚本次改动。" if rollback_issues.is_empty() else "需要手动恢复：" + ", ".join(rollback_issues)]
        written.append(path)
    _cleanup(staged.values())
    return ""

static func _cleanup(paths: Array) -> void:
    for path in paths:
        if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

## 记录文档与外部配置文件修订；脚本/美术保持正常缓存，不重复加载整个执行依赖图。
static func capture(path: String) -> Dictionary:
    return _capture(path, {})

static func _capture(path: String, visited: Dictionary) -> Dictionary:
    path = _absolute(path)
    if visited.has(path) or not FileAccess.file_exists(path): return visited
    visited[path] = FileAccess.get_sha256(path)
    var marker = path.get_basename() + ".assets/" + MARKER
    if FileAccess.file_exists(marker): visited[marker] = FileAccess.get_sha256(marker)
    var pattern = RegEx.new()
    pattern.compile('path="((?:[^"\\\\]|\\\\.)+)"')
    for match_result in pattern.search_all(FileAccess.get_file_as_string(path)):
        var dependency = str(JSON.parse_string('"' + match_result.get_string(1) + '"'))
        if dependency.ends_with(".tres"):
            if not dependency.is_absolute_path() and not dependency.begins_with("res://") and not dependency.begins_with("user://"): dependency = path.get_base_dir().path_join(dependency)
            _capture(dependency, visited)
    return visited

static func refresh_library(library: STGProject) -> STGProject:
    for collection in References.COLLECTIONS:
        var entries: Array = library.get(collection)
        for index in entries.size():
            if entries[index] == null: continue
            var path: String = entries[index].resource_path
            if not path.is_empty() and not "::" in path:
                var fresh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
                if fresh != null: entries[index] = fresh
    return library

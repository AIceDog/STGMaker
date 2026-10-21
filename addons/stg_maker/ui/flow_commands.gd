@tool
extends RefCounted
## 流程编辑接口：插入、连接、删除、排列都通过 Session 快照，可撤销。
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const ConfigPath = preload("res://addons/stg_maker/authoring/config_path.gd")
const Copy = preload("res://stg/definitions/config_copy.gd")

static func _edit(host, change: Callable) -> void:
    host.inspector_dirty = true
    var collection = host.collection
    var identifier = host.selected_id
    var scope = host.flow_scope()
    host.session.edit(func(project): change.call(ConfigPath.resolve(project.find(collection, identifier), scope)))

static func add(host, program: String) -> void:
    var selected=host.boss_node()
    var node=Defaults.flow_node(program)
    var old_next=selected.outputs()[0] if selected!=null and not selected.outputs().is_empty() else host.boss_flow().entry_id
    node.set_output(0,old_next)
    node.editor_position=selected.editor_position+Vector2(0,260) if selected!=null else Vector2(250,50)
    _edit(host,func(flow):_insert(flow,selected,node))
    host.flow_node_id=node.id

static func _insert(flow, selected, node) -> void:
    for other in flow.nodes:
        if not node.outputs().is_empty() and _reaches(flow,node.outputs()[0],other.id,[]):other.editor_position.y+=260
    flow.nodes.append(node)
    if selected==null:flow.entry_id=node.id
    else:flow.find(selected.id).set_output(0,node.id)

static func connect_nodes(host, from: String, port: int, to: String) -> void:
    var flow = host.boss_flow()
    var target = STGFlowNode.FAILURE if to=="failure_end" else ("" if to == "end" else to)
    if not STGFlowNode.is_terminal(target) and flow.find(target) == null: return
    if from == "entry":
        if STGFlowNode.is_terminal(target): return
        _edit(host, func(next): next.entry_id = target); return
    var node = flow.find(from)
    if node == null: return
    if from == target or _reaches(flow, target, from, []): host.message("此连接形成循环，请使用阶段的循环开关。"); return
    _edit(host, func(next): next.find(from).set_output(port, target))

static func disconnect_nodes(host, from: String, port: int, _to: String) -> void:
    if from == "entry": _edit(host, func(flow): flow.entry_id = "")
    else: _edit(host, func(flow): flow.find(from).set_output(port, ""))

static func _reaches(flow, id: String, target: String, visited: Array) -> bool:
    if id == target: return true
    if id in visited or STGFlowNode.is_terminal(id): return false
    var node = flow.find(id)
    if node == null: return false
    visited.append(id)
    for next in node.outputs():
        if _reaches(flow, next, target, visited): return true
    return false

static func remove(host) -> void:
    var node = host.boss_node()
    if node == null: return
    if host.boss_flow().nodes.size() == 1: host.message("至少保留一个行为节点。"); return
    _edit(host, func(flow):
        if flow.entry_id == node.id: flow.entry_id = (node.outputs()[0] if not node.outputs().is_empty() else "")
        if flow.loop_entry_id == node.id: flow.loop_entry_id = ""
        for other in flow.nodes:
            for port in other.outputs().size():
                if other.outputs()[port] == node.id: other.set_output(port, (node.outputs()[0] if not node.outputs().is_empty() else ""))
            if other.program_parameters.get("node_id", "") == node.id: other.program_parameters.node_id = ""
        flow.nodes.remove_at(flow.index_of(node.id)))
    host.flow_node_id = ""

static func duplicate_node(host) -> void:
    var selected = host.boss_node()
    if selected == null: host.message("请先选择要复制的节点。"); return
    var node: STGFlowNode = Copy.copy(selected)
    node.id = Defaults.uid("flow"); node.title += " 副本"
    node.editor_position += Vector2(0, 260)
    _edit(host, func(flow): _insert(flow, selected, node))
    host.flow_node_id = node.id

static func set_positions(host, positions: Dictionary) -> void:
    _edit(host, func(flow):
        for id in positions:
            if flow.find(id) != null: flow.find(id).editor_position = positions[id])

static func arrange(host) -> void:
    var flow = host.boss_flow()
    var columns = {}
    _depth(flow, flow.entry_id, 0, columns, [])
    var rows = {}; var counts = {}; var positions = {}
    for node in flow.nodes:
        var level: int = columns.get(node.id, 0)
        counts[level] = counts.get(level, 0) + 1
    for node in flow.nodes:
        var column: int = columns.get(node.id, 0)
        var row: int = rows.get(column, 0)
        positions[node.id] = Vector2(250 + (row - (counts[column] - 1) / 2.0) * 330, 50 + column * 280)
        rows[column] = row + 1
    set_positions(host, positions)
    host.flow_editor.request_fit()

static func _depth(flow, id: String, level: int, columns: Dictionary, visited: Array) -> void:
    if STGFlowNode.is_terminal(id) or id in visited: return
    var node = flow.find(id)
    if node == null: return
    columns[id] = maxi(columns.get(id, 0), level)
    var next = visited.duplicate(); next.append(id)
    for target in node.outputs(): _depth(flow, target, level + 1, columns, next)

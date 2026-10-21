@tool
extends VBoxContainer
## GraphEdit/GraphNode 是 Godot 控件；连线表示下一步，编辑规则在 FlowCommands。
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Commands = preload("res://addons/stg_maker/ui/flow_commands.gd")
const Style = preload("res://addons/stg_maker/ui/interaction_style.gd")
var host
var graph: GraphEdit
var labels: Dictionary = {}
var displayed_states: Dictionary = {}
var rebuilding: bool = false
var display_unit: float = 1
var programs:Array=[]
var add_menu: MenuButton
var fit_frames: int = -1
var last_entry: String = ""
var last_count: int = -1
var copy_button: Button
var remove_button: Button

func _ready() -> void: # Godot 回调
    var toolbar = HFlowContainer.new(); add_child(toolbar)
    add_menu = MenuButton.new(); add_menu.text = "＋ 插入节点"; toolbar.add_child(add_menu)
    Style.button(add_menu)
    F.help(add_menu, "向当前行为流程插入节点；插入后在右侧设置，再连接后续步骤。")
    _refresh_programs()
    add_menu.get_popup().about_to_popup.connect(_refresh_programs)
    add_menu.get_popup().id_pressed.connect(func(index):Commands.add(host,programs[index].resource_path.get_file().get_basename()))
    F.button(toolbar,"行为节点预设…",func():preload("res://addons/stg_maker/ui/behavior_node_fields.gd").open_presets(host))
    copy_button = F.button(toolbar, "复制节点", func(): Commands.duplicate_node(host))
    remove_button = F.button(toolbar, "删除节点", func(): Commands.remove(host), "danger")
    F.help(F.button(toolbar, "自动排列", func(): Commands.arrange(host)), "重新排布当前流程图中的节点位置；保持现有连线与执行顺序，可以撤销。")
    F.button(toolbar, "总览流程", func(): fit_graph()).tooltip_text = "缩放到看见所有节点；需要读清文字时，用画布上方的缩放按钮放大。"
    graph = GraphEdit.new()
    graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
    graph.minimap_enabled = false; graph.show_minimap_button = false
    graph.show_arrange_button = false; graph.show_grid_buttons = false
    graph.right_disconnects = true; graph.connection_lines_antialiased = true
    F.help(graph, "点击节点后在右侧编辑；拖动节点只改变图中排布，\n不改变敌人的战斗位置。\n从右侧输出点拖线到下一节点左侧输入点，\n会改变执行顺序；拖动已有连线端点可改接。\n画布上方的缩放按钮只调整视图。")
    add_child(graph)
    graph.resized.connect(request_fit)
    graph.connection_request.connect(func(from, port, to, _target_port): Commands.connect_nodes(host, str(from), port, str(to)))
    graph.disconnection_request.connect(func(from, port, to, _target_port): Commands.disconnect_nodes(host, str(from), port, str(to)))
    graph.end_node_move.connect(_commit_positions)
    graph.node_selected.connect(func(node):
        if not rebuilding and host.boss_flow().find(str(node.name)) != null: host.select_flow_node(str(node.name)))
    graph.delete_nodes_request.connect(func(_nodes): Commands.remove(host))
    graph.duplicate_nodes_request.connect(func(): Commands.duplicate_node(host))
    F.note(self, "点选节点 → 右侧属性 · 拖动节点调整排布 · 从输出点连线到下一步")

func rebuild() -> void:
    if graph == null or host.collection not in ["bosses", "behaviors"] or host.current() == null: return
    # 程序重建节点也会触发 Godot 的选中信号，期间不把它当成策划点击。
    rebuilding = true
    _clear_graph()
    var flow = host.boss_flow()
    display_unit = host.theme.default_font_size / 18.0
    var entry = _card("entry", "开始", Vector2(20, 60))
    entry.custom_minimum_size.x = 125 * display_unit
    _label(entry, "进入行为子流程" if host.current() is STGBehaviorFlow else "进入当前血量阶段", "从这里进入当前流程；把开始输出连接到第一步。")
    entry.set_slot(0, false, 0, Color.WHITE, true, 0, Color("55dfbc"))
    var last_y: float = 50
    for definition in flow.nodes:
        last_y = maxf(last_y, definition.editor_position.y)
        _build_flow_card(definition)
    var end = _card("end", "子流程结束" if host.current() is STGBehaviorFlow else "本轮结束", Vector2(250, last_y + 260))
    end.custom_minimum_size.x = 180 * display_unit
    _label(end, "返回调用处" if host.current() is STGBehaviorFlow else "等待攻击收尾", "子流程结束后返回调用处；调用节点的等待设置决定是否等攻击清理。" if host.current() is STGBehaviorFlow else "本轮流程结束后等待已有攻击收尾；后续循环与阶段切换仍由角色配置决定。")
    end.set_slot(0, true, 0, Color("9ab4d0"), false, 0, Color.WHITE)
    var failure_end=_card("failure_end","失败返回",Vector2(560,last_y+260))
    _label(failure_end,"向调用者返回失败","随机尝试可继续下一个候选分支。")
    failure_end.set_slot(0,true,0,Color("ffbf79"),false,0,Color.WHITE)
    _connect_flow(flow)
    _update_actions()
    rebuilding = false
    if last_entry != flow.entry_id or last_count != flow.nodes.size():
        last_entry = flow.entry_id
        last_count = flow.nodes.size()
        request_fit()

func _clear_graph() -> void:
    graph.clear_connections()
    labels.clear()
    displayed_states.clear()
    for child in graph.get_children():
        if child is GraphNode:
            # 先移除以释放节点名，再延迟销毁，避免新节点被 Godot 自动改名。
            graph.remove_child(child)
            child.queue_free()

func _build_flow_card(definition: STGFlowNode) -> void:
    var card = _card(definition.id, definition.title, definition.editor_position)
    _label(card, _summary(definition), "当前节点的行为摘要。点选后在右侧修改参数；\n连线决定后续执行方向，图中位置只用于排版。")
    var outputs = definition.outputs()
    for port in outputs.size():
        var show_output = true
        var caption = _label(card, definition.output_labels()[port] + _terminal_hint(outputs[port]))
        F.help(caption, "这个出口表示“%s”。\n从右侧输出点连接后续节点，或在右侧选择目标；\n连接修改可以撤销。" % definition.output_labels()[port])
        caption.visible = show_output
        var color = Color("ffbf79") if definition.ports()[port].id == "failure" else Color("55dfbc")
        card.set_slot(port + 1, port == 0, 0, Color("9ab4d0"), show_output, 0, color)
    labels[definition.id] = _label(card, "未执行", "当前测试中的节点执行状态，随着预览更新。此文字只用于观察。")
    card.selected = definition.id == host.flow_node_id

func _connect_flow(flow: STGBehaviorFlow) -> void:
    if flow.find(flow.entry_id) != null: graph.connect_node("entry", 0, flow.entry_id, 0)
    for link in flow.links():
        var definition = flow.find(link.from)
        if link.to.is_empty():
            if link.port == 0: graph.connect_node(link.from, link.port, "end", 0)
        elif link.to==STGFlowNode.FAILURE:graph.connect_node(link.from,link.port,"failure_end",0)
        elif link.to==STGFlowNode.SUCCESS:graph.connect_node(link.from,link.port,"end",0)
        elif not STGFlowNode.is_terminal(link.to): graph.connect_node(link.from, link.port, link.to, 0)

func _card(id: String, title: String, at: Vector2) -> GraphNode:
    var node = GraphNode.new()
    node.name = id
    node.title = title
    F.help(node, "点选这个节点，在右侧编辑配置；\n拖动标题只改变流程图排布，不移动战斗中的敌人。" if id not in ["entry", "end", "failure_end"] else "流程的%s标记；通过端点连接行为步骤，\n图中位置只用于排版。" % ("开始" if id == "entry" else "本轮结束"))
    node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    node.position_offset = at * display_unit
    node.custom_minimum_size.x = 250 * display_unit
    node.add_theme_font_size_override("title_font_size", host.theme.default_font_size)
    graph.add_child(node)
    return node

func _label(parent: Node, text: String, description: String = "") -> Label:
    var label = Label.new()
    label.text = text
    F.help(label, description if not description.is_empty() else text)
    parent.add_child(label)
    return label

func _summary(node:STGFlowNode) -> String:
    if node.behavior_preset==null or node.behavior_preset.program==null:return "缺少行为程序声明"
    var p=node.parameters()
    return node.behavior_preset.program.title+"\n前 %.3fs / 执行 %.3fs / 后 %.3fs"%[p.windup,p.execution_duration,p.recovery]

func _terminal_hint(target: String) -> String:
    if target == STGFlowNode.SUCCESS: return " · 完成"
    if target == STGFlowNode.FAILURE: return " · 失败"
    return ""

func request_fit() -> void: fit_frames = 2
func _process(_delta: float) -> void: # Godot 回调：等待容器完成布局，不使用跨越释放的协程。
    if fit_frames < 0: return
    if fit_frames > 0:
        fit_frames -= 1
        return
    fit_frames = -1
    if is_visible_in_tree(): fit_graph(true)

func _exit_tree() -> void: # Godot 回调
    fit_frames = -1
    if is_instance_valid(graph): graph.clear_connections()
    labels.clear()

func fit_graph(prefer_reading: bool = false) -> void:
    var bounds = Rect2()
    var initialized = false
    for child in graph.get_children():
        if child is GraphNode:
            child.reset_size() # Godot 内置：清除布局过程中暂时扩大的尺寸。
            var rect = Rect2(child.position_offset, child.get_combined_minimum_size())
            bounds = bounds.merge(rect) if initialized else rect
            initialized = true
    if not initialized or bounds.size.x <= 0 or bounds.size.y <= 0: return
    # 自动适配保留可读字号；用户点“总览流程”时才允许缩到整个流程都能看见。
    var minimum = maxf(graph.zoom_min, 0.8) if prefer_reading else graph.zoom_min
    graph.zoom = clampf(minf((graph.size.x - 40) / bounds.size.x, (graph.size.y - 70) / bounds.size.y), minimum, 1)
    graph.scroll_offset = bounds.position * graph.zoom - Vector2(20, 50)
    var selected = graph.get_node_or_null(NodePath(host.flow_node_id)) if not host.flow_node_id.is_empty() else null
    if prefer_reading and selected is GraphNode:
        var rect = Rect2(selected.position_offset * graph.zoom - graph.scroll_offset, selected.get_combined_minimum_size() * graph.zoom)
        if not Rect2(Vector2(20, 50), graph.size - Vector2(40, 70)).encloses(rect):
            graph.scroll_offset = (selected.position_offset + selected.get_combined_minimum_size() / 2) * graph.zoom - graph.size / 2

func apply_display(unit: float) -> void:
    if add_menu != null: add_menu.get_popup().theme = host.theme
    if not is_equal_approx(unit, display_unit):
        rebuild()
        request_fit()

func select_node(id: String) -> void:
    rebuilding = true
    for child in graph.get_children():
        if child is GraphNode: child.selected = str(child.name) == id
    rebuilding = false
    _update_actions()

func _update_actions() -> void:
    var node = host.boss_node()
    copy_button.disabled = node == null
    copy_button.tooltip_text = "选中一个节点后复制。" if copy_button.disabled else "复制选中的节点及分支并插入流程；可以独立修改。"
    remove_button.disabled = node == null or host.boss_flow().nodes.size() <= 1
    remove_button.tooltip_text = "先选中一个节点。" if node == null else ("至少保留一个节点。" if remove_button.disabled else "删除选中节点，将前后步骤重新连接；可以撤销。")

func _commit_positions() -> void:
    # GraphEdit 用显示像素定位；制作配置保存未缩放坐标，整次拖动只提交一次。
    var positions = {}
    var flow = host.boss_flow()
    for child in graph.get_children():
        if child is GraphNode:
            var node = flow.find(str(child.name))
            if node != null and not node.editor_position.is_equal_approx(child.position_offset / display_unit): positions[node.id] = child.position_offset / display_unit
    if not positions.is_empty(): Commands.set_positions(host, positions)

func show_states(world) -> void:
    var states: Dictionary = {}
    if world.boss_player != null and world.boss_player.phase_index == host.phase_index: states = world.boss_player.runner.states()
    for id in labels:
        var state: int = states.get(id, -1)
        if displayed_states.get(id, -2) == state: continue
        displayed_states[id] = state
        labels[id].text = ["执行中", "完成", "条件不成立 / 中断"][state] if state >= 0 else "未执行"
        labels[id].add_theme_color_override("font_color", [Color("ffd278"), Color("55dfbc"), Color("ff8394")][state] if state >= 0 else Color("a4b7ca"))

func _refresh_programs() -> void:
    programs=preload("res://addons/stg_maker/authoring/behavior_programs.gd").definitions()
    var menu=add_menu.get_popup();menu.clear()
    for i in programs.size():menu.add_item(programs[i].title,i)

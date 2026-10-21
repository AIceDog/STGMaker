@tool
extends RefCounted
## 属性入口 build/update_context。仅构建当前页，各类资源表单交给对应模块。
const Structure = preload("res://addons/stg_maker/authoring/document_structure.gd")
const Bullet = preload("res://addons/stg_maker/ui/bullet_inspector.gd")
const Barrage = preload("res://addons/stg_maker/ui/barrage_inspector.gd")
const Behavior = preload("res://addons/stg_maker/ui/behavior_inspector.gd")
const Boss = preload("res://addons/stg_maker/ui/boss_inspector.gd")
const Level = preload("res://addons/stg_maker/ui/level_inspector.gd")
const Wave = preload("res://addons/stg_maker/ui/wave_inspector.gd")
const Obstacle = preload("res://addons/stg_maker/ui/obstacle_inspector.gd")
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Library = preload("res://addons/stg_maker/ui/library_ui.gd")

static func build(host) -> void:
    F.close_popups(host.inspector) # 先释放原生弹窗的输入占用，再移除旧表单。
    for child in host.inspector.get_children():
        host.inspector.remove_child(child); child.queue_free() # Godot 内置：先移出布局，再延迟释放。
    host.inspector.set_meta("section_states", host.section_states)
    host.inspector.set_meta("section_context", host.collection + "/" + host.selected_id)
    var resource = host.current()
    var tabs = []
    if resource is STGBulletDefinition: tabs = ["外观与碰撞", "粒子" if resource.form == "moving" else "表现说明"]
    elif resource is STGBarrageSkill: tabs = ["招式参数"]
    elif resource is STGBehaviorFlow: tabs = ["当前节点", "时序 / 动画 / 音频", "流程设置"]
    elif resource is STGBossDefinition: tabs = ["当前节点", "时序 / 动画 / 音频", "阶段 / 美术", "关卡 / 离场"]
    elif resource is STGLevelDefinition: tabs = ["当前出场", "当前阶段", "背景 / 音乐"]
    elif resource is STGWaveDefinition: tabs = ["出场编队"]
    elif resource is STGObstacleDefinition: tabs = ["障碍定义"]
    var key: String = host.collection + "/" + host.selected_id
    if host.inspected_key != key:
        host.inspector_tab = 1 if resource is STGLevelDefinition else 0
        host.inspected_key = key
        host.inspector_scroll.scroll_vertical = 0
    host.inspector_tab = clampi(host.inspector_tab, 0, maxi(0, tabs.size() - 1))
    # 重建页签时暂时阻止 tab_changed，否则控件通知会递归重建属性。
    host.inspector_tabs.set_block_signals(true)
    host.inspector_tabs.clear_tabs()
    for title in tabs: host.inspector_tabs.add_tab(title)
    if resource is STGBossDefinition or resource is STGBehaviorFlow:
        var node = host.boss_node()
        var has_action = node != null
        host.inspector_tabs.set_tab_disabled(1, not has_action)
        host.inspector_tabs.set_tab_tooltip(1, "所有节点共用前摇、定长执行、后摇，以及三段动画与音频。")
        if host.inspector_tab == 1 and not has_action: host.inspector_tab = 0
    if not tabs.is_empty(): host.inspector_tabs.current_tab = host.inspector_tab
    host.inspector_tabs.set_block_signals(false)
    host.inspector_tabs.visible = resource != null
    update_context(host)
    if resource == null: F.note(host.inspector, "从左侧模板开始制作，或打开已有项目。"); return
    var structure_issue = Structure.issue(resource)
    if not structure_issue.is_empty():
        var repair = F.group(host.inspector, "未完成的文档结构")
        F.note(repair, structure_issue + "。草稿已保留原样；补齐后可继续编辑。")
        F.button(repair, "补齐缺失结构（可撤销）", host.repair_document_structure)
        return
    if host.inspector_tab == 0 and not resource is STGBossDefinition and not resource is STGLevelDefinition and not resource is STGBarrageSkill and not resource is STGBulletDefinition: F.text(host.inspector, "名称", resource.title, R.setter(host, [], "title"))
    if resource is STGBulletDefinition: Bullet.build(host, host.inspector, resource)
    elif resource is STGBarrageSkill: Barrage.build(host, host.inspector, resource)
    elif resource is STGBehaviorFlow: Behavior.build(host, host.inspector, resource)
    elif resource is STGBossDefinition: Boss.build(host, host.inspector, resource)
    elif resource is STGLevelDefinition: Level.build(host, host.inspector, resource)
    elif resource is STGWaveDefinition: Wave.build(host, host.inspector, resource)
    elif resource is STGObstacleDefinition: Obstacle.build(host, host.inspector, resource)

static func update_context(host) -> void:
    var resource = host.current()
    host.inspector_caption.text = Library.TITLES[host.collection]
    if resource == null: host.subtitle.text = "从模板开始 → 调整参数 → 测试 → 保存项目"; return
    var summary = ""
    if resource is STGBulletDefinition:
        summary = Bullet.FORM_NAMES[resource.form] + "素材 · 外观、碰撞与表现"
    elif resource is STGBarrageSkill:
        summary = "招式程序与开放参数"
    elif resource is STGBehaviorFlow: summary = "%d 个行为节点" % resource.nodes.size()
    elif resource is STGBossDefinition: summary = "%d 个血量阶段 · 点击流程节点编辑" % resource.phases.size()
    elif resource is STGLevelDefinition: summary = "%d 个阶段 · 完整时间轴安排出场" % resource.segments.size()
    elif resource is STGWaveDefinition: summary = "%d 个实体 · 配置数量、排列与出场间隔" % resource.count
    elif resource is STGObstacleDefinition: summary = "可复用障碍 · 外形与离场规则"
    host.subtitle.text = "正在编辑「%s」 · %s" % [resource.title, summary]
    F.help(host.subtitle, host.subtitle.text + "\n这是当前选择的摘要；在右侧调整参数。")
    host.Context.update(host)

static func sync_values(host) -> void:
    Barrage.sync(host)
    if host.collection in ["bosses","behaviors"] and host.boss_node()!=null:
        preload("res://addons/stg_maker/ui/attack_parameter_fields.gd").sync(host.inspector,host.boss_node().parameters())
    # 数值页保持实例及焦点。撤销/重做和关联字段同步不能再次触发编辑事务。
    _sync_node(host, host.inspector)

static func _sync_node(host, node: Node) -> void:
    if node is BaseButton and node.has_meta("refresh_disabled"):node.disabled=node.get_meta("refresh_disabled").call()
    if node is Label and node.has_meta("refresh_text"): node.text = node.get_meta("refresh_text").call()
    if not node.has_meta("program_parameter") and node.has_meta("config_scope") and node.has_meta("config_field"):
        var owner = host.config_at(node.get_meta("config_scope"))
        if owner != null:
            var value = owner.get(node.get_meta("config_field"))
            if node.has_meta("config_axis") and value is Vector2: value = value[int(node.get_meta("config_axis"))]
            if node is SpinBox and (value is float or value is int): node.set_value_no_signal(value)
            elif node is CheckButton and value is bool: node.set_pressed_no_signal(value)
            elif node is OptionButton and node.has_meta("config_keys"): node.select(node.get_meta("config_keys").find(value))
            elif node is ColorPickerButton and value is Color:
                node.set_block_signals(true); node.color = value; node.set_block_signals(false)
            elif node is LineEdit and value is String:
                if node.text != value:
                    node.set_block_signals(true); node.text = value; node.set_block_signals(false)
                node.set_meta("committed", value)
    for child in node.get_children(): _sync_node(host, child)

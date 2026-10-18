@tool
extends RefCounted
## 上下级编辑导航。保存的是选择与滚动位置，不是游戏配置，也不进入撤销历史。
var parents: Array[Dictionary] = []

func open_reference(host, collection: String, id: String) -> void:
	if host.session.project.find(collection, id) == null: host.message("引用的资源不存在，请先更换引用。"); return
	parents.append({"collection": host.collection, "id": host.selected_id,
		"stage": host.stage_index, "flow_path": host.flow_path.duplicate(), "phase": host.phase_index,
		"node": host.flow_node_id, "tab": host.inspector_tab, "scroll": host.inspector_scroll.scroll_vertical,
		"segment": host.segment_index, "event": host.event_id, "background": host.background_index})
	host.show_collection(collection, id)

func go_back(host) -> void:
	# 上级可能在撤销后消失：跳过已失效的导航项，不创建新的资源。
	while not parents.is_empty():
		var page = parents.pop_back()
		if host.session.project.find(page.collection, page.id) == null: continue
		host.show_collection(page.collection, page.id)
		host.stage_index = page.stage; host.flow_path = page.flow_path.duplicate()
		host.phase_index = page.phase; host.flow_node_id = page.node; host.inspector_tab = page.tab
		host.segment_index = page.segment; host.event_id = page.event; host.background_index = page.background
		host.refresh(true)
		host.inspector_scroll.set_deferred("scroll_vertical", page.scroll)
		break
	refresh(host)

func refresh(host) -> void:
	host.back_button.visible = not parents.is_empty()
	host.context_row.visible = not parents.is_empty()
	if parents.is_empty(): return
	var page = parents[-1]
	var resource = host.session.project.find(page.collection, page.id)
	host.back_button.text = "← 返回「%s」" % resource.title if resource != null else "← 返回上一级"
	host.back_button.tooltip_text = host.back_button.text + "\n返回原来的节点 / 阶段，保留本次修改。"

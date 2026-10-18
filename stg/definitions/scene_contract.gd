@tool
extends RefCounted
## 表现场景结构查询，不推进任何运行状态。
static func presentation_issue(scene: PackedScene, animation: String) -> String:
	if scene == null: return ""
	if not scene.can_instantiate(): return "表现场景无法创建"
	var visual = scene.instantiate()
	var issue = ""
	if not visual is Node2D: issue = "动画 / 粒子场景根节点需要 Node2D"
	elif not animation.is_empty():
		var player = find_player(visual)
		if player == null or not player.has_animation(animation): issue = "表现场景缺少动画：" + animation
	visual.free()
	return issue

static func find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = find_player(child)
		if found != null:
			return found
	return null


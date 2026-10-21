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


## 发射/命中必须有限；运行粒子可以连续发射，停止时自然排空。
static func particles_issue(scene: PackedScene, finite: bool) -> String:
	if scene == null: return ""
	if not scene.can_instantiate(): return "粒子场景无法创建"
	var root = scene.instantiate()
	var issues: Array[String] = []
	if not root is Node2D: issues.append("粒子场景根节点需要 Node2D")
	var count = 0
	for node in [root] + root.find_children("*", "Node", true, false):
		if node is CPUParticles2D or node is GPUParticles2D:
			count += 1
			var location = str(root.get_path_to(node))
			if finite and not node.one_shot: issues.append(location + "：发射/命中粒子必须启用 One Shot")
			if not is_finite(node.lifetime) or node.lifetime <= 0 or not is_finite(node.speed_scale) or node.speed_scale <= 0: issues.append(location + "：粒子寿命与速度倍率必须为有限正数")
		elif finite and node is AnimationPlayer and not node.autoplay.is_empty() and node.has_animation(node.autoplay):
			if not is_finite(node.speed_scale) or node.speed_scale <= 0: issues.append(str(root.get_path_to(node)) + "：事件粒子的自动动画速度必须为有限正数")
			if node.get_animation(node.autoplay).loop_mode != Animation.LOOP_NONE: issues.append(str(root.get_path_to(node)) + "：事件粒子的自动动画不能循环")
	if count == 0: issues.append("粒子场景中没有 CPU/GPU 粒子节点")
	root.free()
	return "；".join(issues)

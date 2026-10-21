@tool
extends Node2D
## 粒子只随战斗步长推进；生命周期来自美术资源，不使用额外保留秒数。
var animations: Array[AnimationPlayer] = []
var particles: Array[Dictionary] = []
var draining: bool = false

func configure(scene: PackedScene, animation: String = "") -> void:
	var visual = scene.instantiate()
	_collect(visual, animation)
	add_child(visual)
	for player in animations:
		var selected: String = player.get_meta("material_animation")
		player.stop()
		if not selected.is_empty() and player.has_animation(selected):
			player.play(selected)
			player.advance(0)
	if particles.any(func(entry): return entry.node is GPUParticles2D):
		RenderingServer.frame_pre_draw.connect(_flush_gpu_particles)

func _collect(node: Node, animation: String) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is AnimationPlayer:
		var selected: String = animation if animations.is_empty() and not animation.is_empty() else node.autoplay
		node.set_meta("material_animation", selected)
		node.autoplay = ""
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animations.append(node)
	elif node is GPUParticles2D or node is CPUParticles2D:
		var entry = {"node": node, "speed": node.speed_scale, "age": 0.0, "residual_age": 0.0, "active_time": 0.0, "residual_time": 0.0, "done": not node.emitting}
		particles.append(entry)
		node.speed_scale = 0
		# 多个发射器各自完成后才回收根节点；无渲染时也按相同资源时长结束。
		node.finished.connect(func(): entry.done = true)
	for child in node.get_children(): _collect(child, animation)

func set_emitting(enabled: bool) -> void:
	if enabled: return # 不能每帧把已结束的一次性发射器重新开启。
	draining = true
	for entry in particles:
		if is_instance_valid(entry.node):
			entry.node.emitting = false
	for player in animations: player.stop()

func tick(dt: float) -> void:
	for player in animations:
		if is_instance_valid(player) and player.is_playing(): player.advance(dt)
	for entry in particles:
		if not is_instance_valid(entry.node) or entry.done: continue
		var seconds: float = dt * entry.speed
		entry.age += seconds
		if draining:
			entry.residual_age += seconds
			entry.done = entry.residual_age + 0.000001 >= _tail(entry.node)
		elif entry.node.one_shot:
			# 最后一批出生到最后一颗消失的上界，包含粒子拖带，不依赖渲染帧数。
			entry.done = entry.age + 0.000001 >= entry.node.lifetime * (1.0 - entry.node.explosiveness) + _tail(entry.node)
		if entry.node is GPUParticles2D:
			entry["active_time" if not draining else "residual_time"] += seconds
		elif not draining: entry.node.request_particles_process(seconds)
		else: entry.node.request_particles_process(0, seconds)

static func _tail(node: Node) -> float:
	return node.lifetime + (node.trail_lifetime if node is GPUParticles2D and node.trail_enabled else 0.0)

func is_finished() -> bool:
	return particles.all(func(entry): return entry.done or not is_instance_valid(entry.node)) and animations.all(func(player): return not is_instance_valid(player) or not player.is_playing())

func _flush_gpu_particles() -> void:
	for entry in particles:
		if not is_instance_valid(entry.node) or not entry.node is GPUParticles2D: continue
		if entry.active_time > 0 or entry.residual_time > 0:
			entry.node.request_particles_process(entry.active_time, entry.residual_time)
			entry.active_time = 0.0
			entry.residual_time = 0.0

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_flush_gpu_particles):
		RenderingServer.frame_pre_draw.disconnect(_flush_gpu_particles)

func place(actor) -> void:
	transform = actor.definition.visual.geometry.local_transform()
	scale *= actor.visual_scale
	position *= actor.visual_scale
	modulate = actor.definition.visual.color

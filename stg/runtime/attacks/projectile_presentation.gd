@tool
extends Node2D
## 所有素材共用的表现实例。动画与粒子只随战斗步长推进，暂停和重播不另开时钟。
var animations: Array[AnimationPlayer] = []
var particles: Array[Dictionary] = []

func configure(scene: PackedScene, animation: String) -> void:
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
	# 美术场景中的动画、粒子由正式模拟更新；不执行额外 _process / _physics_process。
	node.set_process(false)
	node.set_physics_process(false)
	if node is AnimationPlayer:
		var selected: String = animation if animations.is_empty() and not animation.is_empty() else node.autoplay
		node.set_meta("material_animation", selected)
		node.autoplay = ""
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animations.append(node)
	elif node is GPUParticles2D or node is CPUParticles2D:
		particles.append({"node": node, "emits": node.emitting, "speed": node.speed_scale, "active_time": 0.0, "residual_time": 0.0})
		node.speed_scale = 0
	for child in node.get_children(): _collect(child, animation)

func set_emitting(enabled: bool) -> void:
	for entry in particles:
		if is_instance_valid(entry.node): entry.node.emitting = enabled and entry.emits

func tick(dt: float) -> void:
	for player in animations:
		if is_instance_valid(player) and player.is_playing(): player.advance(dt)
	for entry in particles:
		if not is_instance_valid(entry.node): continue
		var seconds: float = dt * entry.speed
		if entry.node is GPUParticles2D:
			# GPU 请求在渲染帧才执行；累计该帧的全部固定步长，避免最后一次请求覆盖前面的时间。
			entry["active_time" if entry.node.emitting else "residual_time"] += seconds
		elif entry.node.emitting: entry.node.request_particles_process(seconds)
		else: entry.node.request_particles_process(0, seconds)

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
	modulate = actor.definition.visual.color * Color(1, 1, 1, actor.opacity())
	if actor.definition.form == "trail":
		# 拖尾本体保持战斗原点，表现场景跟随实际采样位置，段的贴图仍由拖尾绘制器负责。
		position += actor.last_emitter

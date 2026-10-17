@tool
extends RefCounted
## 子弹、激光、拖尾、区域并列；素材保存静态外观、碰撞和表现引用。
const R = preload("res://addons/stg_maker/ui/resource_fields.gd")
const F = preload("res://addons/stg_maker/ui/fields.gd")
const Defaults = preload("res://addons/stg_maker/authoring/defaults.gd")
const KINDS = ["circle", "diamond", "rectangle", "triangle", "polygon", "ring", "sector"]
const NAMES = ["圆形", "菱形", "矩形", "三角形", "自定义多边形", "圆环", "扇形"]
const FORM_NAMES = {"moving": "子弹", "laser": "激光", "trail": "拖尾", "area": "区域"}
const Scenes = preload("res://stg/definitions/scene_contract.gd")

static func build(host, parent, material: STGBulletDefinition) -> void:
	match host.inspector_tab:
		0:
			F.note(parent, "素材类型：" + FORM_NAMES[material.form])
			_visual(host, parent, material)
			_collision(host, parent, material)
			_type_settings(host, parent, material)
		1: _presentation(host, parent, material)

static func _visual(host, parent, material: STGBulletDefinition) -> void:
	var group = F.section(parent, "外观")
	var visual = material.visual
	var current = "texture" if visual.mode == "texture" else visual.geometry.kind
	F.select(group, "形状", current, KINDS + ["texture"], NAMES + ["贴图"], func(value):
		R.edit(host, ["visual"], func(target, _project):
			target.mode = "texture" if value == "texture" else "geometry"
			if value != "rectangle": target.geometry.along_beam = false
			if value != "texture":
				target.texture = null
				for key in ["spawn_clip", "run_clip", "hit_clip", "expire_clip"]: target.set(key, null)
				target.geometry.kind = value))
	if visual.mode == "texture":
		if material.form in ["moving", "laser"]: _texture_animation(host, group, material)
		else: R.asset(host, group, "texture", "自定义贴图", visual.texture, ["visual"])
	_geometry(host, group, material, visual.geometry, ["visual", "geometry"], visual.mode != "texture")
	F.label(group, "颜色")
	var tint = ColorPickerButton.new()
	tint.color = visual.color
	group.add_child(tint)
	F.help(tint, "外形颜色：几何图形直接填色，贴图按这个颜色染色。修改会影响所有引用这份素材的招式。")
	R.locate(tint, ["visual"], "color")
	tint.color_changed.connect(R.setter(host, ["visual"], "color"))
	F.note(group, "旋转与偏移使用弹体局部坐标，只改变外观，不改变飞行方向或碰撞形状。")

static func _collision(host, parent, material: STGBulletDefinition) -> void:
	var group = F.section(parent, "碰撞")
	F.select(group, "形状", material.collision.kind, KINDS, NAMES, func(value):
		R.edit(host, ["collision"], func(target, _project):
			target.kind = value
			if value != "rectangle": target.along_beam = false))
	F.button(group, "复制当前外观几何", func(): host.edit_path([], "collision", host.current().visual.geometry.duplicate(true), true))
	_geometry(host, group, material, material.collision, ["collision"])
	F.note(group, "碰撞与外观独立。圆环空洞、扇形开口和自由多边形凹口均保留；贴图本身不参与命中判定。")
	F.note(group, "伤害、命中频率与命中后的声音、特效、追加招式在招式页配置。")

static func _geometry(host, box, material: STGBulletDefinition, geometry: STGBulletGeometry, scope: Array, show_kind_parameters: bool = true) -> void:
	var size_label = "段长 / 宽" if material.form == "trail" else "大小"
	if material.form == "laser" and geometry.along_beam: size_label = "长 / 宽"
	R.vector_inline(host, box, scope, geometry, "size", size_label, 0.001, 10000, 0.001)
	if material.form == "laser" and geometry.kind == "rectangle" and show_kind_parameters:
		F.toggle(box, "沿激光路径延伸", geometry.along_beam, R.setter(host, scope, "along_beam", true))
	R.number(host, box, scope, geometry, "rotation_degrees", "局部旋转 °", -3600, 3600)
	R.vector_inline(host, box, scope, geometry, "offset", "局部偏移")
	if show_kind_parameters:
		if geometry.kind == "polygon":
			if geometry.polygon_mode == "regular":
				R.number(host, box, scope, geometry, "sides", "边数", 3, 64, 1)
			else:
				F.note(box, "使用素材提供的自定义轮廓；大小、旋转和偏移作用于整条轮廓。")
				F.button(box, "改用正多边形", func(): host.edit_path(scope, "polygon_mode", "regular", true))
		elif geometry.kind == "ring": R.number(host, box, scope, geometry, "inner_ratio", "内径 / 外径", 0, 0.999, 0.01)
		elif geometry.kind == "sector": R.number(host, box, scope, geometry, "sector_angle", "扇形角度 °", 1, 360)

static func _type_settings(host, parent, material: STGBulletDefinition) -> void:
	if material.form == "laser":
		var structure = F.section(parent, "激光路径")
		F.toggle(structure, "曲线激光", material.beam_path != null, func(value):
			R.edit(host, [], func(target, _project):
				target.beam_path = Defaults.path([Vector2.ZERO, Vector2(150, 50), Vector2(260, 0)]) if value else null
				target.beam_path_size = target.visual.geometry.size))
		if material.beam_path != null: F.button(structure, "编辑激光曲线", func(): host.edit_beam = true; host.set_tool("path"))
		F.note(structure, "矩形可以显式选择沿激光路径延伸；关闭后仍使用独立的居中矩形。")
	elif material.form == "trail":
		var sampling = F.section(parent, "拖尾路径")
		R.number(host, sampling, [], material, "trail_offset", "离发射者尾部距离", 0, 200)
		R.number(host, sampling, [], material, "trail_spacing", "采样间距", 1, 100)
		R.number(host, sampling, [], material, "trail_break_distance", "瞬移断线距离", 1, 2000)
		F.note(sampling, "沿发射者实际走过的路径采样。每段生效时长、预警和淡出在招式中设置。")

static func _texture_animation(host, parent, material: STGBulletDefinition) -> void:
	var visual = material.visual
	var box = F.section(parent, "贴图与阶段动画")
	R.asset(host, box, "run_clip" if visual.run_clip != null else "texture", "运行中（静态图 / GIF）", visual.run_clip if visual.run_clip != null else visual.texture, ["visual"], true)
	var phases = [["spawn_clip", "刚发射 / 前摇"], ["hit_clip", "碰撞 / 命中"], ["expire_clip", "未命中消失 / 后摇"]]
	if material.form == "laser": phases = [["spawn_clip", "攻击前摇"], ["expire_clip", "攻击后摇"]]
	for phase in phases: R.asset(host, box, phase[0], phase[1], visual.get(phase[0]), ["visual"], true)
	F.note(box, "选择静态图片、GIF 或已保存的帧动画。GIF 保留逐帧时长，运行中循环；其他阶段可不填。前摇与后摇动画适配招式中设置的时间。")

static func _presentation(host, parent, material: STGBulletDefinition) -> void:
	if material.form == "moving":
		var particles = F.section(parent, "子弹粒子")
		for phase in [["spawn_particles", "刚发射粒子"], ["run_particles", "运行中粒子"], ["hit_particles", "命中后粒子"]]:
			R.asset(host, particles, phase[0], phase[1], material.get(phase[0]))
		R.number(host, particles, [], material, "particle_duration", "发射 / 命中粒子保留 s", 0.01, 60)
		F.note(particles, "所有普通子弹形状均可使用粒子。运行粒子跟随弹体，发射与命中粒子留在事件发生位置。")
	elif material.form == "laser": F.note(parent, "激光的前摇、攻击中、后摇由招式节奏驱动；当前不提供激光粒子配置。")
	var group = F.fold(parent, "表现扩展（技术策划）", material.visual_scene != null, "bullet.presentation")
	R.asset(host, group, "visual_scene", "表现场景", material.visual_scene)
	F.note(group, "可选 Node2D 表现扩展；普通贴图动画在外观中配置，普通子弹粒子在上方分阶段配置。")
	if material.visual_scene != null:
		F.toggle(group, "同时显示基础外观", material.show_base_visual, R.setter(host, [], "show_base_visual", true))
		var instance = material.visual_scene.instantiate()
		var player = Scenes.find_player(instance)
		var keys: Array = [""]
		var names: Array = ["使用场景自动播放设置"]
		if player != null:
			for animation in player.get_animation_list():
				if animation == "RESET": continue
				keys.append(str(animation))
				names.append(str(animation))
		instance.free()
		var selector = F.select(group, "播放动画", material.visual_animation, keys, names, R.setter(host, [], "visual_animation"))
		R.locate(selector, [], "visual_animation")
	var advanced = F.fold(parent, "运行扩展", false, "bullet.runtime")
	R.asset(host, advanced, "scene", "运行场景", material.scene)
	F.note(advanced, "技术策划替换弹体运行节点时使用。运行扩展仍遵守同一套发射和生命周期协议。")

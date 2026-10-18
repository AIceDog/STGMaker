@tool
extends RefCounted
## 原生 SpriteFrames 的只读查询。每个阶段使用 default 动画，实例自己持有播放时间。
const ANIMATION = &"default"

static func duration(frames: SpriteFrames) -> float:
	if frames == null or not frames.has_animation(ANIMATION): return 0.0
	var speed = frames.get_animation_speed(ANIMATION)
	if speed <= 0: return 0.0
	var seconds = 0.0
	for i in frames.get_frame_count(ANIMATION): seconds += frames.get_frame_duration(ANIMATION, i) / speed
	return seconds

static func texture_at(frames: SpriteFrames, seconds: float, loop: bool = false) -> Texture2D:
	if frames == null or not frames.has_animation(ANIMATION): return null
	var count = frames.get_frame_count(ANIMATION)
	if count == 0: return null
	var total = duration(frames)
	var remaining = fposmod(seconds, total) if loop and total > 0 else maxf(0, seconds)
	var speed = frames.get_animation_speed(ANIMATION)
	if speed <= 0: return null
	for i in count:
		var span = frames.get_frame_duration(ANIMATION, i) / speed
		if remaining < span: return frames.get_frame_texture(ANIMATION, i)
		remaining -= span
	return frames.get_frame_texture(ANIMATION, count - 1)

static func validate(frames: SpriteFrames) -> PackedStringArray:
	var issues = PackedStringArray()
	if frames == null or not frames.has_animation(ANIMATION): return PackedStringArray(["阶段动画需要 default 动画。"])
	var count = frames.get_frame_count(ANIMATION)
	if count == 0 or count > 512: issues.append("阶段动画需要 1～512 帧。")
	var speed = frames.get_animation_speed(ANIMATION)
	if not is_finite(speed) or speed <= 0: issues.append("动画速度必须大于零。")
	for i in count:
		if frames.get_frame_texture(ANIMATION, i) == null: issues.append("动画包含空贴图帧。")
		var span = frames.get_frame_duration(ANIMATION, i)
		if not is_finite(span) or span <= 0: issues.append("动画帧时长必须大于零。")
	return issues

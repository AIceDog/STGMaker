@tool
extends RefCounted
## GIF87a/89a 导入：调色板、LZW、交错行、透明与 disposal 2/3。
## 导入后保存普通贴图帧，不把解码器带入成品。规范：https://www.w3.org/Graphics/GIF/spec-gif89a.txt
const MAX_PIXELS = 16777216 # 全部合成帧的像素上限，避免大动图阻塞制作界面。
const MAX_FRAMES = 512
var data: PackedByteArray
var cursor: int = 0
var issue: String = ""

func load_clip(path: String) -> Dictionary:
	data = FileAccess.get_file_as_bytes(path)
	cursor = 0
	issue = ""
	if data.size() < 13 or data.size() > 67108864: return {"issue": "GIF 文件为空、损坏或超过 64 MB。"}
	var header = data.slice(0, 6).get_string_from_ascii()
	if header not in ["GIF87a", "GIF89a"]: return {"issue": "不是有效的 GIF 文件。"}
	cursor = 6
	var width = _word()
	var height = _word()
	var flags = _byte()
	var background_index = _byte()
	_byte()
	if width <= 0 or height <= 0 or width > 2048 or height > 2048: return {"issue": "GIF 尺寸需在 1～2048 像素内。"}
	var global_palette = _palette(1 << ((flags & 7) + 1)) if flags & 128 else []
	var background: Color = global_palette[background_index] if background_index < global_palette.size() else Color(0, 0, 0, 0)
	var canvas = Image.create(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var clip = SpriteFrames.new()
	clip.resource_name = path.get_file()
	clip.set_animation_speed(&"default", 1.0)
	var delay = 0.1
	var disposal = 0
	var transparent = -1
	var trailer = false
	while cursor < data.size() and issue.is_empty():
		var marker = _byte()
		if marker == 0x3b:
			trailer = true
			break
		if marker == 0x21:
			var label = _byte()
			if label == 0xf9:
				if _byte() != 4: issue = "GIF 图形控制块损坏。"; break
				var control = _byte()
				disposal = (control >> 2) & 7
				delay = maxf(0.01, _word() / 100.0) # 零时长至少占一百分之一秒。
				var index = _byte()
				transparent = index if control & 1 else -1
				if _byte() != 0 or disposal > 3: issue = "GIF 图形控制参数无效。"; break
			else:
				_subblocks()
				if label == 1: issue = "当前不导入 GIF 的纯文本绘制块，请转换为图像帧。"
			continue
		if marker != 0x2c: issue = "GIF 包含无效的数据块。"; break
		var x = _word()
		var y = _word()
		var w = _word()
		var h = _word()
		var image_flags = _byte()
		if w <= 0 or h <= 0 or x + w > width or y + h > height: issue = "GIF 帧超出画布。"; break
		if (clip.get_frame_count(&"default") + 1) * width * height > MAX_PIXELS: issue = "GIF 总帧像素超过 1600 万，请缩小尺寸或减少帧数。"; break
		if clip.get_frame_count(&"default") >= MAX_FRAMES: issue = "GIF 超过 512 帧，请减少帧数。"; break
		var palette = _palette(1 << ((image_flags & 7) + 1)) if image_flags & 128 else global_palette
		var code_size = _byte()
		var compressed = _subblocks()
		if not issue.is_empty(): break
		var pixels = _lzw(compressed, code_size, w * h)
		if not issue.is_empty(): break
		if palette.is_empty(): issue = "GIF 缺少调色板。"; break
		if clip.get_frame_count(&"default") == 0: canvas.fill(Color(0, 0, 0, 0) if transparent >= 0 else background)
		var before = canvas.duplicate() if disposal == 3 else null
		var rows: Array[int] = []
		if image_flags & 64:
			for pass_index in 4:
				for row in range([0, 4, 2, 1][pass_index], h, [8, 8, 4, 2][pass_index]): rows.append(row)
		else:
			for row in h: rows.append(row)
		for row_index in h:
			for column in w:
				var index = pixels[row_index * w + column]
				if index == transparent: continue
				if index >= palette.size(): issue = "GIF 像素引用了无效的颜色。"; break
				canvas.set_pixel(x + column, y + rows[row_index], palette[index])
			if not issue.is_empty(): break
		if not issue.is_empty(): break
		# 直接保存原生无损纹理数据，不依赖运行期 GPU 纹理回读来序列化素材。
		var texture = PortableCompressedTexture2D.new()
		texture.keep_compressed_buffer = true
		texture.create_from_image(canvas, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		clip.add_frame(&"default", texture, delay)
		if disposal == 2: canvas.fill_rect(Rect2i(x, y, w, h), Color(0, 0, 0, 0) if transparent >= 0 else background)
		elif disposal == 3: canvas = before
		delay = 0.1
		disposal = 0
		transparent = -1
	if issue.is_empty() and (clip.get_frame_count(&"default") == 0 or not trailer): issue = "GIF 缺少图像帧或结束标记。"
	return {"issue": issue, "clip": clip if issue.is_empty() else null}

func _byte() -> int:
	if cursor >= data.size(): issue = "GIF 文件意外结束。"; return 0
	var value = data[cursor]
	cursor += 1
	return value

func _word() -> int:
	var low = _byte()
	return low | (_byte() << 8)

func _palette(count: int) -> Array[Color]:
	var result: Array[Color] = []
	for i in count:
		var r = _byte()
		var g = _byte()
		var b = _byte()
		result.append(Color8(r, g, b))
	return result

func _subblocks() -> PackedByteArray:
	var result = PackedByteArray()
	while issue.is_empty():
		var count = _byte()
		if count == 0: break
		if cursor + count > data.size(): issue = "GIF 子块长度无效。"; break
		result.append_array(data.slice(cursor, cursor + count))
		cursor += count
	return result

func _lzw(bytes: PackedByteArray, minimum: int, expected: int) -> PackedByteArray:
	var output = PackedByteArray()
	if minimum < 2 or minimum > 8: issue = "GIF LZW 码宽无效。"; return output
	var clear = 1 << minimum
	var end = clear + 1
	var dictionary: Array[PackedByteArray] = []
	dictionary.resize(4096)
	for i in clear: dictionary[i] = PackedByteArray([i])
	var width = minimum + 1
	var next = end + 1
	var bit = 0
	var previous = PackedByteArray()
	var ended = false
	while bit + width <= bytes.size() * 8:
		var code = 0
		for offset in width: code |= ((bytes[(bit + offset) >> 3] >> ((bit + offset) & 7)) & 1) << offset
		bit += width
		if code == clear:
			width = minimum + 1
			next = end + 1
			previous = PackedByteArray()
			continue
		if code == end: ended = true; break
		var entry = PackedByteArray()
		if code < next: entry = dictionary[code]
		elif code == next and not previous.is_empty():
			entry = previous.duplicate()
			entry.append(previous[0])
		if entry.is_empty() or output.size() + entry.size() > expected: issue = "GIF LZW 数据损坏。"; return output
		output.append_array(entry)
		if not previous.is_empty() and next < 4096:
			var added = previous.duplicate()
			added.append(entry[0])
			dictionary[next] = added
			next += 1
			if next == 1 << width and width < 12: width += 1
		previous = entry
	if not ended or output.size() != expected: issue = "GIF LZW 像素数量不完整。"
	return output

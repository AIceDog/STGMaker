@tool
extends RefCounted
## 补充 GDScript 文本中的静态相对引用；原生 get_dependencies 不完整报告普通 .gd 预加载。
static func collect(source: String, text: String) -> Array[String]:
	var result: Array[String] = []
	var literals: Array[String] = []
	var tokens = _tokens(text)
	for index in tokens.size():
		if tokens[index].kind != "name": continue
		var name: String = tokens[index].text
		if name == "extends" and index + 1 < tokens.size() and tokens[index + 1].kind == "string":
			literals.append(tokens[index + 1].text)
		elif name in ["preload", "load"] and index + 3 < tokens.size() and tokens[index + 1].text == "(" and tokens[index + 2].kind == "string" and tokens[index + 3].text in [")", ","]:
			literals.append(tokens[index + 2].text)
	var include = RegEx.new()
	include.compile('(?m)^\\s*#include\\s+["\']([^"\']+)["\']')
	for found in include.search_all(text): literals.append(found.get_string(1))
	for path in literals:
		if path.begins_with("user://"): continue # 玩家存档在运行时读取，不属于制作依赖。
		if path.begins_with("uid://"):
			var identifier = ResourceUID.text_to_id(path)
			if ResourceUID.has_id(identifier): path = ResourceUID.get_id_path(identifier)
		elif not path.is_absolute_path():
			path = source.get_base_dir().path_join(path)
		path = path.simplify_path()
		if not result.has(path): result.append(path)
	return result

## 只识别依赖声明需要的词法单元；注释、普通字符串和动态拼接不会被当成调用。
static func _tokens(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var index = 0
	while index < text.length():
		var character = text[index]
		if character in [" ", "\t", "\r", "\n"]: index += 1; continue
		if character == "#":
			while index < text.length() and text[index] != "\n": index += 1
			continue
		if character in ['"', "'"]:
			var delimiter = character.repeat(3) if text.substr(index, 3) == character.repeat(3) else character
			index += delimiter.length()
			var start = index
			while index < text.length() and text.substr(index, delimiter.length()) != delimiter:
				index += 2 if text[index] == "\\" else 1
			var value = text.substr(start, index - start).c_unescape()
			result.append({"kind": "string", "text": value})
			index += delimiter.length()
		elif _word(character):
			var start = index
			while index < text.length() and _word(text[index]): index += 1
			result.append({"kind": "name", "text": text.substr(start, index - start)})
		else:
			result.append({"kind": "symbol", "text": character})
			index += 1
	return result

static func _word(character: String) -> bool:
	var code = character.unicode_at(0)
	return character == "_" or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

static func identifiers(text: String) -> Dictionary:
	var result = {}
	for token in _tokens(text):
		if token.kind == "name": result[token.text] = true
	return result

static func without_comments(text: String) -> String:
	var result = ""
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#include "): result += line + "\n"; continue
		var quote = ""
		var escaped = false
		var end = line.length()
		for index in line.length():
			var character = line[index]
			if escaped: escaped = false; continue
			if character == "\\" and not quote.is_empty(): escaped = true; continue
			if not quote.is_empty():
				if character == quote: quote = ""
			elif character in ['"', "'"]: quote = character
			elif character == "#": end = index; break
		result += line.left(end) + "\n"
	return result

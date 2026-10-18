@tool
extends RefCounted
## 构建与架构检查共用方向约束；数据可引用运行场景，不能引用制作代码。
static func editor_only(path: String) -> bool:
	var relative = path.trim_prefix("res://").simplify_path()
	return relative.begins_with("addons/") or relative.begins_with("tools/") or relative.begins_with("tests/")

static func issue(source: String, target: String) -> String:
	source = source.trim_prefix("res://")
	target = target.trim_prefix("res://").simplify_path()
	if source.begins_with("stg/") and editor_only(target): return "运行框架依赖了制作代码"
	if source.begins_with("stg/") and target.begins_with("game/"): return "运行框架依赖了具体游戏内容"
	if source.begins_with("stg/api/") and target.begins_with("stg/runtime/"): return "公开 API 依赖了运行器内部实现"
	if source.begins_with("stg/definitions/") and target.begins_with("stg/runtime/") and target.ends_with(".gd"): return "配置定义依赖了运行脚本"
	if source.begins_with("game/extensions/") and (editor_only(target) or target.begins_with("stg/runtime/")): return "游戏扩展绕过了公开 API"
	return ""

static func check_source(source: String, text: String) -> PackedStringArray:
	var issues: PackedStringArray = []
	var pattern = RegEx.new()
	pattern.compile('["\'](res://[^"\']+)["\']')
	var code = preload("res://addons/stg_maker/build/script_dependencies.gd").without_comments(text)
	for found in pattern.search_all(code):
		var target = found.get_string(1)
		var problem = issue(source, target)
		if not problem.is_empty(): issues.append("%s → %s：%s" % [source, target, problem])
	for target in preload("res://addons/stg_maker/build/script_dependencies.gd").collect("res://" + source.trim_prefix("res://"), text):
		var problem = issue(source, target)
		if not problem.is_empty(): issues.append("%s → %s：%s" % [source, target, problem])
	# 全局类型也会形成隐式依赖，不能只检查 preload/load 的字符串。
	var names = preload("res://addons/stg_maker/build/script_dependencies.gd").identifiers(text)
	for entry in ProjectSettings.get_global_class_list():
		var problem = issue(source, entry.path)
		if not problem.is_empty() and names.has(entry.class):
			issues.append(source + "：" + problem + "（" + str(entry.class) + "）")
	return issues

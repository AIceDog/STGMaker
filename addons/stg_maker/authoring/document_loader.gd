@tool
extends RefCounted
## 当前资产文档读取；版本在加载脚本依赖前检查，不提供转换或路径重定向。
static func library(path: String) -> Dictionary:
	var result = {"resource": null, "path": path, "issue": ""}
	if not FileAccess.file_exists(path):
		result.issue = "项目文件不存在：" + path
		return result
	if path.get_extension().to_lower() != "tres":
		result.issue = "资源库应为当前格式的 .tres 索引。"
		return result
	var text = FileAccess.get_file_as_string(path)
	var root = text.rfind("[resource]")
	var version = RegEx.new()
	version.compile("(?m)^schema_version\\s*=\\s*(\\d+)\\s*$")
	var stamp = version.search(text.substr(root)) if root >= 0 else null
	if stamp == null or int(stamp.get_string(1)) != STGProject.VERSION:
		result.issue = "此文件不是当前资产格式（%d），请打开转换后的资源库。" % STGProject.VERSION
		return result
	result.resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not result.resource is STGProject: result.issue = "文件不是 STGMaker 资源库。"
	return result

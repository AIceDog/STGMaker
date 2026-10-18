@tool
class_name STGProgressStore
extends RefCounted
## 局外进度与策划资源分开保存。只记录稳定地点 ID 和货币，不保存战斗运行对象。
const VERSION = 1
const MAX_CURRENCY = 2147483647
var path: String = "user://stg_progress_v1.json"
var completed: Dictionary = {}
var currency: int = 0
var issue: String = ""
var write_blocked: bool = false

func load_progress(save_path: String) -> void:
	path = save_path
	completed.clear()
	currency = 0
	issue = ""
	write_blocked = false
	var primary_exists = FileAccess.file_exists(path)
	var document = _read_valid_document(path) if primary_exists else {}
	if not document.is_empty():
		_apply_document(document)
		return
	# rename(primary, backup) 与 rename(tmp, primary) 之间可能断电。
	# 临时文件完整时优先使用最新快照，否则尝试上一份有效备份。
	var recovery_exists = false
	for suffix in [".tmp", ".bak"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		recovery_exists = true
		document = _read_valid_document(path + suffix)
		if document.is_empty():
			continue
		_apply_document(document)
		if primary_exists:
			_block("原存档无法读取或格式损坏；已从恢复文件读取进度，原文件仍保留，请备份重建后继续保存")
		else:
			issue = "发现中断的存档更新，已从恢复文件读取进度"
		return
	if primary_exists or recovery_exists:
		_block("存档格式损坏或版本不受支持，原文件与恢复文件已保留；本次进度暂存于内存")

func _read_valid_document(source: String) -> Dictionary:
	var file = FileAccess.open(source, FileAccess.READ)
	if file == null:
		return {}
	var parser = JSON.new()
	var error = parser.parse(file.get_as_text())
	file.close()
	return parser.data if error == OK and _valid_document(parser.data) else {}

func _apply_document(document: Dictionary) -> void:
	for identifier in document.completed:
		completed[identifier] = true
	currency = int(document.currency)

func _valid_document(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION:
		return false
	if not value.get("completed") is Array:
		return false
	var amount = value.get("currency")
	if not (amount is float or amount is int) or not is_finite(float(amount)) or amount < 0 or amount > MAX_CURRENCY or amount != floor(float(amount)):
		return false
	for identifier in value.completed:
		if not identifier is String or identifier.is_empty():
			return false
	return true

func is_unlocked(location: STGWorldLocation) -> bool:
	for identifier in location.requires_completion:
		if not completed.has(identifier):
			return false
	return true

## 同一地点只发一次首次通关奖励；重新挑战不会重复增加货币。
func complete_location(location: STGWorldLocation) -> int:
	if location == null or location.reward < 0:
		return 0
	if completed.has(location.id):
		return 0
	completed[location.id] = true
	# 先限制本次实际到账额，避免大额奖励造成整数溢出或写出自己无法读取的存档。
	var earned = mini(location.reward, maxi(0, MAX_CURRENCY - currency))
	currency += earned
	return earned

func save() -> bool:
	if write_blocked:
		return false
	var document = {"version": VERSION, "completed": completed.keys(), "currency": currency}
	if not _valid_document(document):
		issue = "当前进度数据无效，未覆盖已有存档"
		return false
	var temporary = path + ".tmp"
	var backup = path + ".bak"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		issue = "无法写入存档，本次进度仍保留在内存"
		return false
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		issue = "写入存档失败，本次进度仍保留在内存"
		return false
	# 先完整写临时文件，再替换目标；替换失败时恢复上一份有效存档。
	var previous_exists = FileAccess.file_exists(path)
	if previous_exists:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			issue = "无法更新存档备份，本次进度仍保留在内存"
			return false
		if DirAccess.rename_absolute(path, backup) != OK:
			issue = "无法替换存档，原文件已保留"
			return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if previous_exists:
			DirAccess.rename_absolute(backup, path)
		issue = "保存存档失败，上一份存档已保留"
		return false
	issue = ""
	return true

## 只由用户显式点击重建按钮调用；损坏文件先归档，再允许保存当前内存进度。
func archive_corrupt_and_save() -> bool:
	if not write_blocked:
		return save()
	var archive_stamp = str(Time.get_unix_time_from_system()).replace(".", "-") + "-" + str(Time.get_ticks_usec())
	for suffix in ["", ".tmp", ".bak"]:
		var source = path + suffix
		if FileAccess.file_exists(source) and DirAccess.rename_absolute(source, source + ".corrupt-" + archive_stamp) != OK:
			issue = "无法备份损坏存档，剩余原文件已保留"
			return false
	write_blocked = false
	return save()

func _block(message: String) -> void:
	issue = message
	write_blocked = true

@tool
extends RefCounted
## 相对路径辅助脚本也必须进入游戏依赖闭包。
static func angle(index: int, count: int) -> float:
	return TAU * index / count

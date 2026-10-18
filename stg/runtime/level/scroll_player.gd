@tool
extends RefCounted
## 卷轴接口 advance：全关卡只有一个推进距离，背景与实体读取同一次位移。
var distance: float = 0
var displacement: Vector2 = Vector2.ZERO

## 自定义更新：speed 为向左推进的像素 / 秒；distance 为累计路程，displacement 为本步位移。
func advance(speed: float, dt: float) -> void:
	var amount = speed * dt
	distance += amount
	displacement = Vector2(-amount, 0)

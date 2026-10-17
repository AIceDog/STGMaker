@tool
extends RefCounted
## 预览玩家接口 handle_key/move/clear。只接收画布焦点内按键，不修改全局 InputMap。
const KEYS = [KEY_W, KEY_A, KEY_S, KEY_D]
var held: Dictionary = {}
var speed: float = 220

func handle_key(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: clear(); return false
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key not in KEYS: return false
	held[key] = event.pressed
	return true

func direction() -> Vector2:
	return Vector2(int(held.get(KEY_D, false)) - int(held.get(KEY_A, false)), int(held.get(KEY_S, false)) - int(held.get(KEY_W, false))).normalized()

func move(world, dt: float, bounds: Rect2) -> void:
	var point: Vector2 = world.player + direction() * speed * dt
	var arena = bounds.grow(-world.player_radius)
	world.player = point.clamp(arena.position, arena.end)

func clear() -> void: held.clear()

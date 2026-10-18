@tool
extends RefCounted
## 玩家弹丸实例容器；默认武器与自定义武器通过同一生成接口写入完整实例数据。
var shots: Array[Dictionary] = []
var last_fired_at: float = -1000
const SPEED = 720.0 # 战斗坐标像素 / 秒。
const DAMAGE = 25.0 # 当前敌人接口使用最大生命值百分比。

var fire_interval: float = 0.15
var shot_speed: float = SPEED
var shot_damage: float = DAMAGE
var shot_lifetime: float = 1.5
var shot_radius: float = 3

## 自定义测试武器入口：at 为玩家战斗坐标，time 为关卡累计秒数，控制连续射击间隔。
func fire(at: Vector2, time: float) -> void:
	if time - last_fired_at < fire_interval or shots.size() >= 128:
		return
	last_fired_at = time
	emit_shot(at + Vector2(14, 0), Vector2.RIGHT, shot_speed, shot_damage, shot_lifetime)

## 技术策划武器入口：每颗子弹保留独立速度、伤害和寿命，不修改共享武器设置。
func emit_shot(at: Vector2, direction: Vector2, speed: float, damage: float, lifetime: float) -> void:
	if shots.size() >= 128 or not at.is_finite() or not direction.is_finite() or direction.is_zero_approx(): return
	if not is_finite(speed) or not is_finite(damage) or not is_finite(lifetime) or speed <= 0 or damage < 0 or lifetime <= 0: return
	shots.append({"position": at, "age": 0.0, "velocity": direction.normalized() * speed, "damage": damage, "lifetime": lifetime})

## 自定义更新：射击朝右推进，整段位移判定命中，只消耗在距离起点最近的目标上。
func tick(world, dt: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var shot = shots[i]
		var previous: Vector2 = shot.position
		shot.position += shot.velocity * dt
		shot.age += dt
		var target = _find_nearest_target(world, previous, shot.position)
		if target != null:
			target.damage(shot.damage)
			shots.remove_at(i)
		elif shot.age >= shot.lifetime or shot.position.x > 520 or shot.position.x < -520 or absf(shot.position.y) > 420:
			shots.remove_at(i)

func _find_nearest_target(world, previous: Vector2, current: Vector2):
	var target = null
	var nearest = INF
	for entity in world.entities:
		if entity.is_resolved() or (entity.simulation != null and not entity.simulation.boss_visible):
			continue
		var closest = Geometry2D.get_closest_point_to_segment(entity.location, previous, current)
		if entity.location.distance_to(closest) <= entity.settings.body_radius + shot_radius:
			var distance = previous.distance_to(entity.location)
			if distance < nearest:
				nearest = distance
				target = entity
	return target

## 自定义重置：新一轮测试可以立即射击，不继承上一轮的射击冷却。
func clear() -> void:
	shots.clear()
	last_fired_at = -1000

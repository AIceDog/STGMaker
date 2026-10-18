@tool
extends RefCounted
## 编队接口 start/tick/finished_spawning：允许一次 tick 跨过多个出场时间，不漏生成。
var definition: STGWaveDefinition
var origin: Vector2
var group_id: String
var event_id: String = ""
var elapsed: float = 0 # 相对出场事件的秒数；首 tick 前可为负值以补偿触发帧偏移。
var spawned: int = 0

## 自定义初始化：position 是编队中心的战斗坐标；此任务只生成成员，不管理成员 AI。
func start(wave: STGWaveDefinition, position: Vector2, segment_id: String, source_event: String = "", initial_elapsed: float = 0) -> void:
	definition = wave
	origin = position
	group_id = segment_id
	event_id = source_event
	elapsed = initial_elapsed
	spawned = 0

## 自定义更新：一次 dt 跨过多个出场时刻时补齐所有成员，保持配置中的顺序。
func tick(world, dt: float) -> void:
	elapsed += dt
	while spawned < definition.count and elapsed + 0.000001 >= spawned * definition.interval:
		world.spawn_entity(definition, origin + definition.offset(spawned), group_id, event_id)
		spawned += 1
		if not world.issue.is_empty():
			return

## 自定义查询：返回 true 只表示生成条结束，不表示已经生成的敌人应被删除。
func finished_spawning() -> bool:
	return spawned >= definition.count

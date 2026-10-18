@tool
extends RefCounted
## 攻击接口 start/tick/is_completed/cancel；取消发射与清除已有子弹分别处理。
var definition: STGBossAttack
var instance
var elapsed: float = 0 # 从攻击真正开始起的秒数，独立于动作段的执行时钟。
var started: bool = false
var failed: bool = false

## 自定义开始：按配置选择战斗坐标原点，并把本次弹幕 owner 交给敌人阶段跟踪。
func start(context, config: STGBossAttack) -> void:
	definition = config
	started = true
	var world = context.world
	var at: Vector2 = world.boss
	if config.origin_mode == "player":
		at = world.player
	elif config.origin_mode == "world":
		at = Vector2.ZERO
	if not config.behavior_id.is_empty():
		instance = world.play_behavior(config.behavior_id, at + config.origin_offset)
	else:
		instance = world.play_barrage(config.barrage_id, at + config.origin_offset)
	failed = instance == null
	if instance != null:
		context.owned_attacks.append(instance.owner_id)

## 自定义更新：可跟随敌人改变未来发射原点；已经发出的子弹位置不在此修改。
func tick(context, dt: float) -> void:
	if not started or instance == null:
		return
	elapsed += dt
	if definition.follow_boss and definition.origin_mode == "boss":
		instance.origin = context.world.boss + definition.origin_offset

## 自定义查询：按发射结束 / 攻击耗尽 / 指定执行秒数，判断攻击模块是否完成。
func is_completed(world, duration: float) -> bool:
	if not started:
		return false
	if instance == null:
		return true
	if instance.failed:
		failed = true
		return true
	match definition.finish_event:
		"immediate":
			return true
		"emission":
			return instance.emission_finished()
		"cleared":
			return instance.is_finished(world)
	return elapsed + 0.000001 >= duration

## 自定义取消：停止未来发射；只有 clear_on_end 开启才结束同归属的已有子弹。
func cancel(context) -> void:
	if instance == null:
		return
	if definition.finish_event != "immediate":
		instance.cancel() # 非阻塞释放继续执行；阻塞动作取消时停止未来发射。
	if definition.clear_on_end:
		context.world.stop_owner(instance.owner_id)

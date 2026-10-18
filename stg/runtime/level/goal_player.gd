@tool
extends RefCounted
## 阶段目标接口 evaluate / register / resolve / clear。实体回收后仍保留真实结果。
var records: Dictionary = {}

func register(entity) -> void:
	# 配置身份在出场时保存；即使实体节点已释放，真实死亡 / 离场结果也能继续判定。
	records[entity.instance_id] = {
		"group": entity.group_id,
		"event": entity.event_id,
		"required": entity.definition.counts_for_clear,
		"kind": entity.definition.kind,
		"reason": "",
	}

func resolve(id: int, reason: String) -> void:
	if records.has(id):
		records[id].reason = reason

## 自定义查询：ready 表示可推进；failed 是硬错误；blocked 是不可达成的游戏目标。
## waiting 只在超过计划长度后显示，不能用它决定是否继续更新战斗。
func evaluate(world) -> Dictionary:
	var rule: STGLevelExitRule = world.segment().exit_rule
	var timed = world.segment_elapsed + 0.000001 >= world.segment().duration
	if rule.mode == "time":
		return _result(timed)
	var pending = false
	var target_exists = rule.condition != "defeat_target"
	# 尚未触发的事件也属于目标；屏幕暂时为空不代表整个阶段已经清场。
	for event in world.segment().events:
		var wave = world.project.find("waves", event.wave_id)
		# 校验通常在 reset 时完成；运行期间被调用者修改资源，也不能把丢失的目标视为已击败。
		if wave == null:
			return _result(false, false, "出场编队已丢失：" + event.wave_id)
		if event.id == rule.target_event_id:
			target_exists = true
			if rule.condition == "defeat_target" and wave.kind != "enemy":
				return _result(false, false, "指定击败目标必须是敌人出场事件")
		if rule.includes_event(event.id, wave.kind, wave.counts_for_clear) and not world.fired_events.has(event.id):
			pending = true
	if not target_exists:
		return _result(false, false, "指定击败目标不属于当前阶段，请重新选择出场事件")
	# 编队条结束前，后续成员即使还没生成，也要阻止提前推进。
	if _has_pending_members(world, rule):
		pending = true
	for record in records.values():
		if record.group != world.segment().id or not rule.includes_event(record.event, record.kind, record.required):
			continue
		if record.reason.is_empty():
			pending = true
		elif rule.condition != "clear" and record.reason != "died":
			# 这是游戏结果而非程序错误：目标无法达成，但场上其余行为仍须继续。
			var blocked = "击败目标已离场（%s），请重试或调整目标 / 离场规则" % record.reason
			return _result(false, timed, "", blocked)
	if rule.wait_attacks and _has_remaining_attacks(world, rule):
		pending = true
	var ready = not pending and (timed or rule.mode == "condition")
	# 目标型阶段可提前结束；超过计划长度后才进入时间轴的等待状态。
	return _result(ready, pending and timed)

func _has_pending_members(world, rule: STGLevelExitRule) -> bool:
	for job in world.wave_jobs:
		if job.group_id == world.segment().id and rule.includes_event(job.event_id, job.definition.kind, job.definition.counts_for_clear):
			return true
	return false

## 只读调试快照。推进结论直接来自 evaluate；计数读取实际任务与永久结果账本。
## 未生成、存活、真正死亡和离场分开统计，释放节点不会丢失已完成的结果。
func inspect(world) -> Dictionary:
	var result = {"has_condition": false, "events": [], "pending": 0, "alive": 0,
		"defeated": 0, "departed": 0, "remaining_attacks": 0, "finishing": 0, "ready": false,
		"waiting": false, "failed": "", "blocked": ""}
	if world.definition == null or world.definition.segments.is_empty(): return result
	var outcome = evaluate(world)
	for key in ["ready", "waiting", "failed", "blocked"]: result[key] = outcome.get(key, result[key])
	var rule: STGLevelExitRule = world.segment().exit_rule
	result.has_condition = rule.mode != "time"
	if not result.has_condition: return result
	for event in world.segment().events:
		var wave = world.project.find("waves", event.wave_id)
		if wave == null or not rule.includes_event(event.id, wave.kind, wave.counts_for_clear): continue
		var entry = {"id": event.id, "title": event.title, "pending": 0, "alive": 0,
			"defeated": 0, "departed": 0, "remaining_attacks": 0, "finishing": 0, "instances": []}
		if not world.fired_events.has(event.id): entry.pending = wave.count
		for job in world.wave_jobs:
			if job.group_id == world.segment().id and job.event_id == event.id:
				entry.pending += maxi(0, job.definition.count - job.spawned)
		for id in records:
			var record = records[id]
			if record.group != world.segment().id or record.event != event.id: continue
			var state: String = record.reason
			if state.is_empty(): entry.alive += 1
			elif state == "died": entry.defeated += 1
			else: entry.departed += 1
			entry.instances.append({"id": id, "reason": state, "finishing": false})
		for entity in world.entities:
			if entity.group_id == world.segment().id and entity.event_id == event.id and entity.simulation != null:
				entry.remaining_attacks += entity.simulation.actors.size()
				# 死亡行为仍可能在无子弹时等待落地爆炸；直接查询实体自己的收尾判定。
				if entity.is_resolved() and not entity.is_drained():
					entry.finishing += 1
					for instance in entry.instances:
						if instance.id == entity.instance_id: instance.finishing = true
		result.events.append(entry)
		for key in ["pending", "alive", "defeated", "departed", "remaining_attacks", "finishing"]: result[key] += entry[key]
	return result

func _has_remaining_attacks(world, rule: STGLevelExitRule) -> bool:
	for entity in world.entities:
		if entity.group_id != world.segment().id:
			continue
		if rule.includes_event(entity.event_id, entity.definition.kind, entity.definition.counts_for_clear) and not entity.is_drained():
			return true
	return false

func _result(ready: bool, waiting: bool = false, failed: String = "", blocked: String = "") -> Dictionary:
	var result = {"ready": ready, "failed": failed, "waiting": waiting}
	if not blocked.is_empty():
		result.blocked = blocked
	return result

func clear() -> void:
	records.clear()

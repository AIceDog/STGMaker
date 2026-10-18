@tool
extends RefCounted
const Session = preload("res://stg/runtime/extensions/extension_session.gd")
const ContactDamage = preload("res://stg/runtime/modules/contact_damage.gd")

static func apply(actor, world, damage: float, at: Vector2 = Vector2.INF) -> void:
	if actor.lifecycle.damage_on_contact:
		_execute(actor, world, damage, null, ContactDamage.new(), at)
	for binding in actor.lifecycle.hit_effects:
		_execute(actor, world, damage, binding, null, at)

static func _execute(actor, world, damage: float, binding: STGExtensionBinding, builtin: STGExtension = null, at: Vector2 = Vector2.INF) -> void:
	var context = STGEffectContext.new(world)
	context._origin = actor.position if at == Vector2.INF else at
	context._heading = actor.rotation
	context._owner_id = actor.owner_id
	context.hit_position = world.player
	context.damage = damage
	var session = Session.new()
	if not session.begin(binding.definition if binding != null else null, binding.parameters if binding != null else {}, "effect", context, builtin):
		world.issue = session.issue
	elif session.failed:
		world.issue = "自定义命中效果执行失败"
	session.cancel("completed")


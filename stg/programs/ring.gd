@tool
extends "res://stg/programs/burst.gd"
func shot_angle(ctx:STGAttackContext,event:Dictionary) -> float:return ctx.heading()+deg_to_rad(parameters.angle)+TAU*event.shot/parameters.count
func shot_origin(ctx:STGAttackContext,event:Dictionary) -> Vector2:return ctx.origin()+Vector2.from_angle(shot_angle(ctx,event))*parameters.radius

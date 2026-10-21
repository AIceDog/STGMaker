@tool
extends "res://stg/programs/burst.gd"
func shot_angle(ctx:STGAttackContext,event:Dictionary) -> float:return ctx.heading()+deg_to_rad(parameters.angle+event.serial*parameters.angle_step)

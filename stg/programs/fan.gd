@tool
extends "res://stg/programs/burst.gd"
func shot_angle(ctx:STGAttackContext,event:Dictionary) -> float:
 var fraction=0.0 if parameters.count==1 else float(event.shot)/(parameters.count-1)-0.5
 return ctx.heading()+deg_to_rad(parameters.angle+fraction*parameters.spread)

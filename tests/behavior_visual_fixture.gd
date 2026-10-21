@tool
extends RefCounted
static func animated_scene() -> PackedScene:
    var visual=Node2D.new();visual.name="EnemyVisual"
    var body=Node2D.new();body.name="Body";visual.add_child(body);body.owner=visual
    var sprite=Sprite2D.new();sprite.name="Sprite";sprite.texture=load("res://projects/attack_showcase/assets/arrow.png");sprite.scale=Vector2(4,4);body.add_child(sprite);sprite.owner=visual
    var player=AnimationPlayer.new();player.name="AnimationPlayer";visual.add_child(player);player.owner=visual
    var library=AnimationLibrary.new()
    for key in ["windup","active","recovery"]:
        var clip=Animation.new();clip.length=1.0
        var track=clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(track,NodePath("Body:rotation"))
        clip.track_insert_key(track,0,0.0);clip.track_insert_key(track,1,1.0)
        library.add_animation(key,clip)
    player.add_animation_library("",library)
    var packed=PackedScene.new();packed.pack(visual);visual.free();return packed

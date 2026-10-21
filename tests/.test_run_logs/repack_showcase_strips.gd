extends SceneTree
func _initialize():
 var folder="res://projects/attack_showcase";var data=JSON.parse_string(FileAccess.get_file_as_string(folder+"/art_sources.json"))
 for asset in data.assets:
  if not asset.has("packing_rect"):continue
  var rect=asset.packing_rect;var image=Image.load_from_file(asset.source).get_region(Rect2i(int(rect[0]),int(rect[1]),int(rect[2]),int(rect[3])))
  image.resize(16,14,Image.INTERPOLATE_NEAREST)
  var tile=Image.create_empty(16,16,false,Image.FORMAT_RGBA8);tile.blit_rect(image,Rect2i(0,0,16,14),Vector2i(0,1));tile.save_png(folder+"/assets/"+asset.name+".png")
 quit()

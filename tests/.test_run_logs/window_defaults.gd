extends SceneTree
func _initialize():
 for cls in ["Window","AcceptDialog","FileDialog","PopupMenu","PopupPanel"]:
  var w=ClassDB.instantiate(cls)
  print(cls," visible=",w.visible," transient=",w.transient," exclusive=",w.exclusive," popup=",w.popup_window)
  w.free()
 quit()

extends SceneTree
func _initialize():
 for method in ClassDB.class_get_method_list("EditorInterface"):
  if "distraction" in method.name:print(method.name)
 quit()

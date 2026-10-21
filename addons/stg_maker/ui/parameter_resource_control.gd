@tool
extends VBoxContainer
## 类型约束资源参数；清除与继承分开存储，不能用空字符串假装资源引用。
var field:Dictionary
var change:Callable
var current
var mode:OptionButton
var picker:Button
var clear:Button
var path:Label
var picker_dialog:FileDialog
func configure(metadata:Dictionary,value,callback:Callable) -> void:
 field=metadata;change=callback
 var title=Label.new();title.text=str(field.get("label",field.name));add_child(title)
 if field.type=="resource_override":
  mode=OptionButton.new()
  for label in ["沿用素材","禁用","自定义"]:mode.add_item(label)
  add_child(mode)
  mode.item_selected.connect(func(index):
   current={"mode":["inherit","disabled","custom"][index],"value":current.get("value") if index==2 else null};_commit())
 var row=HFlowContainer.new();add_child(row)
 picker=Button.new();picker.text="选择资源…";row.add_child(picker);picker.pressed.connect(_choose)
 clear=Button.new();clear.text="清除";row.add_child(clear)
 clear.pressed.connect(func():current={"mode":"disabled","value":null} if mode!=null else null;_commit())
 path=Label.new();path.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(path)
 sync_value(value)
func sync_value(value) -> void:
 current=value
 var resource=current
 if mode!=null:
  if not current is Dictionary:current={"mode":"inherit","value":null}
  mode.select(["inherit","disabled","custom"].find(current.get("mode","inherit")))
  resource=current.get("value")
  picker.visible=mode.selected==2;clear.visible=mode.selected!=0
 path.text=(resource.resource_path if not resource.resource_path.is_empty() else resource.resource_name) if resource is Resource else "未选择资源"
 path.tooltip_text=path.text
 if mode!=null and mode.selected==0:path.text="沿用引用素材的默认值"
 if mode!=null and mode.selected==1:path.text="此招式禁用该项"
func _commit() -> void:
 var value=current
 change.call(value);sync_value(value)
func _choose() -> void:
 if is_instance_valid(picker_dialog):return
 var dialog=FileDialog.new();picker_dialog=dialog;dialog.access=FileDialog.ACCESS_RESOURCES;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
 var cls=str(field.get("resource_class","Resource"))
 var filters={"Texture2D":"*.png,*.jpg,*.webp,*.svg,*.tres ; 贴图","SpriteFrames":"*.gif,*.png,*.jpg,*.webp,*.tres ; 动画","AudioStream":"*.wav,*.ogg,*.mp3,*.tres ; 音效","PackedScene":"*.tscn,*.scn ; 特效场景"}
 dialog.filters=PackedStringArray([filters.get(cls,"*.tres ; 资源")]);add_child(dialog) # 与字段同归属，切页不能遗留一个阻塞整个编辑器的窗口。
 dialog.file_selected.connect(func(selected):
  var resource
  if cls=="SpriteFrames" and selected.get_extension().to_lower()=="gif":
   var result=load("res://addons/stg_maker/authoring/gif_import.gd").new().load_clip(selected)
   if result.issue.is_empty():resource=result.clip
  else:resource=load(selected)
  if cls=="SpriteFrames" and resource is Texture2D:
   var clip=SpriteFrames.new();clip.set_animation_speed(&"default",1);clip.add_frame(&"default",resource,.1);resource=clip
  if resource is Resource and resource.is_class(cls):current={"mode":"custom","value":resource} if mode!=null else resource;_commit()
  else:path.text="资源类型不符合："+cls
  _close_picker())
 dialog.canceled.connect(_close_picker);dialog.popup_centered_ratio(.7)

func _close_picker() -> void:
 if not is_instance_valid(picker_dialog):return
 picker_dialog.hide();picker_dialog.queue_free();picker_dialog=null
func _exit_tree() -> void:
 _close_picker()

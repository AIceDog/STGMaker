@tool
extends RefCounted
## 事务快照：复制配置及可编辑曲线/形状，共享只读场景、贴图和音频，避免复制大型美术。
static func copy(value: Variant) -> Variant: # 自定义接口
	if value is PackedStringArray or value is PackedVector2Array:
		return value.duplicate() # Godot PackedArray 按引用传递，连接/轮廓需要独立副本。
	if value is Texture2D or value is SpriteFrames or value is AudioStream or value is PackedScene or value is Script or value is STGExtensionDefinition:
		return value
	if value is Resource:
		if value.get_script() == null:
			return value.duplicate(true) # Godot 内置 Resource.duplicate
		var result = value.get_script().new()
		for property in value.get_property_list(): # Godot 内置：读取属性描述
			if property.name != "script" and property.usage & PROPERTY_USAGE_STORAGE:
				result.set(property.name, copy(value.get(property.name)))
		return result
	if value is Array:
		var result = value.duplicate()
		for i in value.size():
			result[i] = copy(value[i])
		return result
	if value is Dictionary:
		return value.duplicate(true)
	return value

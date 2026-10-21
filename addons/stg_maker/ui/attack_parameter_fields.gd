@tool
extends RefCounted
const F = preload("res://addons/stg_maker/ui/fields.gd")
static func add(parent: Node, field: Dictionary, value, change: Callable, project: STGProject) -> Control:
    var metadata = STGExtensionDefinition.new()
    metadata.fields.assign([field])
    var issues = metadata.validate_fields()
    if not issues.is_empty(): return F.note(parent,"参数声明需修正："+"；".join(issues))
    var label = str(field.get("label",field.name))
    var control: Control
    match str(field.type):
        "float", "int":
            control = F.number(parent,label,float(value),func(v): change.call(int(v) if field.type=="int" else v),float(field.get("min",-100000)),float(field.get("max",100000)),float(field.get("step",1 if field.type=="int" else 0.1)))
        "enum":control=F.select(parent,label,str(value),field.get("values",[]),field.get("labels",field.get("values",[])),change)
        "vector2":
            control=VBoxContainer.new();parent.add_child(control)
            var axes=F.vector_inline(control,label,value,func(v):change.call(v),-100000,100000)
            control.set_meta("parameter_axes",axes)
        "color":control=F.color(parent,label,value,change)
        "resource","resource_override":
            control=load("res://addons/stg_maker/ui/parameter_resource_control.gd").new();parent.add_child(control);control.configure(field,value,change)
        "bool": control = F.toggle(parent,label,bool(value),change)
        "string": control = F.text(parent,label,str(value),change)
        "resource_id":
            var ids: Array = [""]; var labels: Array = ["请选择资源"]
            for item in project.get(field.collection):
                if item != null: ids.append(item.id); labels.append(item.title)
            control = F.select(parent,label,str(value),ids,labels,change)
    if control != null:
        control.set_meta("program_parameter",str(field.name))
        F.help(control,str(field.get("help","")))
    return control
static func sync(root: Node, values: Dictionary) -> void:
    for node in root.find_children("*","Control",true,false):
        if not node.has_meta("program_parameter"): continue
        var value = values.get(str(node.get_meta("program_parameter")))
        if node.has_method("sync_value"):node.sync_value(value);continue
        if value == null: continue
        if node.has_meta("parameter_axes"):
            var axes=node.get_meta("parameter_axes");axes[0].set_value_no_signal(value.x);axes[1].set_value_no_signal(value.y);continue
        if node is ColorPickerButton:node.color=value;continue
        if node is SpinBox: node.set_value_no_signal(value)
        elif node is CheckButton: node.set_pressed_no_signal(value)
        elif node is LineEdit:
            if node.text != str(value): node.text = str(value)
            node.set_meta("committed",str(value))
        elif node is OptionButton and node.has_meta("config_keys"): node.select(node.get_meta("config_keys").find(value))

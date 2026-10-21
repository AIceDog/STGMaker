@tool
extends RefCounted
## 制作能力目录：枚举声明资源；不维护内置节点白名单。
static func definitions() -> Array:
    var result=[]
    for name in DirAccess.get_files_at("res://stg/behaviors"):
        if name.ends_with(".tres"):
            var definition=load("res://stg/behaviors/"+name)
            if definition is STGBehaviorProgramDefinition:result.append(definition)
    result.sort_custom(func(a,b):return a.title.naturalnocasecmp_to(b.title)<0)
    return result

@tool
extends RefCounted
## 纯配置查询接口 resolve。路径里的字符串访问字段，整数访问数组；不修改资源。
## scope 使用属性名与数组索引，不接触运行对象。
static func resolve(resource, path: Array):
    var target = resource
    for part in path:
        if target == null: return null
        if part is int and (not target is Array or part < 0 or part >= target.size()): return null
        target = target.get(part) if part is String else target[part]
    return target

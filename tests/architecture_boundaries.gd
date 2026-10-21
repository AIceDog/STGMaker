extends SceneTree
const Audit = preload("res://addons/stg_maker/build/architecture_audit.gd")
const Policy = preload("res://addons/stg_maker/build/dependency_policy.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    var issues = Audit.check()
    check(issues.is_empty(), "实际工程依赖方向：" + "；".join(issues))
    for source in ["res://stg/runtime/example.gd", "res://stg/api/example.gd", "res://stg/definitions/example.gd"]:
        check(not Policy.issue(source, "res://addons/stg_maker/ui/fields.gd").is_empty(), "运行框架拒绝编辑器依赖")
    check(not Policy.issue("stg/api/example.gd", "res://stg/runtime/simulation.gd").is_empty(), "API 不能反向依赖实现")
    check(not Policy.issue("stg/definitions/example.gd", "res://stg/runtime/simulation.gd").is_empty(), "配置不能反向依赖运行代码")
    check(Policy.issue("stg/definitions/example.gd", "res://stg/runtime/scenes/moving.tscn").is_empty(), "资产定义可引用运行场景")
    check(not Policy.check_source("game/extensions/example.gd", "extends STGSimulation").is_empty(), "隐式全局类型不能绕过公开 API")
    check(Policy.issue("game/extensions/example.gd", "res://stg/api/attack_extension.gd").is_empty(), "游戏扩展可以依赖公共协议")
    check(not Policy.check_source("game/extensions/example.gd", 'const Bad = preload("../../stg/runtime/simulation.gd")').is_empty(), "相对路径不能绕过公开 API")
    var paths = preload("res://addons/stg_maker/build/script_dependencies.gd").collect("res://game/extensions/example.gd", '# preload("comment.gd")\nconst MESSAGE = "preload(\\\"text.gd\\\")"\nvar dynamic = load("folder/" + name)\nconst Helper = preload("helper.gd") # load("comment2.gd")')
    check(paths == ["res://game/extensions/helper.gd"], "依赖收集跳过注释、普通文本和动态拼接，仅收集静态文件")
    for source in ["stg/api/probe.gd", "stg/definitions/probe.gd"]:
        check(not Policy.check_source(source, "extends STGGameSession").is_empty(), "所有受限目录均检查隐式全局类型")
    print("ARCHITECTURE BOUNDARIES RESULT: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)

func check(value: bool, message: String) -> void:
    checks += 1
    if not value: failures += 1; push_error(message)

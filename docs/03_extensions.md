# 编写扩展

每个实现脚本使用 @tool，继承对应的公开类型。编辑器预览和成品使用同一实现；构造函数不要求参数，运行参数在 start 中读取。

| 能力 | 基类 | 上下文 |
| --- | --- | --- |
| 弹丸运动 | STGMotionExtension | STGMotionContext |
| 发射 | STGEmissionExtension | STGEmissionContext |
| 敌人动作 | STGActionExtension | STGActionContext |
| 条件 | STGConditionExtension | STGConditionContext |
| 命中效果 | STGEffectExtension | STGEffectContext |
| 主角控制/武器/能力 | STGPlayerExtension | STGPlayerContext |

STGExtensionDefinition 保存 kind、sdk_version=1、稳定 id、标题、说明、implementation Script 与 fields。字段支持 float、int、bool、string、resource_id，包含默认值、范围、步长和说明。resource_id 必须声明 collection（可引用bullets、barrages、behaviors、bosses等），框架据此收集资源依赖。声明只读共享；所有能力槽均保存 STGExtensionBinding，包含 definition 与独立 parameters。

```gdscript
@tool
extends STGActionExtension
var start_position: Vector2
func start(context: STGActionContext, _parameters: Dictionary) -> void:
    start_position = context.position()
    context.play_animation("dive")
func tick(context: STGActionContext, _dt: float) -> void:
    context.set_position(start_position + Vector2(-100 * context.elapsed(), 0))
    if context.elapsed() >= 1: context.finish()
```

公共查询包含玩家位置、敌人位置/血量、战斗时间、动作完成间隔和固定种子随机数。命令上下文通过emit_projectile(attack_id, position, angle)发射已配置的招式弹体，通过play_barrage和play_behavior调用招式或行为子流程，并提供召唤和伤害请求；扩展不访问带下划线的内部字段，也不依赖 Simulation 或流程运行器。

start 启动一次，tick 按固定步长更新，finish(success) 报告完成。宿主调用 cancel(reason) 进行最终清理；completed、expired、interrupted、stopped、removed 等原因来自具体宿主。清理时上下文已关闭；不要在 cancel 内继续提交战斗命令。条件和命中效果同步完成，运动、发射、动作和主角模块可跨帧执行。自定义动作受 duration 上限限制。

主角提供 controller、weapon、ability 三个槽。控制器通过 move/set_position 移动；武器可以 fire 调用默认武器，或 shoot 提交自己的方向、速度、伤害和寿命。每颗弹丸都保存完整实例字段。

完整脚本与声明示例见 game/extensions；可运行示例见 game/content/modular_example/run.tscn。新增参数需同步声明、工厂与对应校验，并运行 tests/extension_protocol.gd 和真实编辑器测试。

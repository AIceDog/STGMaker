# 架构与代码入口

```text
stg/api/                        六种公开能力及上下文
stg/definitions/                当前资源模型、工厂、引用图和校验
stg/runtime/                    战斗、关卡、游戏会话与能力宿主
addons/stg_maker/authoring/      文档、独立资产、事务与恢复草稿
addons/stg_maker/ui/             同页配置与预览
addons/stg_maker/build/          编译、依赖规则、构建与架构审查
game/content/                   游戏制作结果
game/extensions/                项目专用能力脚本与声明
tests/                          当前格式与当前行为的验收
tools/                          当前内容生成及构建命令
```

**依赖方向。** 运行框架不能依赖编辑器或具体游戏。API 不能依赖 runtime，definitions 可以引用运行场景但不能引用运行脚本。game/extensions 通过公开 API 接入。构建检查包含静态路径、相对依赖和隐式全局类型。构建检查自身属于编辑器，不进入成品。

**一个生命周期。** extension_session 负责创建实现、复制参数、start、tick、完成和 cancel。内置实现与脚本实现都从同一入口启动。声明资源、Script、场景、贴图可共享；执行对象、上下文、计时、目标和冷却属于实例。关闭的上下文不能继续提交操作，清理只发生一次。

**资产职责。** BulletDefinition只包含静态外观、碰撞、场景和尾迹采样。BarrageSkill保存FirePattern、ProjectileDefinition及其AttackLifecycle。BehaviorFlow既可嵌入敌人阶段，也可独立保存并复用；并行、等待与子流程仍由同一个flow_runner执行。素材不保存运动、伤害或后继，招式不保存敌人移动。

**动作。** flow_runner 创建 action_runner；后者统一处理动作运行标记、表现时钟、受击中断、完成记录和 completed/cancelled 事件。内置 composite_action 只编排攻击与移动组件及前摇/执行/后摇；脚本动作直接实现 STGActionExtension。宿主不暴露内置组件的属性代理。

**时序。** 战斗固定步长为 1/120 秒。敌人行为先更新，随后推进发射计划、弹丸和回收。动作的阶段时钟与攻击开始后的时钟分别有明确语义；并行分支从同一时刻开始，等待节点把当前步长剩余时间交给后续节点。AnimationPlayer 由动作宿主手动推进，不另用独立动画时钟。

**表现。** 发射声音可按每次释放、每轮或每颗弹体播放；命中与自然结束分别触发对应声音和Node2D特效场景。特效使用固定模拟时钟回收，提前结束的粒子可自行完成；所有场景都受最长持续时间限制。

**运动。** motion_runner 初始化阶段公共状态，并通过通用 Session 执行内置或自定义运动。模块只维护自己的算法状态。阶段时长、尺寸曲线、几何旋转和碰撞由宿主管理。

**引用图。** resource_references 遍历当前生效配置以及声明为 resource_id 的扩展参数。编译闭包、导入重映射、删除保护和扩展引用校验共用它；删除保护扫描全部来源集合，没有单独的反向来源白名单。

**格式。** STGProject.create() 创建显式版本 12 的索引。DocumentLoader、编译器和运行器都拒绝其他版本。当前代码不包含历史 Resource 字段、历史路径别名和运行时数据回退。

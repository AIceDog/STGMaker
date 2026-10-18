# STGMaker 开发约定

- Godot 4.7 GDScript，当前资产格式 12；STGProject.create() 显式创建当前索引。
- stg/api 是公开能力边界，definitions 是共享配置与生效引用图，runtime 是执行与实例状态。
- addons/stg_maker 负责制作与构建；构建依赖检查也放在此目录，不进入运行框架。
- 当前工程不保留历史模型、路径转发、在线迁移和历史实例数据回退；格式转换工具只能放在工程外。
- 内置与脚本能力均通过 extension_session；实现参数独立复制，关闭上下文后不能继续提交命令，清理只执行一次。
- action_runner 统一处理表现时钟、受击中断、完成记录和 completed/cancelled；composite_action 只编排内置算法。
- API 不依赖 runtime；definitions 不依赖运行脚本；runtime 不依赖编辑器或具体游戏；game/extensions 只依赖公开协议。
- 编辑器预览需要实例化的脚本使用 @tool，并验证真实编辑器中的能力执行。
- 保存通过 authoring/asset_store.gd；保留磁盘冲突检查、事务回滚与稳定序列化，不覆盖共享声明或手写脚本。
- 新引用进入 resource_references；编译、导入、删除和校验不能各自维护另一套来源关系。
- 敌人负责移动、攻击与离场；关卡安排出场和卷轴，不能拖动已经发射的攻击。
- 保留中文注释与 docs 阅读路线，注明坐标、时间、随机数和生命周期约定。
- 修改运行行为先运行 smoke 和相关专项；交付前运行 Run Tests.ps1。UI 变化使用真实渲染检查。
- 后续素材与招式制作界面需求见 docs/07_authoring_design_pending.md；实施相关改动前先阅读并随进展更新。FlyTiger 两套模板库按该记录暂缓处理。

extends SceneTree
## 悬停文案的语义约束：未知标题不编造，时间原点与素材职责不能互相混淆。
const Help = preload("res://addons/stg_maker/ui/control_help.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void:
	_check(Help.text("没有定义的字段").is_empty(), "未知标题留空")
	_check(Help.option("飞行方式", "不存在的方式").is_empty(), "未知选项留空")
	_check(Help.option("没有定义的字段", "track").is_empty(), "同名选项不能跨字段猜测")
	_check(Help.text("发射节奏 · 3 轮 / 0.20s") == Help.text("发射节奏"), "节奏动态标题使用明确匹配")
	_check(Help.text("新的发射节奏").is_empty(), "不对未知前后缀泛化")
	_check(Help.text("← 返回「五连射」") == Help.text("← 返回上一级"), "返回标题可包含资源名")
	_check(Help.text("多边形参数").contains("几何外形"), "已知动态外形分组")
	_check(Help.text("未知形状参数").is_empty(), "未知动态分组留空")
	_check(Help.text("开始时间 s").contains("本次招式开始"), "发射时间相对本招式")
	_check(Help.text("阶段内时间 s").contains("所属关卡阶段开始"), "出场时间相对所属关卡阶段")
	_check(Help.text("持续时间 s").contains("进入这一步"), "运动时长相对当前步骤")
	_check(Help.option("目标锁定时机", "call_start").contains("招式开始"), "延迟发射仍可使用招式起始锁定")
	_check(Help.text("局部旋转 °").contains("不改变") or Help.text("局部旋转 °").contains("仍沿原本"), "素材旋转与飞行方向分开")
	_check(Help.option("形状", "triangle").contains("三角形"), "三角形有独立说明")
	_check(Help.option("形状", "texture").contains("自定义图片"), "贴图是明确外形来源")
	_check(Help.option("碰撞形状", "texture").is_empty(), "碰撞不提供贴图形状")
	_check(Help.text("组合多个发射组").is_empty() and Help.text("修改范围").is_empty(), "删除的架构入口不保留悬停别名")
	_check(Help.text("发射与弹道").contains("行为流程"), "招式组合交给行为流程")
	_check(Help.text("打开子弹素材编辑器").contains("影响所有引用"), "直接素材页说明共享影响")
	_check(Help.text("玩家轴向安全缺口").contains("过滤出生位置"), "安全缺口不承诺未来路径安全")
	_check(Help.option("排列方式", "path").contains("不是子弹之后飞行"), "出生曲线与飞行曲线区分")
	_check(Help.option("等待目标", "clear").contains("越界和超时"), "清场接受普通离场")
	_check(Help.option("等待目标", "defeat_all").contains("逃走或超时不算击败"), "全部击败要求真实死亡")
	_check(Help.option("等待目标", "defeat_target").contains("指定批次"), "击败目标说明是出场批次")
	_check(Help.option("限时结束后", "finish").contains("记录这个敌人已被击败"), "现有Boss限时结束实际走死亡收尾")
	_check(Help.option("进入方式", "hp").contains("等待当前动作"), "血量切换等待旧动作与攻击收尾")
	_check(Help.option("环绕圆心基准", "world") == Help.option("目标位置基准", "world"), "圆心与目标共享相同坐标语义")
	_check(Help.text("X").contains("向右") and Help.text("Y").contains("向下"), "设计坐标方向明确")
	_check(Help.text("每轮数量").contains("发射") and Help.text("每轮数量").contains("子弹"), "数量解释实际发射内容")
	_check(Help.text("地图横坐标").contains("相对位置"), "世界地图不误用战斗坐标")
	for title in Help.TEXTS:
		_check_description(Help.TEXTS[title], title)
	for title in Help.OPTIONS:
		for key in Help.OPTIONS[title]:
			_check_description(Help.OPTIONS[title][key], title + "/" + key)
	for alias in Help.ALIASES:
		_check(not Help.text(alias).is_empty(), "字段别名有效：" + alias)
	for alias in Help.OPTION_ALIASES:
		_check(Help.OPTIONS.has(Help.OPTION_ALIASES[alias]), "选项别名有效：" + alias)
	print("Control help catalog: %d / %d checks passed (%d fields, %d option groups)" % [checks - failures, checks, Help.TEXTS.size(), Help.OPTIONS.size()])
	print("CONTROL HELP RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check_description(description: String, title: String) -> void:
	var lines = description.split("\n")
	var readable = lines.size() >= 2 and lines.size() <= 4
	for line in lines:
		readable = readable and not line.is_empty() and line.length() <= 40
	_check(readable, "说明分行且长度可读：" + title)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

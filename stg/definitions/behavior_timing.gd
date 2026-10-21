@tool
extends RefCounted
## 纯配置时长分析；只解释声明的组合策略，不识别节点 ID 或实现脚本。
const EPSILON=0.000001
static func animation_plan(length:float,duration:float,stage:String,mode:String="fit_cycles",manual:int=0) -> Dictionary:
    if not is_finite(duration) or not is_finite(length) or duration<=0 or length<=0:return {"rate":1.0,"cycles":0,"duration":duration,"length":length,"hold":false}
    var cycles=1
    var rate=length/duration
    var hold=false
    if stage=="active":
        if mode=="once_hold":
            rate=maxf(1.0,length/duration);hold=true
        else:
            cycles=manual if manual>0 else maxi(1,floori(duration/length+0.5))
            rate=float(cycles)*length/duration
    return {"rate":rate,"cycles":cycles,"duration":duration,"length":length,"hold":hold}
static func node_duration(node:STGFlowNode) -> float:
    var p=node.parameters()
    for key in ["windup","execution_duration","recovery"]:
        if not STGParameterSchema.number(p.get(key)) or float(p[key])<0:return INF
    return float(p.windup)+float(p.execution_duration)+float(p.recovery)
static func flow_duration(flow,project,entry:String="",memo:Dictionary={},stack:Array=[]) -> float:
    if not flow is STGBehaviorFlow:return INF
    var start=flow.entry_id if entry.is_empty() else entry
    var key=str(flow.get_instance_id())+":"+start
    if key in stack or stack.size()>128:return INF
    if memo.has(key):return memo[key]
    var result=_path_duration(flow,start,project,memo,stack+[key],[])
    memo[key]=result
    return result
static func _path_duration(flow,id:String,project,memo:Dictionary,stack:Array,path:Array) -> float:
    if STGFlowNode.is_terminal(id):return 0.0
    if id in path:return INF
    var key="path:"+str(flow.get_instance_id())+":"+id
    if memo.has(key):return memo[key]
    var node=flow.find(id)
    if node==null:return INF
    var duration=node_duration(node)
    if not is_finite(duration):return INF
    # 向上报告完整子树的最短时长，即使中间宿主自身预算还未修正。
    var required=required_execution(node,flow,project,memo,stack)
    if not is_finite(required):return INF
    var p=node.parameters()
    duration=float(p.windup)+maxf(float(p.execution_duration),required)+float(p.recovery)
    var tail=0.0
    for port in node.ports():
        if port.get("role","")=="child":continue
        tail=maxf(tail,_path_duration(flow,node.target(str(port.id)),project,memo,stack,path+[id]))
    memo[key]=duration+tail
    return duration+tail
static func required_execution(node:STGFlowNode,flow:STGBehaviorFlow,project,memo:Dictionary={},stack:Array=[]) -> float:
    if node.behavior_preset==null or node.behavior_preset.program==null:return INF
    var definition=node.behavior_preset.program
    var required=0.0
    match definition.child_budget_mode:
        "parallel":
            for child in node.children:required=maxf(required,flow_duration(child,project,"",memo,stack))
        "sum_branches":
            for port in node.ports():
                if port.get("role","")=="child":
                    var target=node.target(str(port.id))
                    if not STGFlowNode.is_terminal(target):required+=flow_duration(flow,project,target,memo,stack)
        "references":
            var p=node.parameters()
            for key in definition.child_flow_fields:
                var id=str(p.get(key,""))
                if id.is_empty():continue
                required=maxf(required,flow_duration(project.find("behaviors",id),project,"",memo,stack))
    return required

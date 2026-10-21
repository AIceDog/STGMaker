@tool
class_name STGAttackProgramDefinition
extends STGExtensionDefinition
## 只读声明；参数校验、构造及脚本依赖复用正式能力协议。
const CAPABILITIES = ["Body2D", "Beam2D", "Polyline2D", "Trail2D", "Area2D", "SummonEnemy"]
@export_enum("Body2D", "Beam2D", "Polyline2D", "Trail2D", "Area2D", "SummonEnemy") var capability: String = "Body2D"
func _init() -> void: kind = "attack"
func validate_fields() -> PackedStringArray:
    var issues = super.validate_fields()
    if capability not in CAPABILITIES: issues.append("攻击程序要求的素材能力无效")
    if kind != "attack": issues.append("攻击程序声明必须使用 attack 类别")
    return issues

func reference_collection() -> String: return "bosses" if capability=="SummonEnemy" else "bullets"

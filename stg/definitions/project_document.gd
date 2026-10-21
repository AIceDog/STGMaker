@tool
class_name STGProject
extends Resource
## 制作资产索引；只接收当前格式，运行状态不进入 Resource。
## Godot 注解：@tool 允许在编辑器执行，class_name 注册全局类型，@export 保存且显示字段。
const Copy = preload("res://stg/definitions/config_copy.gd")
const Validation = preload("res://stg/definitions/validation.gd")
const References = preload("res://stg/definitions/resource_references.gd")
const VERSION = preload("res://stg/definitions/asset_schema.gd").VERSION
@export var behavior_presets: Array[STGBehaviorPreset] = []
@export var attack_presets: Array[STGAttackPreset] = []
@export var schema_version: int = 0 # 必须显式写入当前版本；省略版本的文件不属于此格式。
@export var bullets: Array[STGBulletDefinition] = []
@export var barrages: Array[STGBarrageSkill] = []
@export var behaviors: Array[STGBehaviorFlow] = []
@export var bosses: Array[STGBossDefinition] = []
@export var waves: Array[STGWaveDefinition] = []
@export var levels: Array[STGLevelDefinition] = []
@export var obstacles: Array[STGObstacleDefinition] = []

static func create() -> Resource:
    # 避免静态工厂构造器和返回类型同时持有自己的脚本；实际对象仍为 STGProject。
    var project = load("res://stg/definitions/project_document.gd").new()
    project.schema_version = VERSION
    return project

func snapshot() -> Resource:
    # 自定义快照接口：复制可编辑配置，贴图 / 场景等只读资源继续共享。
    return Copy.copy(self)

func find(collection: String, id: String) -> Resource:
    if collection not in References.COLLECTIONS:
        return null
    for value in get(collection):
        if value != null and value.id == id:
            return value
    return null

func validate() -> PackedStringArray:
    return Validation.check(self)

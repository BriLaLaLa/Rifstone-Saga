extends Resource
class_name Skill

@export var id: String = ""
@export var name: String = "Skill"
@export var category: String = "profession" # "profession" | "combat" | "passive"
@export var level: int = 1
@export var xp: float = 0.0
@export var xp_curve: String = "linear_easy"
@export var grade: String = "N" # N/A/M/G
@export var actions: Array = []  # list of action ids
@export var bonuses: Array = []  # [{"type":"...", "value":...}]
@export var icon: String = ""   # path a texture opzionale

# ancora compatibili con la vecchia base
@export var rate: float = 0.0
@export var threshold: float = 10.0
@export var reward_gold: int = 0
@export var yields: Dictionary = {}

var progress: float = 0.0
var is_training: bool = false

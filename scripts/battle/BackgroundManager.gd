extends Node
class_name BackgroundManager

## Manages battle backgrounds and spawn point configurations
## Loads from data/battle_backgrounds.json and provides random background selection
## Path: res://scripts/battle/BackgroundManager.gd

# ==================== CONSTANTS ====================
const BACKGROUND_DATA_PATH = "res://data/battle_backgrounds.json"

# ==================== INTERNAL VARIABLES ====================
var background_data: Dictionary = {}
var background_keys: Array = []
var current_background_key: String = ""
var current_background_config: Dictionary = {}

# ==================== INITIALIZATION ====================

func _ready() -> void:
	_load_background_data()
	if GameLogger.ENABLED:
		print("[BackgroundManager] Ready - %d backgrounds loaded" % background_keys.size())

func _load_background_data() -> void:
	"""Load background configuration from JSON file"""
	var file = FileAccess.open(BACKGROUND_DATA_PATH, FileAccess.READ)
	if not file:
		push_error("[BackgroundManager] Failed to load background data from: %s" % BACKGROUND_DATA_PATH)
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_error("[BackgroundManager] Failed to parse background JSON: %s" % json.get_error_message())
		return

	background_data = json.data

	# Extract background keys for random selection
	if background_data.has("backgrounds"):
		background_keys = background_data.backgrounds.keys()

	if GameLogger.ENABLED:
		print("[BackgroundManager] Loaded %d backgrounds: %s" % [background_keys.size(), background_keys])

# ==================== PUBLIC API ====================

func get_random_background() -> Dictionary:
	"""
	Select a random background and return its configuration
	Returns: {
		"key": "m1_z1_1",
		"scene_path": "res://scenes/battle/backgrounds/...",
		"texture_path": "res://Item_Texture/Backgrounds/...",
		"description": "..."
	}
	"""
	if background_keys.is_empty():
		push_error("[BackgroundManager] No backgrounds available!")
		return {}

	# Select random background
	var random_index = randi() % background_keys.size()
	current_background_key = background_keys[random_index]
	current_background_config = background_data.backgrounds[current_background_key].duplicate(true)
	current_background_config["key"] = current_background_key

	if GameLogger.ENABLED:
		print("[BackgroundManager] Selected background: %s (%s)" % [current_background_key, current_background_config.get("description", "")])

	return current_background_config

func get_background_by_key(key: String) -> Dictionary:
	"""Get specific background by key (for testing/debugging)"""
	if not background_data.backgrounds.has(key):
		push_error("[BackgroundManager] Background key not found: %s" % key)
		return {}

	current_background_key = key
	current_background_config = background_data.backgrounds[key].duplicate(true)
	current_background_config["key"] = key

	return current_background_config

func get_current_background() -> Dictionary:
	"""Get currently selected background configuration"""
	return current_background_config

func get_scene_path() -> String:
	"""Get the scene path for current background"""
	if current_background_config.is_empty():
		return ""
	return current_background_config.get("scene_path", "")

func get_texture_path() -> String:
	"""Get the texture path for current background"""
	if current_background_config.is_empty():
		return ""
	return current_background_config.get("texture_path", "")

func load_battlefield_scene() -> Control:
	"""
	Load and instantiate the current battlefield scene
	Returns: Control node with BackgroundTexture and SpawnPoints
	"""
	var scene_path = get_scene_path()
	if scene_path == "":
		push_error("[BackgroundManager] No scene path for current background!")
		return null

	if not ResourceLoader.exists(scene_path):
		push_error("[BackgroundManager] Battlefield scene not found: %s" % scene_path)
		return null

	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("[BackgroundManager] Failed to load battlefield scene: %s" % scene_path)
		return null

	var battlefield = packed_scene.instantiate() as Control
	if not battlefield:
		push_error("[BackgroundManager] Failed to instantiate battlefield scene!")
		return null

	if GameLogger.ENABLED:
		print("[BackgroundManager] ✅ Loaded battlefield scene: %s" % current_background_key)

	return battlefield

# ==================== DEBUG HELPERS ====================

func print_current_config() -> void:
	"""Print current background configuration (for debugging)"""
	print("\n[BackgroundManager] Current Configuration:")
	print("  Key: %s" % current_background_key)
	print("  Scene Path: %s" % current_background_config.get("scene_path", "N/A"))
	print("  Texture Path: %s" % current_background_config.get("texture_path", "N/A"))
	print("  Description: %s" % current_background_config.get("description", "N/A"))

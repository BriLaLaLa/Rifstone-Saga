# File: res://scripts/battle/EnemyDatabase.gd
# Database for enemy stats, icons, and drops
# Singleton autoload for global access

extends Node

# Enemy data cache
var enemies: Dictionary = {}

# ==================== INITIALIZATION ====================

func _ready() -> void:
	_load_enemy_data()

func _load_enemy_data() -> void:
	"""Load enemy data from JSON file"""
	var file_path = "res://data/enemies.json"

	if not FileAccess.file_exists(file_path):
		push_error("[EnemyDatabase] enemies.json not found at: %s" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[EnemyDatabase] Failed to open enemies.json")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		push_error("[EnemyDatabase] Failed to parse enemies.json: %s" % json.get_error_message())
		return

	var data = json.get_data()

	if not data.has("enemies"):
		push_error("[EnemyDatabase] No 'enemies' key in JSON data")
		return

	enemies = data["enemies"]

	if GameLogger.ENABLED:
		print("[EnemyDatabase] ✅ Loaded %d enemy types" % enemies.size())
		for enemy_id in enemies.keys():
			print("[EnemyDatabase]   - %s" % enemy_id)

# ==================== ENEMY DATA RETRIEVAL ====================

func get_enemy_data(enemy_id: String) -> Dictionary:
	"""Get full data for an enemy type"""
	if not enemies.has(enemy_id):
		push_warning("[EnemyDatabase] Unknown enemy type: %s" % enemy_id)
		return _get_fallback_enemy_data(enemy_id)

	return enemies[enemy_id].duplicate(true)

func get_enemy_stats(enemy_id: String, level: int = 1) -> Dictionary:
	"""Get calculated stats for an enemy at a given level"""
	var enemy_data = get_enemy_data(enemy_id)

	# Calculate level-scaled stats
	var base_hp = float(enemy_data.get("base_hp", 100))
	var base_attack = float(enemy_data.get("base_attack", 5))

	# HP scaling: +10% per level
	var scaled_hp = base_hp * (1.0 + (level - 1) * 0.1)

	# Attack scaling: +5% per level
	var scaled_attack = base_attack * (1.0 + (level - 1) * 0.05)

	return {
		"name": enemy_data.get("name", "Unknown"),
		"hp": int(scaled_hp),
		"attack": scaled_attack,
		"attack_speed": enemy_data.get("attack_speed", 2.0),
		"icon": enemy_data.get("icon", ""),
		"type": enemy_data.get("type", "normal"),
		"level": level,
		"is_boss": enemy_data.get("type") == "boss" or enemy_data.get("type") == "metin",
		"is_metin": enemy_data.get("type") == "metin",
		"special_mechanics": enemy_data.get("special_mechanics", {}),
		"drops": enemy_data.get("drops", {})
	}

func _get_fallback_enemy_data(enemy_id: String) -> Dictionary:
	"""Return fallback data for unknown enemies"""
	return {
		"id": enemy_id,
		"name": enemy_id.capitalize(),
		"type": "normal",
		"base_hp": 100,
		"base_attack": 5,
		"attack_speed": 2.0,
		"icon": "",
		"drops": {
			"gold_min": 5,
			"gold_max": 15,
			"xp_min": 10,
			"xp_max": 30,
			"item_drop_chance": 0.1,
			"rare_item_multiplier": 1.0
		}
	}

# ==================== DROP CALCULATION ====================

func calculate_drops(enemy_id: String, level: int = 1) -> Dictionary:
	"""Calculate what this enemy should drop"""
	var enemy_data = get_enemy_data(enemy_id)
	var drop_data = enemy_data.get("drops", {})

	# Calculate gold drop
	var gold_min = int(drop_data.get("gold_min", 5)) * level
	var gold_max = int(drop_data.get("gold_max", 15)) * level
	var gold = randi_range(gold_min, gold_max)

	# Calculate XP drop
	var xp_min = int(drop_data.get("xp_min", 10)) * level
	var xp_max = int(drop_data.get("xp_max", 30)) * level
	var xp = randi_range(xp_min, xp_max)

	# Item drop chance
	var item_drop_chance = float(drop_data.get("item_drop_chance", 0.1))
	var rare_multiplier = float(drop_data.get("rare_item_multiplier", 1.0))

	var drops = {
		"gold": gold,
		"xp": xp,
		"items": []
	}

	# Roll for item drop
	if randf() < item_drop_chance:
		var item = _roll_random_item(level, rare_multiplier)
		if item != "":
			drops["items"].append(item)

	return drops

func _roll_random_item(level: int, rare_multiplier: float) -> String:
	"""Roll a random item based on level and rarity multiplier"""
	# Get all available items from ItemDatabase
	var item_db = get_node_or_null("/root/ItemDatabase")
	if not item_db:
		return ""

	var all_items = item_db.items.keys()
	if all_items.is_empty():
		return ""

	# Filter items by level (simple implementation - can be enhanced)
	var valid_items = []
	for item_id in all_items:
		var item_data = item_db.get_item_data(item_id)
		var item_level = int(item_data.get("level", 1))

		# Item can drop if it's within ±3 levels
		if abs(item_level - level) <= 3:
			valid_items.append(item_id)

	if valid_items.is_empty():
		# Fallback: just pick random item
		return all_items.pick_random()

	return valid_items.pick_random()

# ==================== SPECIAL MECHANICS ====================

func has_spawn_mechanic(enemy_id: String) -> bool:
	"""Check if enemy has add-spawning mechanic (like Metin)"""
	var enemy_data = get_enemy_data(enemy_id)
	var mechanics = enemy_data.get("special_mechanics", {})
	return mechanics.get("spawn_adds", false)

func get_spawn_thresholds(enemy_id: String) -> Array:
	"""Get HP thresholds where adds spawn"""
	var enemy_data = get_enemy_data(enemy_id)
	var mechanics = enemy_data.get("special_mechanics", {})
	return mechanics.get("spawn_thresholds", [])

func get_spawn_info(enemy_id: String) -> Dictionary:
	"""Get full spawn mechanic info"""
	var enemy_data = get_enemy_data(enemy_id)
	return enemy_data.get("special_mechanics", {})

# ==================== UTILITY ====================

func get_all_enemy_ids() -> Array:
	"""Get list of all enemy IDs"""
	return enemies.keys()

func enemy_exists(enemy_id: String) -> bool:
	"""Check if enemy type exists"""
	return enemies.has(enemy_id)

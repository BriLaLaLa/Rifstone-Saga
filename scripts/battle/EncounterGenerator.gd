# File: res://scripts/battle/EncounterGenerator.gd
# Generates combat encounters with proper composition and slot allocation
# Integrates with PitySystem for dynamic probabilities

extends Node
class_name EncounterGenerator

# const LOG removed - using GameLogger

# ==================== REFERENCES ====================

var pity_system: PitySystem = null

# ==================== CONFIGURATION ====================

# Zone configuration
var zone_level_min: int = 1
var zone_level_max: int = 10
var zone_enemy_pool: Array[String] = []
var zone_boss_pool: Array[String] = []
var zone_metin_pool: Array[String] = []

# Encounter composition limits
const NORMAL_COUNT_MIN: int = 3
const NORMAL_COUNT_MAX: int = 12
const MINIBOSS_COMPANIONS_MIN: int = 1
const MINIBOSS_COMPANIONS_MAX: int = 3

# Boss level boost
const BOSS_LEVEL_BOOST: int = 2
const METIN_LEVEL_BOOST: int = 3

# Last generated encounter (for testing/debugging)
var last_encounter: Dictionary = {}

# ==================== INITIALIZATION ====================

func _init():
	pass

func set_pity_system(pity: PitySystem) -> void:
	"""Set the pity system reference"""
	pity_system = pity

	if GameLogger.ENABLED:
		print("[EncounterGenerator] Pity system connected")

func set_zone_config(config: Dictionary) -> void:
	"""Configure generator for a specific zone"""
	if config.has("level_range"):
		var range_array = config["level_range"]
		zone_level_min = range_array[0]
		zone_level_max = range_array[1]

	if config.has("enemies"):
		zone_enemy_pool.clear()
		for enemy in config["enemies"]:
			zone_enemy_pool.append(enemy)

	if config.has("boss_types"):
		zone_boss_pool.clear()
		for boss in config["boss_types"]:
			zone_boss_pool.append(boss)
	else:
		# Default: Use enemy pool with "_boss" suffix
		zone_boss_pool.clear()
		for enemy in zone_enemy_pool:
			zone_boss_pool.append(enemy + "_boss")

	if config.has("metin_types"):
		zone_metin_pool.clear()
		for metin in config["metin_types"]:
			zone_metin_pool.append(metin)
	else:
		# Default: Generic metin
		zone_metin_pool = ["metin"]

	if GameLogger.ENABLED:
		print("[EncounterGenerator] Zone configured: Lv%d-%d, %d enemies, %d bosses, %d metins" %
			[zone_level_min, zone_level_max, zone_enemy_pool.size(), zone_boss_pool.size(), zone_metin_pool.size()])

func set_zone_level_range(min_level: int, max_level: int) -> void:
	"""Set zone level range"""
	zone_level_min = min_level
	zone_level_max = max_level

func set_zone_enemy_pool(enemies: Array) -> void:
	"""Set available enemies for this zone"""
	zone_enemy_pool.clear()
	for enemy in enemies:
		zone_enemy_pool.append(enemy)

# ==================== ENCOUNTER GENERATION ====================

func generate_with_pity() -> Dictionary:
	"""Generate encounter using pity system probabilities"""
	if not pity_system:
		push_error("[EncounterGenerator] No pity system set!")
		return generate_encounter("normal")

	# Use pity system to determine encounter type
	var encounter_type = pity_system.generate_encounter()

	if GameLogger.ENABLED:
		print("[EncounterGenerator] Generated encounter type: %s" % encounter_type)

	# Generate encounter composition
	var encounter = generate_encounter(encounter_type)

	# Update pity counters
	pity_system.on_encounter_result(encounter_type)

	return encounter

func generate_encounter(encounter_type: String) -> Dictionary:
	"""Generate encounter composition based on type"""

	var encounter = {}

	match encounter_type:
		"normal":
			encounter = _generate_normal_encounter()
		"miniboss":
			encounter = _generate_miniboss_encounter()
		"metin":
			encounter = _generate_metin_encounter()
		_:
			push_error("[EncounterGenerator] Invalid encounter type: %s" % encounter_type)
			return {}

	# Add gathering node (30-40% chance) - ONLY for NORMAL encounters
	if encounter_type == "normal":
		var should_spawn = GatheringDatabase.should_spawn_node() if GatheringDatabase else false

		if should_spawn:
			var node_type = GatheringDatabase.get_random_node_type() if GatheringDatabase else "mining_node"
			encounter["gathering_node"] = node_type

			print("[GATHERING] 🌿 Gathering node will spawn: %s" % node_type)

	return encounter

# ==================== NORMAL ENCOUNTER ====================

func _generate_normal_encounter() -> Dictionary:
	"""Generate normal encounter: 3-12 random enemies"""

	# Random count between 3-12
	var count = randi_range(NORMAL_COUNT_MIN, NORMAL_COUNT_MAX)

	var enemies: Array = []

	for i in range(count):
		var enemy = _create_normal_enemy()
		enemies.append(enemy)

	var encounter = {
		"type": "normal",
		"enemies": enemies
	}

	last_encounter = encounter

	if GameLogger.ENABLED:
		print("[EncounterGenerator] ⚔️ Normal encounter: %d enemies" % count)

	return encounter

func _create_normal_enemy() -> Dictionary:
	"""Create a single normal enemy"""

	if zone_enemy_pool.is_empty():
		push_warning("[EncounterGenerator] Empty enemy pool, using default")
		return {
			"type": "slime",
			"level": _roll_level(),
			"is_boss": false
		}

	var enemy_type = zone_enemy_pool.pick_random()
	var level = _roll_level()

	return {
		"type": enemy_type,
		"level": level,
		"is_boss": false
	}

# ==================== MINIBOSS ENCOUNTER ====================

func _generate_miniboss_encounter() -> Dictionary:
	"""Generate miniboss encounter: 1 boss + 1-3 companions"""

	# 1 Boss
	var boss = _create_boss_enemy()

	# 1-3 Companions
	var companion_count = randi_range(MINIBOSS_COMPANIONS_MIN, MINIBOSS_COMPANIONS_MAX)
	var companions: Array = []

	for i in range(companion_count):
		var companion = _create_normal_enemy()
		companions.append(companion)

	var encounter = {
		"type": "miniboss",
		"boss": boss,
		"companions": companions
	}

	last_encounter = encounter

	if GameLogger.ENABLED:
		print("[EncounterGenerator] 👹 Miniboss encounter: 1 boss + %d companions" % companion_count)

	return encounter

func _create_boss_enemy() -> Dictionary:
	"""Create a boss enemy (higher level)"""

	if zone_boss_pool.is_empty():
		push_warning("[EncounterGenerator] Empty boss pool, using default 'scrofa'")
		return {
			"type": "scrofa",  # Default boss fallback
			"level": min(zone_level_max, _roll_level() + BOSS_LEVEL_BOOST),
			"is_boss": true
		}

	var boss_type = zone_boss_pool.pick_random()
	var level = min(zone_level_max, _roll_level() + BOSS_LEVEL_BOOST)

	return {
		"type": boss_type,
		"level": level,
		"is_boss": true
	}

# ==================== METIN ENCOUNTER ====================

func _generate_metin_encounter() -> Dictionary:
	"""Generate metin encounter: 1 metin only (solo)"""

	var metin = _create_metin_enemy()

	var encounter = {
		"type": "metin",
		"metin": metin
	}

	last_encounter = encounter

	if GameLogger.ENABLED:
		print("[EncounterGenerator] 💎 Metin encounter: Solo metin")

	return encounter

func _create_metin_enemy() -> Dictionary:
	"""Create a metin enemy (very high level, solo)"""

	if zone_metin_pool.is_empty():
		push_warning("[EncounterGenerator] Empty metin pool, using default")
		return {
			"type": "metin",
			"level": min(zone_level_max, _roll_level() + METIN_LEVEL_BOOST),
			"is_boss": true,
			"is_metin": true
		}

	var metin_type = zone_metin_pool.pick_random()
	var level = min(zone_level_max, _roll_level() + METIN_LEVEL_BOOST)

	return {
		"type": metin_type,
		"level": level,
		"is_boss": true,
		"is_metin": true
	}

# ==================== SLOT ALLOCATION ====================

func get_slot_allocation(encounter: Dictionary) -> Dictionary:
	"""Get slot allocation for an encounter"""

	var slot_data = {
		"boss_slot": null,
		"normal_slots": []
	}

	match encounter["type"]:
		"normal":
			# All enemies in normal slots, boss slot empty
			slot_data["normal_slots"] = encounter["enemies"]
			slot_data["boss_slot"] = null

		"miniboss":
			# Boss in boss slot, companions in normal slots
			slot_data["boss_slot"] = encounter["boss"]
			slot_data["normal_slots"] = encounter["companions"]

		"metin":
			# Metin in boss slot, no normal slots
			slot_data["boss_slot"] = encounter["metin"]
			slot_data["normal_slots"] = []

	if GameLogger.ENABLED:
		print("[EncounterGenerator] Slot allocation: Boss=%s, Normal=%d" %
			[slot_data["boss_slot"] != null, slot_data["normal_slots"].size()])

	return slot_data

# ==================== UTILITY ====================

func _roll_level() -> int:
	"""Roll random level within zone range"""
	return randi_range(zone_level_min, zone_level_max)

func get_last_generated_encounter() -> Dictionary:
	"""Get last generated encounter (for testing)"""
	return last_encounter

# ==================== DEBUG ====================

func get_debug_info() -> String:
	"""Get formatted debug info"""
	return """[EncounterGenerator Debug]
Zone Level Range: %d-%d
Enemy Pool: %s
Boss Pool: %s
Metin Pool: %s
Last Encounter Type: %s
""" % [
		zone_level_min,
		zone_level_max,
		str(zone_enemy_pool),
		str(zone_boss_pool),
		str(zone_metin_pool),
		last_encounter.get("type", "none")
	]

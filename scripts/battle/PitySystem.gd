# File: res://scripts/battle/PitySystem.gd
# Dynamic Pity System for Rare Encounter Generation
# Increases rare encounter probabilities after consecutive failures

extends Node
class_name PitySystem

# const LOG removed - using GameLogger

# ==================== CONFIGURATION ====================

# Base probabilities (must sum to 100)
const BASE_PROB_NORMAL: float = 80.0
const BASE_PROB_MINIBOSS: float = 15.0
const BASE_PROB_METIN: float = 5.0

# Pity system parameters
const PITY_INCREMENT: float = 2.0  # % increase per failure
const MINIBOSS_MAX_CAP: float = 40.0  # Cap at 40%
const METIN_MAX_CAP: float = 20.0  # Cap at 20%

# Failure threshold before pity kicks in
const PITY_THRESHOLD: int = 0  # Start increasing immediately

# ==================== STATE ====================

# Failure counters (independent for each rare type)
var miniboss_failure_counter: int = 0
var metin_failure_counter: int = 0

# Current adjusted probabilities
var current_probabilities: Dictionary = {
	"normal": BASE_PROB_NORMAL,
	"miniboss": BASE_PROB_MINIBOSS,
	"metin": BASE_PROB_METIN
}

# Signals
signal probabilities_changed(probabilities: Dictionary)
signal rare_encounter_spawned(encounter_type: String)

# ==================== INITIALIZATION ====================

func _ready() -> void:
	_recalculate_probabilities()

	if GameLogger.ENABLED:
		print("[PitySystem] Initialized - Base: Normal=%.1f%%, Miniboss=%.1f%%, Metin=%.1f%%" %
			[BASE_PROB_NORMAL, BASE_PROB_MINIBOSS, BASE_PROB_METIN])

# ==================== PROBABILITY CALCULATION ====================

func _recalculate_probabilities() -> void:
	"""Recalculate current probabilities based on failure counters"""

	# Calculate boosted rare probabilities
	var miniboss_boost = 0.0
	if miniboss_failure_counter > PITY_THRESHOLD:
		miniboss_boost = min(
			(miniboss_failure_counter - PITY_THRESHOLD) * PITY_INCREMENT,
			MINIBOSS_MAX_CAP - BASE_PROB_MINIBOSS
		)

	var metin_boost = 0.0
	if metin_failure_counter > PITY_THRESHOLD:
		metin_boost = min(
			(metin_failure_counter - PITY_THRESHOLD) * PITY_INCREMENT,
			METIN_MAX_CAP - BASE_PROB_METIN
		)

	# Apply boosts
	var new_miniboss = BASE_PROB_MINIBOSS + miniboss_boost
	var new_metin = BASE_PROB_METIN + metin_boost

	# Cap at maximums
	new_miniboss = min(new_miniboss, MINIBOSS_MAX_CAP)
	new_metin = min(new_metin, METIN_MAX_CAP)

	# Normal probability = remainder to keep sum at 100%
	var new_normal = 100.0 - new_miniboss - new_metin

	# Update current probabilities
	current_probabilities = {
		"normal": new_normal,
		"miniboss": new_miniboss,
		"metin": new_metin
	}

	if GameLogger.ENABLED and (miniboss_boost > 0 or metin_boost > 0):
		print("[PitySystem] 📈 Probabilities adjusted: Normal=%.1f%%, Miniboss=%.1f%% (+%.1f), Metin=%.1f%% (+%.1f)" %
			[new_normal, new_miniboss, miniboss_boost, new_metin, metin_boost])

	probabilities_changed.emit(current_probabilities)

# ==================== PUBLIC API ====================

func get_current_probability(encounter_type: String) -> float:
	"""Get current probability for an encounter type"""
	return current_probabilities.get(encounter_type, 0.0)

func get_miniboss_counter() -> int:
	"""Get current miniboss failure counter"""
	return miniboss_failure_counter

func get_metin_counter() -> int:
	"""Get current metin failure counter"""
	return metin_failure_counter

func get_base_probability(encounter_type: String) -> float:
	"""Get base probability for an encounter type (before pity)"""
	match encounter_type:
		"normal":
			return BASE_PROB_NORMAL
		"miniboss":
			return BASE_PROB_MINIBOSS
		"metin":
			return BASE_PROB_METIN
		_:
			return 0.0

# ==================== ENCOUNTER GENERATION ====================

func generate_encounter() -> String:
	"""Generate encounter type based on current probabilities"""

	# Roll random number 0-100
	var roll = randf() * 100.0

	# Check ranges (order matters - check rarest first for precision)
	var metin_chance = current_probabilities["metin"]
	var miniboss_chance = current_probabilities["miniboss"] + metin_chance
	var normal_chance = 100.0  # Everything else

	if roll < metin_chance:
		return "metin"
	elif roll < miniboss_chance:
		return "miniboss"
	else:
		return "normal"

# ==================== PITY TRACKING ====================

func on_encounter_result(encounter_type: String) -> void:
	"""Update pity counters based on encounter result"""

	match encounter_type:
		"normal":
			# Failed to get both rares - increment both counters
			miniboss_failure_counter += 1
			metin_failure_counter += 1

			if GameLogger.ENABLED:
				print("[PitySystem] Normal encounter - Counters: Miniboss=%d, Metin=%d" %
					[miniboss_failure_counter, metin_failure_counter])

		"miniboss":
			# Got miniboss - reset only miniboss counter
			if GameLogger.ENABLED and miniboss_failure_counter > 0:
				print("[PitySystem] ✨ Miniboss spawned! Resetting miniboss counter (was %d)" % miniboss_failure_counter)

			miniboss_failure_counter = 0
			# Metin counter unchanged (independent counters)

			rare_encounter_spawned.emit("miniboss")

		"metin":
			# Got metin - reset only metin counter
			if GameLogger.ENABLED and metin_failure_counter > 0:
				print("[PitySystem] 💎 Metin spawned! Resetting metin counter (was %d)" % metin_failure_counter)

			metin_failure_counter = 0
			# Miniboss counter unchanged (independent counters)

			rare_encounter_spawned.emit("metin")

		_:
			push_warning("[PitySystem] Invalid encounter type: %s" % encounter_type)
			return

	# Recalculate probabilities for next encounter
	_recalculate_probabilities()

# ==================== UTILITY ====================

func reset_all() -> void:
	"""Reset all pity counters to 0"""
	miniboss_failure_counter = 0
	metin_failure_counter = 0
	_recalculate_probabilities()

	if GameLogger.ENABLED:
		print("[PitySystem] All counters reset")

func get_pity_info() -> Dictionary:
	"""Get detailed pity info for UI display"""
	return {
		"miniboss": {
			"counter": miniboss_failure_counter,
			"probability": current_probabilities["miniboss"],
			"base_probability": BASE_PROB_MINIBOSS,
			"boost": current_probabilities["miniboss"] - BASE_PROB_MINIBOSS
		},
		"metin": {
			"counter": metin_failure_counter,
			"probability": current_probabilities["metin"],
			"base_probability": BASE_PROB_METIN,
			"boost": current_probabilities["metin"] - BASE_PROB_METIN
		}
	}

# ==================== PERSISTENCE ====================

func save_state() -> Dictionary:
	"""Save pity state to dictionary"""
	return {
		"miniboss_counter": miniboss_failure_counter,
		"metin_counter": metin_failure_counter
	}

func load_state(state: Dictionary) -> void:
	"""Load pity state from dictionary"""
	miniboss_failure_counter = state.get("miniboss_counter", 0)
	metin_failure_counter = state.get("metin_counter", 0)

	_recalculate_probabilities()

	if GameLogger.ENABLED:
		print("[PitySystem] State loaded - Counters: Miniboss=%d, Metin=%d" %
			[miniboss_failure_counter, metin_failure_counter])

# ==================== DEBUG ====================

func get_debug_info() -> String:
	"""Get formatted debug info string"""
	return """[PitySystem Debug]
Counters: Miniboss=%d, Metin=%d
Current Probabilities:
  Normal: %.1f%%
  Miniboss: %.1f%% (base: %.1f%%, boost: +%.1f%%)
  Metin: %.1f%% (base: %.1f%%, boost: +%.1f%%)
""" % [
		miniboss_failure_counter,
		metin_failure_counter,
		current_probabilities["normal"],
		current_probabilities["miniboss"],
		BASE_PROB_MINIBOSS,
		current_probabilities["miniboss"] - BASE_PROB_MINIBOSS,
		current_probabilities["metin"],
		BASE_PROB_METIN,
		current_probabilities["metin"] - BASE_PROB_METIN
	]

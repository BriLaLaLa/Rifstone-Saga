# File: res://scripts/systems/LevelSystem.gd
# Sistema di livelli ed esperienza riutilizzabile
# Supporta curve di esperienza personalizzabili

class_name LevelSystem
extends RefCounted

# ==================== CONFIGURATION ====================
var max_level: int = 99
var base_exp_requirement: int = 100  # EXP per raggiungere livello 2
var exp_curve_multiplier: float = 1.15  # Moltiplicatore esponenziale per livello

# ==================== STATE ====================
var current_level: int = 1
var current_exp: int = 0
var exp_to_next_level: int = 100

# ==================== SIGNALS ====================
signal level_up(new_level: int)
signal exp_gained(amount: int, total_exp: int)
signal max_level_reached()

# ==================== INITIALIZATION ====================

func _init(initial_level: int = 1, initial_exp: int = 0, curve_multiplier: float = 1.15):
	"""Initialize level system

	Args:
		initial_level: Starting level (default 1)
		initial_exp: Starting exp (default 0)
		curve_multiplier: Exponential curve (default 1.15 = harder, 1.10 = easier)
	"""
	exp_curve_multiplier = curve_multiplier
	current_level = clamp(initial_level, 1, max_level)
	current_exp = initial_exp
	_calculate_exp_requirement()

# ==================== EXP & LEVELING ====================

func add_exp(amount: int) -> Dictionary:
	"""Add experience and handle level ups

	Returns:
		Dictionary with keys:
		- levels_gained: int (number of levels gained)
		- new_level: int (current level after gain)
		- exp_gained: int (actual exp gained)
	"""
	if current_level >= max_level:
		max_level_reached.emit()
		return {"levels_gained": 0, "new_level": current_level, "exp_gained": 0}

	current_exp += amount
	exp_gained.emit(amount, current_exp)

	var levels_gained = 0

	# Check for level ups (può salire più livelli se abbastanza EXP)
	while current_exp >= exp_to_next_level and current_level < max_level:
		current_exp -= exp_to_next_level
		current_level += 1
		levels_gained += 1

		level_up.emit(current_level)

		if current_level < max_level:
			_calculate_exp_requirement()
		else:
			max_level_reached.emit()
			current_exp = 0  # Reset exp at max level
			break

	return {
		"levels_gained": levels_gained,
		"new_level": current_level,
		"exp_gained": amount
	}

func _calculate_exp_requirement() -> void:
	"""Calculate EXP needed for next level based on curve"""
	if current_level >= max_level:
		exp_to_next_level = 0
		return

	# Exponential curve: base * (multiplier ^ (level - 1))
	exp_to_next_level = int(base_exp_requirement * pow(exp_curve_multiplier, current_level - 1))

# ==================== GETTERS ====================

func get_level() -> int:
	return current_level

func get_exp() -> int:
	return current_exp

func get_exp_to_next() -> int:
	return exp_to_next_level

func get_exp_progress_percent() -> float:
	"""Returns progress to next level as 0.0-1.0"""
	if exp_to_next_level == 0:
		return 1.0
	return float(current_exp) / float(exp_to_next_level)

func get_total_exp_for_level(level: int) -> int:
	"""Calculate total EXP needed to reach a specific level from level 1"""
	var total = 0
	for lvl in range(1, level):
		total += int(base_exp_requirement * pow(exp_curve_multiplier, lvl - 1))
	return total

func is_max_level() -> bool:
	return current_level >= max_level

# ==================== SERIALIZATION ====================

func to_dict() -> Dictionary:
	"""Export to dictionary for saving"""
	return {
		"current_level": current_level,
		"current_exp": current_exp,
		"exp_to_next_level": exp_to_next_level,
		"max_level": max_level,
		"base_exp_requirement": base_exp_requirement,
		"exp_curve_multiplier": exp_curve_multiplier
	}

func from_dict(data: Dictionary) -> void:
	"""Load from dictionary"""
	current_level = data.get("current_level", 1)
	current_exp = data.get("current_exp", 0)
	max_level = data.get("max_level", 99)
	base_exp_requirement = data.get("base_exp_requirement", 100)
	exp_curve_multiplier = data.get("exp_curve_multiplier", 1.15)
	_calculate_exp_requirement()

# ==================== DEBUG ====================

func print_level_table(levels: int = 10) -> void:
	"""Print EXP requirements for debugging"""
	print("[LevelSystem] Experience Table (first %d levels):" % levels)
	print("  Level | EXP Required | Total EXP")
	print("  ------|--------------|----------")

	var total = 0
	for lvl in range(1, min(levels + 1, max_level + 1)):
		var req = int(base_exp_requirement * pow(exp_curve_multiplier, lvl - 1))
		total += req
		print("  %-5d | %-12d | %d" % [lvl, req, total])

# File: res://scripts/systems/GatheringSkillsManager.gd
# Gestisce i livelli ed esperienza per le gathering skills
# Skills: Mining, Herbalism, Fishing

class_name GatheringSkillsManager
extends RefCounted

# ==================== CONSTANTS ====================
const SKILL_TYPES = ["mining", "herbalism", "fishing"]
const BASE_EXP_PER_ACTION = 20  # EXP guadagnata per azione
const GATHERING_CURVE = 1.10  # Curva più gentile del combat

# ==================== STATE ====================
var skill_systems: Dictionary = {}  # skill_name -> LevelSystem

# ==================== SIGNALS ====================
signal skill_level_up(skill_name: String, new_level: int)
signal skill_exp_gained(skill_name: String, amount: int, current_exp: int, exp_to_next: int)

# ==================== INITIALIZATION ====================

func _init():
	"""Initialize level systems for all gathering skills"""
	for skill in SKILL_TYPES:
		var level_sys = LevelSystem.new(1, 0, GATHERING_CURVE)
		level_sys.level_up.connect(_on_skill_level_up.bind(skill))
		level_sys.exp_gained.connect(_on_skill_exp_gained.bind(skill))
		skill_systems[skill] = level_sys

	if GameLogger.ENABLED:
		print("[GatheringSkillsManager] Initialized %d gathering skills" % SKILL_TYPES.size())

# ==================== EXPERIENCE ====================

func add_skill_exp(skill_name: String, amount: int = BASE_EXP_PER_ACTION) -> void:
	"""Add experience to a gathering skill

	Args:
		skill_name: "mining", "herbalism", or "fishing"
		amount: EXP amount (default BASE_EXP_PER_ACTION)
	"""
	if not skill_systems.has(skill_name):
		push_error("[GatheringSkillsManager] Unknown skill: %s" % skill_name)
		return

	skill_systems[skill_name].add_exp(amount)

func add_mining_exp(amount: int = BASE_EXP_PER_ACTION) -> void:
	"""Convenience function for mining"""
	add_skill_exp("mining", amount)

func add_herbalism_exp(amount: int = BASE_EXP_PER_ACTION) -> void:
	"""Convenience function for herbalism"""
	add_skill_exp("herbalism", amount)

func add_fishing_exp(amount: int = BASE_EXP_PER_ACTION) -> void:
	"""Convenience function for fishing"""
	add_skill_exp("fishing", amount)

# ==================== GETTERS ====================

func get_skill_level(skill_name: String) -> int:
	"""Get current level of a skill"""
	if skill_systems.has(skill_name):
		return skill_systems[skill_name].get_level()
	return 1

func get_skill_exp(skill_name: String) -> int:
	"""Get current EXP of a skill"""
	if skill_systems.has(skill_name):
		return skill_systems[skill_name].get_exp()
	return 0

func get_skill_exp_to_next(skill_name: String) -> int:
	"""Get EXP needed for next level"""
	if skill_systems.has(skill_name):
		return skill_systems[skill_name].get_exp_to_next()
	return 100

func get_skill_exp_progress(skill_name: String) -> float:
	"""Get progress to next level (0.0-1.0)"""
	if skill_systems.has(skill_name):
		return skill_systems[skill_name].get_exp_progress_percent()
	return 0.0

func get_all_skill_levels() -> Dictionary:
	"""Returns {skill_name: level} for all skills"""
	var levels = {}
	for skill in SKILL_TYPES:
		levels[skill] = get_skill_level(skill)
	return levels

# ==================== CALLBACKS ====================

func _on_skill_level_up(new_level: int, skill_name: String) -> void:
	"""Called when a skill levels up"""
	if GameLogger.ENABLED:
		print("[GatheringSkillsManager] 🎉 %s LEVEL UP! New level: %d" % [skill_name.capitalize(), new_level])

	skill_level_up.emit(skill_name, new_level)

func _on_skill_exp_gained(amount: int, total_exp: int, skill_name: String) -> void:
	"""Called when a skill gains EXP"""
	var exp_to_next = get_skill_exp_to_next(skill_name)
	skill_exp_gained.emit(skill_name, amount, get_skill_exp(skill_name), exp_to_next)

# ==================== SERIALIZATION ====================

func to_dict() -> Dictionary:
	"""Export all skills to dictionary"""
	var data = {}
	for skill in SKILL_TYPES:
		if skill_systems.has(skill):
			data[skill] = skill_systems[skill].to_dict()
	return data

func from_dict(data: Dictionary) -> void:
	"""Load all skills from dictionary"""
	for skill in SKILL_TYPES:
		if data.has(skill) and skill_systems.has(skill):
			skill_systems[skill].from_dict(data[skill])

	if GameLogger.ENABLED:
		print("[GatheringSkillsManager] Loaded skill levels:")
		for skill in SKILL_TYPES:
			print("  %s: Level %d" % [skill.capitalize(), get_skill_level(skill)])

# ==================== DEBUG ====================

func print_all_skills() -> void:
	"""Print current state of all skills"""
	print("\n=== GATHERING SKILLS ===")
	for skill in SKILL_TYPES:
		var level = get_skill_level(skill)
		var exp = get_skill_exp(skill)
		var to_next = get_skill_exp_to_next(skill)
		var progress = get_skill_exp_progress(skill) * 100.0
		print("%s: Level %d (EXP: %d/%d - %.1f%%)" %
			[skill.capitalize(), level, exp, to_next, progress])

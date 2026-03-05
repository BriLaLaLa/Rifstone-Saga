# File: res://scripts/battle/SkillDatabase.gd
# Database of all warrior skills
# Provides access to skill definitions

class_name SkillDatabase
extends RefCounted

const WarriorSkill = preload("res://scripts/battle/WarriorSkill.gd")

# Skill storage
var skills: Dictionary = {}  # skill_id -> WarriorSkill

# const LOG removed - using GameLogger

# ==================== INITIALIZATION ====================

func _init():
	_load_all_warrior_skills()

	if GameLogger.ENABLED:
		print("[SkillDatabase] Loaded %d warrior skills" % skills.size())

# ==================== SKILL ACCESS ====================

func get_skill(skill_id: String) -> WarriorSkill:
	"""Get a skill by ID (returns copy to avoid mutation)"""
	if not skills.has(skill_id):
		push_error("[SkillDatabase] Skill not found: %s" % skill_id)
		return null

	# Return a new instance from the template
	var template = skills[skill_id]
	return WarriorSkill.new(template.to_dict())

func has_skill(skill_id: String) -> bool:
	"""Check if skill exists"""
	return skills.has(skill_id)

func get_all_skill_ids() -> Array[String]:
	"""Get list of all skill IDs"""
	var ids: Array[String] = []
	for key in skills.keys():
		ids.append(key)
	return ids

# ==================== SKILL DEFINITIONS ====================

func _load_all_warrior_skills() -> void:
	"""Load all 6 warrior skill definitions"""

	# 1. BASIC ATTACK - Default fallback
	_register_skill({
		"id": "basic_attack",
		"name": "Attacco Base",
		"description": "Reliable basic attack. Used when all skills are on cooldown.",
		"icon_path": "res://Icons/Skills/Attacco_Base.png",
		"skill_type": "single",
		"max_targets": 1,
		"damage_min": 15,
		"damage_max": 20,
		"cooldown": 0.0,  # No cooldown - always available
		"cast_time": 0.3,
		"mana_cost": 0,
		"effects": [],
		"effect_values": {}
	})

	# 2. HISS (Sibilare) - Single Target + Stun
	_register_skill({
		"id": "hiss",
		"name": "Sibilare",
		"description": "Moderate damage + brief stun to single target.",
		"icon_path": "res://Icons/Skills/Sibilare.png",
		"skill_type": "single",
		"max_targets": 1,
		"damage_min": 25,
		"damage_max": 35,
		"cooldown": 8.0,
		"cast_time": 0.3,
		"mana_cost": 15,
		"duration": 1.5,  # Stun duration
		"effects": ["stun"],
		"effect_values": {
			"stun_duration": 1.5
		}
	})

	# 3. SWORD VORTEX (Vortice della Spada) - AOE
	_register_skill({
		"id": "sword_vortex",
		"name": "Vortice della Spada",
		"description": "Spinning sword attack hitting all enemies.",
		"icon_path": "res://Icons/Skills/Vortice_della_spada.png",
		"skill_type": "aoe",
		"max_targets": 999,  # All enemies
		"damage_min": 20,
		"damage_max": 30,
		"cooldown": 12.0,
		"cast_time": 0.3,
		"mana_cost": 25,
		"effects": [],
		"effect_values": {}
	})

	# 4. BATTLE CRY (Grido di Battaglia) - Self Buff
	_register_skill({
		"id": "battle_cry",
		"name": "Grido di Battaglia",
		"description": "Increase attack but reduce defense.",
		"icon_path": "res://Icons/Skills/Grido_di_battaglia.png",
		"skill_type": "self",
		"max_targets": 0,  # Self only
		"damage_min": 0,
		"damage_max": 0,
		"cooldown": 20.0,
		"cast_time": 0.3,
		"mana_cost": 20,
		"duration": 25.0,  # Buff duration
		"effects": ["buff_attack", "debuff_defense"],
		"effect_values": {
			"attack_percent": 40.0,  # +40% attack
			"defense_percent": -30.0  # -30% defense
		}
	})

	# 5. GUARD (Guardia) - Defense Buff
	_register_skill({
		"id": "guard",
		"name": "Guardia",
		"description": "Reduces incoming damage.",
		"icon_path": "res://Icons/Skills/Guardia.png",
		"skill_type": "self",
		"max_targets": 0,
		"damage_min": 0,
		"damage_max": 0,
		"cooldown": 20.0,
		"cast_time": 0.3,
		"mana_cost": 20,
		"duration": 30.0,  # Buff duration
		"effects": ["reduce_damage"],
		"effect_values": {
			"damage_reduction_percent": 50.0  # Reduce incoming damage by 50%
		}
	})

	# 6. THREE-WAY SLASH (Taglio a Tre Vie) - Multi-Target Defense Pierce
	_register_skill({
		"id": "three_way_slash",
		"name": "Taglio a Tre Vie",
		"description": "Moderate damage that bypasses physical defense.",
		"icon_path": "res://Icons/Skills/Taglio_a_tre_vie.png",
		"skill_type": "multi",
		"max_targets": 3,
		"damage_min": 30,
		"damage_max": 40,
		"cooldown": 10.0,
		"cast_time": 0.3,
		"mana_cost": 22,
		"effects": ["defense_pierce"],
		"effect_values": {}
	})

func _register_skill(data: Dictionary) -> void:
	"""Register a skill in the database"""
	var skill = WarriorSkill.new(data)
	skills[skill.id] = skill

	if GameLogger.ENABLED:
		print("[SkillDatabase] Registered: %s (%s)" % [skill.name, skill.id])

# ==================== DEBUG ====================

func print_all_skills() -> void:
	"""Print all skills for debugging"""
	print("\n=== WARRIOR SKILLS DATABASE ===")
	for skill_id in skills.keys():
		var skill = skills[skill_id]
		skill.print_info()
		print()


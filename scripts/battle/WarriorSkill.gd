# File: res://scripts/battle/WarriorSkill.gd
# Warrior Skill Data Structure
# Defines all properties and behavior of warrior combat skills

class_name WarriorSkill
extends RefCounted

# ==================== SKILL PROPERTIES ====================

# Identification
var id: String = ""
var name: String = ""
var description: String = ""
var icon_path: String = ""

# Type and targeting
var skill_type: String = "single"  # "single", "aoe", "multi", "self"
var max_targets: int = 1

# Damage
var damage_min: int = 0
var damage_max: int = 0

# Timing
var cooldown: float = 0.0
var cast_time: float = 0.3
var duration: float = 0.0  # For buffs/debuffs

# Resources
var mana_cost: int = 0

# Effects array - what this skill does
var effects: Array[String] = []

# Effect values - magnitude of effects
var effect_values: Dictionary = {}

# Current cooldown remaining (runtime state)
var current_cooldown: float = 0.0

# ==================== CONSTRUCTOR ====================

func _init(data: Dictionary = {}):
	if data.is_empty():
		return

	id = data.get("id", "")
	name = data.get("name", "")
	description = data.get("description", "")
	icon_path = data.get("icon_path", "")

	skill_type = data.get("skill_type", "single")
	max_targets = data.get("max_targets", 1)

	damage_min = data.get("damage_min", 0)
	damage_max = data.get("damage_max", 0)

	cooldown = data.get("cooldown", 0.0)
	cast_time = data.get("cast_time", 0.3)
	duration = data.get("duration", 0.0)

	mana_cost = data.get("mana_cost", 0)

	if data.has("effects") and data.effects is Array:
		for effect in data.effects:
			effects.append(effect)

	if data.has("effect_values"):
		effect_values = data.effect_values.duplicate()

# ==================== COOLDOWN MANAGEMENT ====================

func start_cooldown() -> void:
	"""Start the cooldown timer for this skill"""
	current_cooldown = cooldown

func update_cooldown(delta: float) -> void:
	"""Update cooldown - call every frame/tick"""
	if current_cooldown > 0:
		current_cooldown = max(0.0, current_cooldown - delta)

func is_on_cooldown() -> bool:
	"""Check if skill is currently on cooldown"""
	return current_cooldown > 0.0

func is_ready() -> bool:
	"""Check if skill is ready to cast"""
	return current_cooldown <= 0.0

func get_cooldown_remaining() -> float:
	"""Get remaining cooldown in seconds"""
	return current_cooldown

func get_cooldown_percent() -> float:
	"""Get cooldown progress as 0-1 value"""
	if cooldown <= 0.0:
		return 1.0
	return 1.0 - (current_cooldown / cooldown)

# ==================== EFFECT QUERIES ====================

func has_effect(effect_name: String) -> bool:
	"""Check if skill has a specific effect"""
	return effects.has(effect_name)

func get_effect_value(effect_name: String, default: float = 0.0) -> float:
	"""Get the value of a specific effect"""
	return effect_values.get(effect_name, default)

# ==================== DAMAGE CALCULATION ====================

func roll_damage() -> int:
	"""Roll random damage between min and max"""
	if damage_max <= damage_min:
		return damage_min
	return randi_range(damage_min, damage_max)

func get_average_damage() -> float:
	"""Get average damage for UI display"""
	return (damage_min + damage_max) / 2.0

# ==================== VALIDATION ====================

func can_cast(player_mana: float) -> bool:
	"""Check if this skill can be cast right now"""
	if is_on_cooldown():
		return false
	if player_mana < mana_cost:
		return false
	return true

# ==================== SERIALIZATION ====================

func to_dict() -> Dictionary:
	"""Convert to dictionary for saving/loading"""
	return {
		"id": id,
		"name": name,
		"description": description,
		"icon_path": icon_path,
		"skill_type": skill_type,
		"max_targets": max_targets,
		"damage_min": damage_min,
		"damage_max": damage_max,
		"cooldown": cooldown,
		"cast_time": cast_time,
		"duration": duration,
		"mana_cost": mana_cost,
		"effects": effects.duplicate(),
		"effect_values": effect_values.duplicate(),
		"current_cooldown": current_cooldown
	}

func from_dict(data: Dictionary) -> void:
	"""Load from dictionary"""
	_init(data)
	current_cooldown = data.get("current_cooldown", 0.0)

# ==================== DEBUG ====================

func print_info() -> void:
	"""Print skill info for debugging"""
	print("=== %s ===" % name)
	print("ID: %s" % id)
	print("Type: %s" % skill_type)
	print("Damage: %d-%d" % [damage_min, damage_max])
	print("Cooldown: %.1fs" % cooldown)
	print("Cast Time: %.1fs" % cast_time)
	print("Mana Cost: %d" % mana_cost)
	print("Effects: %s" % effects)
	print("Description: %s" % description)

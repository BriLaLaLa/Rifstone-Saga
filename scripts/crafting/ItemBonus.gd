# File: res://scripts/crafting/ItemBonus.gd
# Rappresenta un singolo bonus su un item (Prefix, Suffix o Special)

extends Resource
class_name ItemBonus

enum BonusType {
	PREFIX,
	SUFFIX,
	SPECIAL
}

enum BonusStat {
	# PREFIX
	PHYSICAL_DAMAGE,
	ATTACK_SPEED,

	# SUFFIX
	HP_REGEN,
	AUTO_HEAL_ON_DAMAGE,

	# SPECIAL
	MOMENTUM
}

# Proprietà del bonus
var bonus_type: BonusType
var bonus_stat: BonusStat
var tier: int = 1  # T1 - T7
var value1: float = 0.0  # Valore principale (es: +10% Physical Damage)
var value2: float = 0.0  # Valore secondario (es: chance per auto-heal)

# ==================== SERIALIZATION ====================

func to_dict() -> Dictionary:
	return {
		"bonus_type": bonus_type,
		"bonus_stat": bonus_stat,
		"tier": tier,
		"value1": value1,
		"value2": value2
	}

func from_dict(data: Dictionary) -> void:
	bonus_type = data.get("bonus_type", BonusType.PREFIX)
	bonus_stat = data.get("bonus_stat", BonusStat.PHYSICAL_DAMAGE)
	tier = data.get("tier", 1)
	value1 = data.get("value1", 0.0)
	value2 = data.get("value2", 0.0)

# ==================== DISPLAY ====================

func get_display_text() -> String:
	"""Genera il testo da mostrare nel tooltip"""
	match bonus_stat:
		BonusStat.PHYSICAL_DAMAGE:
			return "+%.1f%% Physical Damage" % value1
		BonusStat.ATTACK_SPEED:
			return "+%.1f%% Attack Speed" % value1
		BonusStat.HP_REGEN:
			return "+%.1f HP Regen/s" % value1
		BonusStat.AUTO_HEAL_ON_DAMAGE:
			return "%.1f%% chance to heal %.1f%% HP on damage" % [value1, value2]
		BonusStat.MOMENTUM:
			return "+%.2f%% damage every %ds (max %d stacks)" % [value1, int(value2), int(tier + 4)]

	return "Unknown bonus"

func get_tier_name() -> String:
	"""Restituisce il nome del tier (T1-T7)"""
	return "T%d" % tier

func get_color() -> Color:
	"""Restituisce il colore in base al tipo di bonus"""
	match bonus_type:
		BonusType.PREFIX:
			return Color(1.0, 0.7, 0.3)  # Arancione
		BonusType.SUFFIX:
			return Color(0.3, 0.8, 1.0)  # Azzurro
		BonusType.SPECIAL:
			return Color(1.0, 0.3, 0.8)  # Rosa

	return Color.WHITE

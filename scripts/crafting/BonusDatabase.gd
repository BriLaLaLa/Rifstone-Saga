# File: res://scripts/crafting/BonusDatabase.gd
# Database di tutti i bonus possibili con tier e range di valori

extends Node

const ItemBonus = preload("res://scripts/crafting/ItemBonus.gd")

# Pesi per i tier (usati quando si genera un bonus casuale)
const TIER_WEIGHTS = {
	1: 40.0,  # T1 - 40%
	2: 25.0,  # T2 - 25%
	3: 15.0,  # T3 - 15%
	4: 10.0,  # T4 - 10%
	5: 6.0,   # T5 - 6%
	6: 3.0,   # T6 - 3%
	7: 1.0    # T7 - 1%
}

# Database dei bonus con range per tier
const BONUS_DATA = {
	# ==================== PREFIX ====================
	"physical_damage": {
		"type": ItemBonus.BonusType.PREFIX,
		"stat": ItemBonus.BonusStat.PHYSICAL_DAMAGE,
		"tiers": {
			1: {"min": 3.0, "max": 5.0},
			2: {"min": 5.0, "max": 7.0},
			3: {"min": 8.0, "max": 10.0},
			4: {"min": 11.0, "max": 13.0},
			5: {"min": 15.0, "max": 18.0},
			6: {"min": 19.0, "max": 23.0},
			7: {"min": 25.0, "max": 30.0}
		}
	},

	"attack_speed": {
		"type": ItemBonus.BonusType.PREFIX,
		"stat": ItemBonus.BonusStat.ATTACK_SPEED,
		"tiers": {
			1: {"min": 1.0, "max": 3.0},
			2: {"min": 3.0, "max": 5.0},
			3: {"min": 5.0, "max": 7.0},
			4: {"min": 7.0, "max": 9.0},
			5: {"min": 9.0, "max": 11.0},
			6: {"min": 12.0, "max": 14.0},
			7: {"min": 15.0, "max": 17.0}
		}
	},

	# ==================== SUFFIX ====================
	"hp_regen": {
		"type": ItemBonus.BonusType.SUFFIX,
		"stat": ItemBonus.BonusStat.HP_REGEN,
		"tiers": {
			1: {"min": 0.3, "max": 0.6},
			2: {"min": 0.7, "max": 1.1},
			3: {"min": 1.2, "max": 1.7},
			4: {"min": 1.8, "max": 2.3},
			5: {"min": 2.5, "max": 3.2},
			6: {"min": 3.3, "max": 4.2},
			7: {"min": 4.3, "max": 5.5}
		}
	},

	"auto_heal": {
		"type": ItemBonus.BonusType.SUFFIX,
		"stat": ItemBonus.BonusStat.AUTO_HEAL_ON_DAMAGE,
		"tiers": {
			1: {"chance_min": 4.0, "chance_max": 6.0, "heal_min": 2.0, "heal_max": 3.0},
			2: {"chance_min": 6.0, "chance_max": 8.0, "heal_min": 3.0, "heal_max": 4.0},
			3: {"chance_min": 8.0, "chance_max": 10.0, "heal_min": 4.0, "heal_max": 5.0},
			4: {"chance_min": 9.0, "chance_max": 11.0, "heal_min": 5.0, "heal_max": 6.0},
			5: {"chance_min": 11.0, "chance_max": 13.0, "heal_min": 6.0, "heal_max": 7.0},
			6: {"chance_min": 13.0, "chance_max": 15.0, "heal_min": 7.0, "heal_max": 8.0},
			7: {"chance_min": 15.0, "chance_max": 17.0, "heal_min": 8.0, "heal_max": 9.0}
		}
	},

	# ==================== SPECIAL ====================
	"momentum": {
		"type": ItemBonus.BonusType.SPECIAL,
		"stat": ItemBonus.BonusStat.MOMENTUM,
		"tiers": {
			1: {"dmg_min": 0.4, "dmg_max": 0.6, "interval": 10.0, "max_stacks": 5},
			2: {"dmg_min": 0.4, "dmg_max": 0.6, "interval": 8.0, "max_stacks": 6},
			3: {"dmg_min": 0.6, "dmg_max": 0.8, "interval": 8.0, "max_stacks": 7},
			4: {"dmg_min": 0.9, "dmg_max": 1.1, "interval": 8.0, "max_stacks": 8},
			5: {"dmg_min": 0.9, "dmg_max": 1.1, "interval": 6.0, "max_stacks": 9},
			6: {"dmg_min": 1.1, "dmg_max": 1.3, "interval": 6.0, "max_stacks": 10},
			7: {"dmg_min": 1.3, "dmg_max": 1.6, "interval": 5.0, "max_stacks": 10}
		}
	}
}

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

# ==================== RANDOM TIER GENERATION ====================

func roll_tier() -> int:
	"""Genera un tier casuale basato sui pesi"""
	var total_weight = 0.0
	for weight in TIER_WEIGHTS.values():
		total_weight += weight

	var roll = rng.randf() * total_weight
	var current_sum = 0.0

	for tier in TIER_WEIGHTS.keys():
		current_sum += TIER_WEIGHTS[tier]
		if roll <= current_sum:
			return tier

	return 1  # Fallback

# ==================== BONUS GENERATION ====================

func create_random_prefix() -> ItemBonus:
	"""Crea un prefix casuale"""
	var bonus_keys = ["physical_damage", "attack_speed"]
	var key = bonus_keys[rng.randi() % bonus_keys.size()]
	var tier = roll_tier()
	return create_bonus(key, tier)

func create_random_suffix() -> ItemBonus:
	"""Crea un suffix casuale"""
	var bonus_keys = ["hp_regen", "auto_heal"]
	var key = bonus_keys[rng.randi() % bonus_keys.size()]
	var tier = roll_tier()
	return create_bonus(key, tier)

func create_random_special() -> ItemBonus:
	"""Crea un special casuale (solo Momentum per ora)"""
	var tier = roll_tier()
	return create_bonus("momentum", tier)

func create_bonus(bonus_key: String, tier: int) -> ItemBonus:
	"""Crea un bonus specifico con tier e valori randomizzati"""
	if not BONUS_DATA.has(bonus_key):
		push_error("[BonusDatabase] Bonus key not found: %s" % bonus_key)
		return null

	var data = BONUS_DATA[bonus_key]
	var tier_data = data.tiers.get(tier, data.tiers[1])  # Fallback a T1

	var bonus = ItemBonus.new()
	bonus.bonus_type = data.type
	bonus.bonus_stat = data.stat
	bonus.tier = tier

	# Genera valori in base al tipo di bonus
	match bonus_key:
		"physical_damage", "attack_speed", "hp_regen":
			bonus.value1 = rng.randf_range(tier_data.min, tier_data.max)

		"auto_heal":
			bonus.value1 = rng.randf_range(tier_data.chance_min, tier_data.chance_max)  # Chance
			bonus.value2 = rng.randf_range(tier_data.heal_min, tier_data.heal_max)      # Heal %

		"momentum":
			bonus.value1 = rng.randf_range(tier_data.dmg_min, tier_data.dmg_max)  # Damage %
			bonus.value2 = tier_data.interval  # Interval (stored for display)

	return bonus

# ==================== REROLL UTILITIES ====================

func reroll_bonus_same_category(bonus: ItemBonus) -> ItemBonus:
	"""Rerolla un bonus mantenendo la stessa categoria (per Gem of Renewal)"""
	match bonus.bonus_type:
		ItemBonus.BonusType.PREFIX:
			return create_random_prefix_same_tier(bonus.tier)
		ItemBonus.BonusType.SUFFIX:
			return create_random_suffix_same_tier(bonus.tier)
		ItemBonus.BonusType.SPECIAL:
			return create_random_special_same_tier(bonus.tier)

	return bonus

func create_random_prefix_same_tier(tier: int) -> ItemBonus:
	"""Crea un prefix casuale con tier fisso"""
	var bonus_keys = ["physical_damage", "attack_speed"]
	var key = bonus_keys[rng.randi() % bonus_keys.size()]
	return create_bonus(key, tier)

func create_random_suffix_same_tier(tier: int) -> ItemBonus:
	"""Crea un suffix casuale con tier fisso"""
	var bonus_keys = ["hp_regen", "auto_heal"]
	var key = bonus_keys[rng.randi() % bonus_keys.size()]
	return create_bonus(key, tier)

func create_random_special_same_tier(tier: int) -> ItemBonus:
	"""Crea uno special casuale con tier fisso"""
	return create_bonus("momentum", tier)

func reroll_bonus_values(bonus: ItemBonus) -> ItemBonus:
	"""Rerolla solo i valori di un bonus, mantenendo stat e tier (per Gem of Chaos)"""
	var new_tier = roll_tier()

	# Trova il bonus key dalla stat
	var bonus_key = _get_bonus_key_from_stat(bonus.bonus_stat)
	if bonus_key == "":
		return bonus

	return create_bonus(bonus_key, new_tier)

func _get_bonus_key_from_stat(stat: int) -> String:
	"""Helper per ottenere il bonus_key dalla stat"""
	match stat:
		ItemBonus.BonusStat.PHYSICAL_DAMAGE:
			return "physical_damage"
		ItemBonus.BonusStat.ATTACK_SPEED:
			return "attack_speed"
		ItemBonus.BonusStat.HP_REGEN:
			return "hp_regen"
		ItemBonus.BonusStat.AUTO_HEAL_ON_DAMAGE:
			return "auto_heal"
		ItemBonus.BonusStat.MOMENTUM:
			return "momentum"

	return ""

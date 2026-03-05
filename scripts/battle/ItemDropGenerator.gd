# File: res://scripts/battle/ItemDropGenerator.gd
# Genera item droppati dai mostri con rarità e bonus casuali

extends Node

# const LOG removed - using GameLogger  # Set to true for debug logging

const ItemBonus = preload("res://scripts/crafting/ItemBonus.gd")

var bonus_db: Node = null
var rng := RandomNumberGenerator.new()

# Chance di rarità per drop
const RARITY_CHANCES = {
	"white": 50.0,   # 50% - 0 bonus
	"blue": 35.0,    # 35% - 1-2 bonus
	"yellow": 14.0,  # 14% - 3-4 bonus
	"gold": 1.0      # 1%  - 5 bonus (with Special)
}

func _ready() -> void:
	rng.randomize()

	# Cerca BonusDatabase
	bonus_db = get_node_or_null("/root/BonusDatabase")
	if not bonus_db:
		push_error("[ItemDropGenerator] BonusDatabase not found!")

func generate_weapon_drop(weapon_id: String, weapon_data: Dictionary) -> Dictionary:
	"""Genera un'arma con rarità e bonus casuali"""

	# Crea una copia dei dati base
	var item_data = weapon_data.duplicate(true)
	item_data["bonuses"] = []

	# Roll rarità
	var rarity = _roll_rarity()

	# Genera bonus in base alla rarità
	match rarity:
		"white":
			# Nessun bonus
			pass

		"blue":
			# 1-2 bonus (solo Prefix o Suffix)
			var bonus_count = rng.randi_range(1, 2)
			_add_random_prefix_suffix(item_data, bonus_count)

		"yellow":
			# 3-4 bonus (2 Prefix + 1-2 Suffix)
			_add_prefix(item_data, 2)  # Sempre 2 prefix
			var suffix_count = rng.randi_range(1, 2)
			_add_suffix(item_data, suffix_count)

		"gold":
			# 5 bonus (2 Prefix + 2 Suffix + 1 Special)
			_add_prefix(item_data, 2)
			_add_suffix(item_data, 2)
			_add_special(item_data, 1)

	print("[ItemDropGenerator] Generated %s: %s rarity with %d bonuses" %
		[weapon_id, rarity, item_data.bonuses.size()])

	return item_data

func _roll_rarity() -> String:
	"""Determina la rarità in base alle probabilità"""
	var total = 0.0
	for chance in RARITY_CHANCES.values():
		total += chance

	var roll = rng.randf() * total
	var current_sum = 0.0

	for rarity in RARITY_CHANCES.keys():
		current_sum += RARITY_CHANCES[rarity]
		if roll <= current_sum:
			return rarity

	return "white"

func _add_random_prefix_suffix(item_data: Dictionary, count: int) -> void:
	"""Aggiunge bonus casuali (mix di prefix/suffix)"""
	if not bonus_db:
		return

	for i in range(count):
		if rng.randf() < 0.5:
			var bonus = bonus_db.create_random_prefix()
			item_data.bonuses.append(bonus.to_dict())
		else:
			var bonus = bonus_db.create_random_suffix()
			item_data.bonuses.append(bonus.to_dict())

func _add_prefix(item_data: Dictionary, count: int) -> void:
	"""Aggiunge Prefix"""
	if not bonus_db:
		return

	for i in range(count):
		var bonus = bonus_db.create_random_prefix()
		item_data.bonuses.append(bonus.to_dict())

func _add_suffix(item_data: Dictionary, count: int) -> void:
	"""Aggiunge Suffix"""
	if not bonus_db:
		return

	for i in range(count):
		var bonus = bonus_db.create_random_suffix()
		item_data.bonuses.append(bonus.to_dict())

func _add_special(item_data: Dictionary, count: int) -> void:
	"""Aggiunge Special"""
	if not bonus_db:
		return

	for i in range(count):
		var bonus = bonus_db.create_random_special()
		item_data.bonuses.append(bonus.to_dict())

# ==================== INTEGRATION WITH EXISTING DROP SYSTEM ====================

func generate_drop_from_loot_table(item_id: String) -> Dictionary:
	"""Genera un drop in base all'item_id dalla loot table"""

	# Cerca i dati dell'item in GameState
	var gs = get_node_or_null("/root/GameState")
	if not gs or not "data" in gs or not "items" in gs.data:
		push_error("[ItemDropGenerator] GameState or items data not found")
		return {}

	var item_data = gs.data.items.get(item_id, {})
	if item_data.is_empty():
		# Silently skip items not in database (legacy items like fish, potion, etc.)
		if GameLogger.ENABLED:
			print("[ItemDropGenerator] ⚠️ Item %s not found in database - skipping" % item_id)
		return {}

	# Se è un'arma, genera con bonus
	if item_data.get("type", "") == "Weapon":
		return generate_weapon_drop(item_id, item_data)

	# Altrimenti restituisci i dati base (gems, etc.)
	return item_data.duplicate(true)

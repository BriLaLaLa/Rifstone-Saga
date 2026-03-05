# File: res://scripts/crafting/GemCrafting.gd
# Sistema di crafting con gemme

extends Node

const ItemBonus = preload("res://scripts/crafting/ItemBonus.gd")

# Riferimento al database dei bonus
var bonus_db: Node = null

signal gem_applied(item_data: Dictionary, gem_id: String, success: bool)
signal gem_returned(gem_id: String)

func _ready() -> void:
	# Cerca il BonusDatabase nella scena
	bonus_db = get_node_or_null("/root/BonusDatabase")
	if not bonus_db:
		push_error("[GemCrafting] BonusDatabase not found!")

# ==================== MAIN API ====================

func apply_gem_to_item(item_data: Dictionary, gem_id: String) -> Dictionary:
	"""
	Applica una gemma a un item e restituisce l'item modificato.
	Restituisce anche un flag "gem_consumed" per sapere se la gemma è stata usata.
	"""
	if not bonus_db:
		push_error("[GemCrafting] BonusDatabase not available")
		return {"item": item_data, "gem_consumed": false}

	# Assicurati che l'item abbia la struttura per i bonus
	if not item_data.has("bonuses"):
		item_data["bonuses"] = []

	var result = {"item": item_data, "gem_consumed": true}

	match gem_id:
		"force_gem":
			result = _apply_force_gem(item_data)

		"gem_of_agility":
			result = _apply_agility_gem(item_data)

		"gem_of_chaos":
			result = _apply_chaos_gem(item_data)

		"gem_of_excellence":
			result = _apply_excellence_gem(item_data)

		"gem_of_renewal":
			result = _apply_renewal_gem(item_data)

		_:
			push_error("[GemCrafting] Unknown gem: %s" % gem_id)
			result["gem_consumed"] = false

	# Emetti signal
	gem_applied.emit(result.item, gem_id, result.gem_consumed)

	if not result.gem_consumed:
		gem_returned.emit(gem_id)

	return result

# ==================== GEM IMPLEMENTATIONS ====================

func _apply_force_gem(item_data: Dictionary) -> Dictionary:
	"""ForceGem - Aggiunge 1 Prefix"""
	var bonuses = item_data.bonuses
	var prefix_count = _count_bonuses_by_type(bonuses, ItemBonus.BonusType.PREFIX)

	# Se già 2 prefix, no-op e restituisci gemma
	if prefix_count >= 2:
		print("[GemCrafting] ForceGem: Already 2 prefixes, gem returned")
		return {"item": item_data, "gem_consumed": false}

	# Aggiungi un nuovo prefix
	var new_prefix = bonus_db.create_random_prefix()
	bonuses.append(new_prefix.to_dict())

	print("[GemCrafting] ForceGem: Added prefix - %s" % new_prefix.get_display_text())
	return {"item": item_data, "gem_consumed": true}

func _apply_agility_gem(item_data: Dictionary) -> Dictionary:
	"""Gem of Agility - Aggiunge 1 Suffix"""
	var bonuses = item_data.bonuses
	var suffix_count = _count_bonuses_by_type(bonuses, ItemBonus.BonusType.SUFFIX)

	# Se già 2 suffix, no-op e restituisci gemma
	if suffix_count >= 2:
		print("[GemCrafting] Agility Gem: Already 2 suffixes, gem returned")
		return {"item": item_data, "gem_consumed": false}

	# Aggiungi un nuovo suffix
	var new_suffix = bonus_db.create_random_suffix()
	bonuses.append(new_suffix.to_dict())

	print("[GemCrafting] Agility Gem: Added suffix - %s" % new_suffix.get_display_text())
	return {"item": item_data, "gem_consumed": true}

func _apply_chaos_gem(item_data: Dictionary) -> Dictionary:
	"""Gem of Chaos - Rerolla tutti i valori T1-T7"""
	var bonuses = item_data.bonuses

	if bonuses.is_empty():
		print("[GemCrafting] Chaos Gem: No bonuses to reroll, gem returned")
		return {"item": item_data, "gem_consumed": false}

	# Rerolla ogni bonus (categoria e numero invariati, tier e valori ricalcolati)
	for i in range(bonuses.size()):
		var bonus_dict = bonuses[i]
		var bonus = ItemBonus.new()
		bonus.from_dict(bonus_dict)

		# Rerolla tier e valori
		var rerolled = bonus_db.reroll_bonus_values(bonus)
		bonuses[i] = rerolled.to_dict()

		print("[GemCrafting] Chaos Gem: Rerolled bonus %d - %s" % [i, rerolled.get_display_text()])

	return {"item": item_data, "gem_consumed": true}

func _apply_excellence_gem(item_data: Dictionary) -> Dictionary:
	"""Gem of Excellence - Aggiunge il 5° bonus (Special)"""
	var bonuses = item_data.bonuses

	# Controlla se c'è già uno Special
	var has_special = _count_bonuses_by_type(bonuses, ItemBonus.BonusType.SPECIAL) > 0

	if has_special:
		print("[GemCrafting] Excellence Gem: Special already exists, gem returned")
		return {"item": item_data, "gem_consumed": false}

	# Aggiungi uno Special
	var new_special = bonus_db.create_random_special()
	bonuses.append(new_special.to_dict())

	print("[GemCrafting] Excellence Gem: Added special - %s" % new_special.get_display_text())
	return {"item": item_data, "gem_consumed": true}

func _apply_renewal_gem(item_data: Dictionary) -> Dictionary:
	"""Gem of Renewal - Sostituisce 1 bonus casuale con uno della stessa categoria"""
	var bonuses = item_data.bonuses

	if bonuses.is_empty():
		print("[GemCrafting] Renewal Gem: No bonuses to replace, gem returned")
		return {"item": item_data, "gem_consumed": false}

	# Scegli un bonus casuale
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var index = rng.randi() % bonuses.size()

	var old_bonus_dict = bonuses[index]
	var old_bonus = ItemBonus.new()
	old_bonus.from_dict(old_bonus_dict)

	# Genera un nuovo bonus della stessa categoria con lo stesso tier
	var new_bonus = bonus_db.reroll_bonus_same_category(old_bonus)
	bonuses[index] = new_bonus.to_dict()

	print("[GemCrafting] Renewal Gem: Replaced bonus %d - %s -> %s" %
		[index, old_bonus.get_display_text(), new_bonus.get_display_text()])

	return {"item": item_data, "gem_consumed": true}

# ==================== UTILITY FUNCTIONS ====================

func _count_bonuses_by_type(bonuses: Array, bonus_type: int) -> int:
	"""Conta quanti bonus di un certo tipo ci sono"""
	var count = 0
	for bonus_dict in bonuses:
		if bonus_dict.get("bonus_type", -1) == bonus_type:
			count += 1
	return count

func get_item_rarity(item_data: Dictionary) -> String:
	"""Determina la rarità di un item in base al numero di bonus"""
	if not item_data.has("bonuses"):
		return "white"

	var count = item_data.bonuses.size()

	if count == 0:
		return "white"
	elif count <= 2:
		return "blue"
	elif count <= 4:
		return "yellow"
	else:
		return "gold"  # 5 bonus (con Special)

func get_rarity_color(rarity: String) -> Color:
	"""Restituisce il colore della rarità"""
	match rarity:
		"white":
			return Color.WHITE
		"blue":
			return Color(0.3, 0.6, 1.0)
		"yellow":
			return Color(1.0, 0.9, 0.2)
		"gold":
			return Color(1.0, 0.6, 0.0)

	return Color.WHITE

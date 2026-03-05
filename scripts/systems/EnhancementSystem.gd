extends Node

## EnhancementSystem - Sistema di potenziamento armi stile Metin2
##
## Gestisce il potenziamento progressivo delle armi da +0 a +9
## con effetti visivi che rappresentano l'instabilità crescente dell'energia

# ==================== CONSTANTS ====================

const MAX_ENHANCEMENT_LEVEL = 9

# Enhancement success rates (Metin2-style)
const ENHANCEMENT_RATES = {
	0: 1.0,   # +0 → +1: 100%
	1: 1.0,   # +1 → +2: 100%
	2: 1.0,   # +2 → +3: 100%
	3: 0.95,  # +3 → +4: 95%
	4: 0.90,  # +4 → +5: 90%
	5: 0.80,  # +5 → +6: 80%
	6: 0.70,  # +6 → +7: 70% - Inizia l'instabilità visiva
	7: 0.50,  # +7 → +8: 50% - Energia incontrollata
	8: 0.30   # +8 → +9: 30% - Manifestazione soprannaturale
}

# Destruction chance on failure (only for high levels)
const DESTRUCTION_RATES = {
	0: 0.0,
	1: 0.0,
	2: 0.0,
	3: 0.0,
	4: 0.0,
	5: 0.0,
	6: 0.1,   # +6 → +7 fail: 10% distruzione
	7: 0.3,   # +7 → +8 fail: 30% distruzione
	8: 0.6    # +8 → +9 fail: 60% distruzione
}

# Stat bonus per enhancement level (moltiplicatore)
const STAT_MULTIPLIERS = {
	0: 1.0,
	1: 1.05,
	2: 1.10,
	3: 1.15,
	4: 1.20,
	5: 1.30,
	6: 1.40,
	7: 1.60,  # +7: Controlled Energy - bonus significativo
	8: 1.90,  # +8: Unstable Energy - bonus maggiore
	9: 2.50   # +9: Manifested Artifact - bonus leggendario
}

# Material costs (example - da customizzare)
const ENHANCEMENT_COSTS = {
	0: {"gold": 100},
	1: {"gold": 200},
	2: {"gold": 500},
	3: {"gold": 1000, "ore": 5},
	4: {"gold": 2000, "ore": 10},
	5: {"gold": 5000, "ore": 20},
	6: {"gold": 10000, "ore": 50, "mystic_stone": 1},
	7: {"gold": 25000, "ore": 100, "mystic_stone": 3},
	8: {"gold": 50000, "ore": 200, "mystic_stone": 5, "ancient_crystal": 1}
}

# ==================== SHADER PATHS ====================

const ENHANCEMENT_SHADERS = {
	7: preload("res://shaders/enhancement_plus7.gdshader"),
	8: preload("res://shaders/enhancement_plus8.gdshader"),
	9: preload("res://shaders/enhancement_plus9.gdshader")
}

# ==================== SIGNALS ====================

signal enhancement_attempted(item_id: String, from_level: int, to_level: int)
signal enhancement_succeeded(item_id: String, new_level: int)
signal enhancement_failed(item_id: String, level: int, destroyed: bool)
signal item_destroyed(item_id: String, level: int)

# ==================== PUBLIC FUNCTIONS ====================

func can_enhance(item_data: Dictionary) -> bool:
	"""Verifica se un item può essere potenziato"""
	if not item_data.has("type"):
		return false

	# Solo armi e armature
	if item_data.type not in ["Weapon", "Armor", "Accessory"]:
		return false

	var current_level = item_data.get("enhancement_level", 0)
	return current_level < MAX_ENHANCEMENT_LEVEL


func get_enhancement_chance(current_level: int) -> float:
	"""Ritorna la probabilità di successo per il livello corrente"""
	return ENHANCEMENT_RATES.get(current_level, 0.0)


func get_destruction_chance(current_level: int) -> float:
	"""Ritorna la probabilità di distruzione in caso di fallimento"""
	return DESTRUCTION_RATES.get(current_level, 0.0)


func get_stat_multiplier(enhancement_level: int) -> float:
	"""Ritorna il moltiplicatore di stats per il livello di enhancement"""
	return STAT_MULTIPLIERS.get(enhancement_level, 1.0)


func get_enhancement_cost(current_level: int) -> Dictionary:
	"""Ritorna il costo in materiali per potenziare dal livello corrente"""
	return ENHANCEMENT_COSTS.get(current_level, {})


func attempt_enhancement(item_instance_id: String) -> Dictionary:
	"""
	Tenta di potenziare un'arma

	Returns: {
		"success": bool,
		"destroyed": bool,
		"new_level": int,
		"message": String
	}
	"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return {"success": false, "destroyed": false, "new_level": 0, "message": "GameState not found"}

	# Trova l'item nell'inventario
	var item_data = _find_item_in_inventory(item_instance_id)
	if item_data.is_empty():
		return {"success": false, "destroyed": false, "new_level": 0, "message": "Item not found"}

	if not can_enhance(item_data):
		return {"success": false, "destroyed": false, "new_level": item_data.get("enhancement_level", 0), "message": "Cannot enhance this item"}

	var current_level = item_data.get("enhancement_level", 0)
	var success_rate = get_enhancement_chance(current_level)
	var destruction_rate = get_destruction_chance(current_level)

	# Check if player has required materials
	var cost = get_enhancement_cost(current_level)
	if not _has_materials(cost):
		return {"success": false, "destroyed": false, "new_level": current_level, "message": "Not enough materials"}

	# Consume materials
	_consume_materials(cost)

	# Roll for success
	var roll = randf()

	enhancement_attempted.emit(item_instance_id, current_level, current_level + 1)

	if roll <= success_rate:
		# SUCCESS
		var new_level = current_level + 1
		item_data["enhancement_level"] = new_level

		# Recalculate stats with new multiplier
		_apply_enhancement_stats(item_data, new_level)

		enhancement_succeeded.emit(item_instance_id, new_level)
		gs.save_game()

		return {
			"success": true,
			"destroyed": false,
			"new_level": new_level,
			"message": "Enhancement successful! Weapon is now +%d" % new_level
		}
	else:
		# FAILURE - check for destruction
		var destruction_roll = randf()

		if destruction_roll <= destruction_rate:
			# ITEM DESTROYED
			_destroy_item(item_instance_id)
			item_destroyed.emit(item_instance_id, current_level)
			enhancement_failed.emit(item_instance_id, current_level, true)
			gs.save_game()

			return {
				"success": false,
				"destroyed": true,
				"new_level": 0,
				"message": "Enhancement failed! The weapon was destroyed by unstable energy!"
			}
		else:
			# FAILURE but item survives
			enhancement_failed.emit(item_instance_id, current_level, false)

			return {
				"success": false,
				"destroyed": false,
				"new_level": current_level,
				"message": "Enhancement failed, but the weapon survived."
			}


func get_shader_for_level(enhancement_level: int) -> Shader:
	"""Ritorna lo shader appropriato per il livello di enhancement"""
	if enhancement_level >= 9:
		return ENHANCEMENT_SHADERS[9]
	elif enhancement_level >= 8:
		return ENHANCEMENT_SHADERS[8]
	elif enhancement_level >= 7:
		return ENHANCEMENT_SHADERS[7]

	return null  # No shader for levels < 7


func has_visual_effect(enhancement_level: int) -> bool:
	"""Verifica se un livello di enhancement ha effetti visivi"""
	return enhancement_level >= 7


func get_enhancement_display_name(enhancement_level: int) -> String:
	"""Ritorna il nome narrativo del livello di enhancement"""
	match enhancement_level:
		7: return "Controlled Energy"
		8: return "Unstable Energy"
		9: return "Manifested Artifact"
		_: return ""


# ==================== PRIVATE FUNCTIONS ====================

func _find_item_in_inventory(item_instance_id: String) -> Dictionary:
	"""Trova un item nell'inventario usando il suo instance_id"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return {}

	for item in gs.inventory_items:
		if item.get("instance_id", "") == item_instance_id:
			return item

	# Check equipped items too
	for slot in gs.equipped_items:
		var equipped = gs.equipped_items[slot]
		if equipped and equipped.get("instance_id", "") == item_instance_id:
			return equipped

	return {}


func _has_materials(cost: Dictionary) -> bool:
	"""Verifica se il player ha i materiali richiesti"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return false

	# Check gold
	if cost.has("gold"):
		if gs.gold < cost.gold:
			return false

	# Check other materials (da implementare con sistema inventario)
	# Per ora assumiamo sempre true per materiali non-gold
	return true


func _consume_materials(cost: Dictionary) -> void:
	"""Consuma i materiali richiesti"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	if cost.has("gold"):
		gs.gold -= cost.gold

	# TODO: Consume other materials from inventory


func _apply_enhancement_stats(item_data: Dictionary, enhancement_level: int) -> void:
	"""Applica il moltiplicatore di stats all'item"""
	if not item_data.has("base_stats"):
		# First enhancement - save original stats
		item_data["base_stats"] = item_data.get("stats", {}).duplicate()

	var base_stats = item_data["base_stats"]
	var multiplier = get_stat_multiplier(enhancement_level)

	# Apply multiplier to all stats
	var enhanced_stats = {}
	for stat in base_stats:
		enhanced_stats[stat] = int(base_stats[stat] * multiplier)

	item_data["stats"] = enhanced_stats


func _destroy_item(item_instance_id: String) -> void:
	"""Rimuove un item dall'inventario (distrutto)"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	# Remove from inventory
	for i in range(gs.inventory_items.size()):
		if gs.inventory_items[i].get("instance_id", "") == item_instance_id:
			gs.inventory_items.remove_at(i)
			return

	# Remove from equipped items
	for slot in gs.equipped_items:
		if gs.equipped_items[slot] and gs.equipped_items[slot].get("instance_id", "") == item_instance_id:
			gs.unequip_item_from_slot(slot)
			return

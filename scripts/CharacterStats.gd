# CharacterStats.gd
# Sistema completo di statistiche del personaggio
# Integrato con il GameState esistente di Rifstone Saga
# Path: res://scripts/CharacterStats.gd

class_name CharacterStats
extends RefCounted

# ============================================
# STATS BASE
# ============================================
var base_stats := {
	# Stats Primarie
	"max_hp": 100,
	"max_mana": 100,
	"strength": 10,
	"dexterity": 10,
	"intelligence": 10,
	"vitality": 10,
	"luck": 10,
	
	# Stats Offensive
	"physical_damage": 5,
	"magic_damage": 5,
	"attack_speed": 1.0,
	"crit_chance": 5.0,
	"crit_damage": 150.0,
	
	# Stats Defensive
	"physical_defense": 0,
	"magic_defense": 0,
	"evasion": 5.0,
	"block_chance": 0.0,
	"block_amount": 0,
	
	# Stats Utility
	"hp_regen": 1.0,
	"mana_regen": 20.0,  # High regen for testing
	"movement_speed": 100.0,
	"cooldown_reduction": 0.0,
	
	# Stats Elementali
	"fire_damage": 0,
	"ice_damage": 0,
	"lightning_damage": 0,
	"fire_resistance": 0.0,
	"ice_resistance": 0.0,
	"lightning_resistance": 0.0,
	
	# Stats Bonus
	"lifesteal": 0.0,
	"gold_find": 0.0,
	"magic_find": 0.0,
	"exp_bonus": 0.0,
}

# Bonus da equipment (stessa struttura)
# Bonus da equipment (stessa struttura)
var equipment_bonuses := {}

# Bonus da passives
var passive_bonuses := {}

# Modificatori temporanei (buffs/debuffs)
var temporary_modifiers := []

# HP/Mana correnti
var current_hp: float = 100.0
var current_mana: float = 100.0

# ============================================
# LEVEL SYSTEM
# ============================================
var level_system: LevelSystem = null

# Signals
signal stats_changed(stat_name: String, old_value, new_value)
signal hp_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal player_died()  # Emesso quando HP arriva a 0
signal level_up(new_level: int)  # Emesso quando si sale di livello
signal exp_gained(amount: int, current_exp: int, exp_to_next: int)  # Emesso quando si guadagna EXP

func _init():
	# Inizializza equipment_bonuses
	for stat in base_stats.keys():
		equipment_bonuses[stat] = 0 if typeof(base_stats[stat]) == TYPE_INT else 0.0
		passive_bonuses[stat] = 0 if typeof(base_stats[stat]) == TYPE_INT else 0.0

	current_hp = get_stat("max_hp")
	current_mana = get_stat("max_mana")

	# Inizializza level system (combat level con curva 1.15)
	level_system = LevelSystem.new(1, 0, 1.15)
	level_system.level_up.connect(_on_level_up)
	level_system.exp_gained.connect(_on_exp_gained)

# ============================================
# CALCOLO STATS FINALI
# ============================================

func get_stat(stat_name: String) -> float:
	if not base_stats.has(stat_name):
		return 0.0
	
	var value: float = base_stats[stat_name]
	value += equipment_bonuses[stat_name]
	if passive_bonuses.has(stat_name):
		value += passive_bonuses[stat_name]
	
	# Applica modificatori temporanei
	for modifier in temporary_modifiers:
		if modifier.has(stat_name):
			if modifier.get("type", "flat") == "flat":
				value += modifier[stat_name]
			else:
				value *= (1.0 + modifier[stat_name] / 100.0)
	
	return value

func get_all_stats() -> Dictionary:
	var final_stats := {}
	for stat in base_stats.keys():
		final_stats[stat] = get_stat(stat)
	return final_stats

# ============================================
# MODIFICA STATS BASE
# ============================================

func set_base_stat(stat_name: String, value: float) -> void:
	if not base_stats.has(stat_name):
		return
	
	var old_value = base_stats[stat_name]
	base_stats[stat_name] = value
	stats_changed.emit(stat_name, old_value, value)
	
	if stat_name == "max_hp":
		current_hp = min(current_hp, get_stat("max_hp"))
		hp_changed.emit(current_hp, get_stat("max_hp"))
	elif stat_name == "max_mana":
		current_mana = min(current_mana, get_stat("max_mana"))
		mana_changed.emit(current_mana, get_stat("max_mana"))

func modify_base_stat(stat_name: String, amount: float) -> void:
	set_base_stat(stat_name, base_stats.get(stat_name, 0) + amount)

# ============================================
# EQUIPMENT BONUSES (INTEGRAZIONE CHIAVE)
# ============================================

func apply_equipment_stats(item_stats: Dictionary) -> void:
	"""Applica le stats di un item equipaggiato"""
	for stat in item_stats.keys():
		if equipment_bonuses.has(stat):
			equipment_bonuses[stat] += item_stats[stat]
			stats_changed.emit(stat, get_stat(stat) - item_stats[stat], get_stat(stat))
	
	_update_max_hp_mana()

func remove_equipment_stats(item_stats: Dictionary) -> void:
	"""Rimuove le stats di un item de-equipaggiato"""
	for stat in item_stats.keys():
		if equipment_bonuses.has(stat):
			equipment_bonuses[stat] -= item_stats[stat]
			stats_changed.emit(stat, get_stat(stat) + item_stats[stat], get_stat(stat))
	
	_update_max_hp_mana()

# ============================================
# PASSIVE BONUSES
# ============================================

func add_passive_bonus(stat_name: String, amount: float) -> void:
	"""Aggiunge un bonus passivo"""
	if not passive_bonuses.has(stat_name):
		passive_bonuses[stat_name] = 0.0
	
	passive_bonuses[stat_name] += amount
	stats_changed.emit(stat_name, get_stat(stat_name) - amount, get_stat(stat_name))
	
	_update_max_hp_mana()

func clear_passive_bonuses() -> void:
	"""Rimuove tutti i bonus passivi"""
	for stat in passive_bonuses.keys():
		var old_val = get_stat(stat)
		passive_bonuses[stat] = 0 if typeof(base_stats.get(stat, 0)) == TYPE_INT else 0.0
		stats_changed.emit(stat, old_val, get_stat(stat))
	
	_update_max_hp_mana()

# ============================================
# MODIFICATORI TEMPORANEI
# ============================================

func add_temporary_modifier(modifier: Dictionary, duration: float = 0.0) -> void:
	modifier["duration"] = duration
	modifier["start_time"] = Time.get_ticks_msec() / 1000.0
	temporary_modifiers.append(modifier)

func remove_temporary_modifier(modifier_id: String) -> void:
	temporary_modifiers = temporary_modifiers.filter(func(m): return m.get("id", "") != modifier_id)

func update_temporary_modifiers(delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var expired := []
	
	for modifier in temporary_modifiers:
		if modifier.get("duration", 0.0) > 0:
			if current_time - modifier["start_time"] >= modifier["duration"]:
				expired.append(modifier)
	
	for modifier in expired:
		temporary_modifiers.erase(modifier)

# ============================================
# HP / MANA
# ============================================

func take_damage(amount: float) -> float:
	var old_hp = current_hp
	current_hp = max(0, current_hp - amount)
	hp_changed.emit(current_hp, get_stat("max_hp"))

	# Check if player died
	if current_hp <= 0 and old_hp > 0:
		player_died.emit()

	return old_hp - current_hp

func heal(amount: float) -> float:
	var old_hp = current_hp
	current_hp = min(get_stat("max_hp"), current_hp + amount)
	hp_changed.emit(current_hp, get_stat("max_hp"))
	return current_hp - old_hp

func consume_mana(amount: float) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		mana_changed.emit(current_mana, get_stat("max_mana"))
		return true
	return false

func restore_mana(amount: float) -> float:
	var old_mana = current_mana
	current_mana = min(get_stat("max_mana"), current_mana + amount)
	mana_changed.emit(current_mana, get_stat("max_mana"))
	return current_mana - old_mana

func _update_max_hp_mana() -> void:
	var max_hp = get_stat("max_hp")
	var max_mana = get_stat("max_mana")
	
	current_hp = min(current_hp, max_hp)
	current_mana = min(current_mana, max_mana)
	
	hp_changed.emit(current_hp, max_hp)
	mana_changed.emit(current_mana, max_mana)

# ============================================
# LEVEL & EXPERIENCE SYSTEM
# ============================================

func add_combat_exp(amount: int) -> void:
	"""Aggiungi esperienza da combattimento

	Args:
		amount: Quantità di EXP da aggiungere
	"""
	if not level_system:
		push_error("[CharacterStats] Level system not initialized!")
		return

	# Applica bonus EXP se presente
	var exp_bonus_mult = 1.0 + (get_stat("exp_bonus") / 100.0)
	var final_amount = int(amount * exp_bonus_mult)

	level_system.add_exp(final_amount)

func get_level() -> int:
	"""Ritorna il livello corrente"""
	if level_system:
		return level_system.get_level()
	return 1

func get_current_exp() -> int:
	"""Ritorna l'EXP corrente per il livello attuale"""
	if level_system:
		return level_system.get_exp()
	return 0

func get_exp_to_next_level() -> int:
	"""Ritorna l'EXP necessaria per il prossimo livello"""
	if level_system:
		return level_system.get_exp_to_next()
	return 100

func get_exp_progress() -> float:
	"""Ritorna il progresso verso il prossimo livello (0.0-1.0)"""
	if level_system:
		return level_system.get_exp_progress_percent()
	return 0.0

func _on_level_up(new_level: int) -> void:
	"""Callback quando si sale di livello"""
	if GameLogger.ENABLED:
		print("[CharacterStats] 🎉 LEVEL UP! New level: %d" % new_level)

	# Emetti signal per altri sistemi (PassivesTab, UI, etc.)
	level_up.emit(new_level)

	# Heal to full on level up
	current_hp = get_stat("max_hp")
	current_mana = get_stat("max_mana")
	hp_changed.emit(current_hp, get_stat("max_hp"))
	mana_changed.emit(current_mana, get_stat("max_mana"))

func _on_exp_gained(amount: int, total_exp: int) -> void:
	"""Callback quando si guadagna EXP"""
	var exp_to_next = get_exp_to_next_level()
	exp_gained.emit(amount, get_current_exp(), exp_to_next)

# ============================================
# SERIALIZATION (per save/load)
# ============================================

func to_dict() -> Dictionary:
	var data = {
		"base_stats": base_stats.duplicate(),
		"equipment_bonuses": equipment_bonuses.duplicate(),
		"current_hp": current_hp,
		"current_mana": current_mana,
		"temporary_modifiers": temporary_modifiers.duplicate()
	}

	# Save level system
	if level_system:
		data["level_system"] = level_system.to_dict()

	return data

func from_dict(data: Dictionary) -> void:
	if data.has("base_stats"):
		base_stats = data.base_stats
	if data.has("equipment_bonuses"):
		equipment_bonuses = data.equipment_bonuses
	if data.has("current_hp"):
		current_hp = data.current_hp
	if data.has("current_mana"):
		current_mana = data.current_mana
	if data.has("temporary_modifiers"):
		temporary_modifiers = data.temporary_modifiers

	# Load level system
	if data.has("level_system") and level_system:
		level_system.from_dict(data.level_system)

# ============================================
# DEBUG
# ============================================

func print_stats() -> void:
	print("=== CHARACTER STATS ===")
	print("HP: ", current_hp, "/", get_stat("max_hp"))
	print("Mana: ", current_mana, "/", get_stat("max_mana"))
	print("\n=== Primary Stats ===")
	for stat in ["strength", "dexterity", "intelligence", "vitality", "luck"]:
		var final = get_stat(stat)
		var bonus = equipment_bonuses[stat]
		if bonus != 0:
			print(stat, ": ", base_stats[stat], " + ", bonus, " = ", final)
		else:
			print(stat, ": ", final)
	
	print("\n=== Combat Stats ===")
	print("Physical Damage: ", get_stat("physical_damage"))
	print("Physical Defense: ", get_stat("physical_defense"))
	print("Crit Chance: ", get_stat("crit_chance"), "%")

# File: res://scripts/battle/CharacterDisplay.gd
# Mostra il personaggio con equipment e stats calcolate in tempo reale

extends Control
class_name CharacterDisplay

const LOG := true

# References
@onready var character_bg: TextureRect = $CharacterBackground
@onready var equipment_slots: Control = $EquipmentSlots
@onready var stats_panel: VBoxContainer = $StatsPanel

# Equipment slot references (come in InventoryTab)
@onready var helmet_slot: Panel = $EquipmentSlots/HelmetSlot
@onready var weapon_slot: Panel = $EquipmentSlots/WeaponSlot
@onready var chest_slot: Panel = $EquipmentSlots/ChestSlot
@onready var shield_slot: Panel = $EquipmentSlots/ShieldSlot
@onready var belt_slot: Panel = $EquipmentSlots/BeltSlot
@onready var boots_slot: Panel = $EquipmentSlots/BootsSlot

# Stats display references
@onready var hp_bar: ProgressBar = $StatsPanel/HPBar
@onready var hp_label: Label = $StatsPanel/HPBar/HPLabel
@onready var attack_label: Label = $StatsPanel/AttackLabel
@onready var defense_label: Label = $StatsPanel/DefenseLabel
@onready var level_label: Label = $StatsPanel/LevelLabel

# Cached stats
var current_stats: Dictionary = {
	"attack": 0,
	"defense": 0,
	"hp_bonus": 0,
	"max_hp": 100
}

func _ready() -> void:
	_setup_equipment_slots()
	_connect_signals()
	_update_stats()
	
	if LOG:
		print("[CharacterDisplay] Ready")

func _setup_equipment_slots() -> void:
	"""Configura gli slot equipment per accettare drag & drop"""
	var slots = [helmet_slot, weapon_slot, chest_slot, shield_slot, belt_slot, boots_slot]
	
	for slot in slots:
		if slot:
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			
			# Applica stile base
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.3, 0.5, 0.7, 0.9)
			slot.add_theme_stylebox_override("panel", style)
	
	if LOG:
		print("[CharacterDisplay] Equipment slots configured")

func _connect_signals() -> void:
	"""Connetti ai signal del GameState per aggiornamenti"""
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			# Aggiorna stats quando l'inventario cambia
			if gs.has_signal("on_inventory_changed"):
				if not gs.on_inventory_changed.is_connected(_on_equipment_changed):
					gs.on_inventory_changed.connect(_on_equipment_changed)
			
			# Aggiorna HP quando cambia in combattimento
			if gs.has_signal("on_combat_event"):
				if not gs.on_combat_event.is_connected(_on_combat_event):
					gs.on_combat_event.connect(_on_combat_event)

func _on_equipment_changed() -> void:
	"""Chiamato quando l'equipment cambia"""
	_update_stats()
	if LOG:
		print("[CharacterDisplay] Equipment changed, stats updated")

func _on_combat_event(msg: String) -> void:
	"""Chiamato durante eventi di combattimento"""
	_update_hp_bar()

func _update_stats() -> void:
	"""Ricalcola e aggiorna tutte le statistiche del personaggio"""
	current_stats = _calculate_equipment_stats()
	
	# Aggiorna labels
	if attack_label:
		var total_atk = current_stats.attack + _get_base_attack()
		attack_label.text = "⚔️ Attack: %d" % total_atk
	
	if defense_label:
		var total_def = current_stats.defense + _get_base_defense()
		defense_label.text = "🛡️ Defense: %d" % total_def
	
	if level_label:
		var combat_level = _get_combat_level()
		level_label.text = "Level: %d" % combat_level
	
	_update_hp_bar()

func _calculate_equipment_stats() -> Dictionary:
	"""Calcola le stats totali da tutti gli equipment equipaggiati"""
	var stats = {
		"attack": 0,
		"defense": 0,
		"hp_bonus": 0,
		"max_hp": 100
	}
	
	# Trova tutti gli items equipaggiati negli slot
	var slots = [helmet_slot, weapon_slot, chest_slot, shield_slot, belt_slot, boots_slot]
	
	for slot in slots:
		if not slot:
			continue
		
		# Cerca un Item child nello slot
		for child in slot.get_children():
			if child is Item:
				var item: Item = child as Item
				var item_data = _get_item_data(item.item_id)
				
				# Somma le stats dell'item
				stats.attack += int(item_data.get("attack", 0))
				stats.defense += int(item_data.get("defense", 0))
				stats.hp_bonus += int(item_data.get("hp_bonus", 0))
				
				if LOG:
					print("[CharacterDisplay] Found equipped: %s (+%d ATK, +%d DEF)" % 
						[item.item_id, item_data.get("attack", 0), item_data.get("defense", 0)])
	
	stats.max_hp = 100 + stats.hp_bonus
	return stats

func _get_item_data(item_id: String) -> Dictionary:
	"""Ottieni i dati di un item dal GameState"""
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs and gs.has("data") and gs.data.has("items"):
			return gs.data.items.get(item_id, {})
	return {}

func _get_base_attack() -> int:
	"""Ottieni l'attacco base dal livello combat"""
	var level = _get_combat_level()
	return 5 + level  # Formula base: 5 + livello

func _get_base_defense() -> int:
	"""Ottieni la difesa base dal livello combat"""
	var level = _get_combat_level()
	return 3 + int(level * 0.5)  # Formula base: 3 + metà livello

func _get_combat_level() -> int:
	"""Ottieni il livello di combattimento dal GameState"""
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs and gs.has("skills"):
			var combat_skill = gs.skills.get("swordsmanship", null)
			if combat_skill:
				return combat_skill.level
	return 1

func _update_hp_bar() -> void:
	"""Aggiorna la barra HP con i valori correnti"""
	if not hp_bar or not hp_label:
		return
	
	var current_hp = 100.0
	var max_hp = current_stats.max_hp
	
	# Prendi HP dal GameState se disponibile
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			if gs.has("player_hp"):
				current_hp = float(gs.get("player_hp"))
			if gs.has("player_max_hp"):
				max_hp = float(gs.get("player_max_hp"))
			else:
				# Se non esiste ancora, usa il nostro calcolo
				max_hp = current_stats.max_hp
	
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_label.text = "%d / %d" % [int(current_hp), int(max_hp)]
	
	# Cambia colore in base alla % di HP
	var hp_percent = current_hp / max_hp
	if hp_percent > 0.6:
		hp_bar.modulate = Color.GREEN
	elif hp_percent > 0.3:
		hp_bar.modulate = Color.YELLOW
	else:
		hp_bar.modulate = Color.RED

# ==================== API PUBBLICA ====================

func get_total_attack() -> int:
	"""Restituisce l'attacco totale (base + equipment)"""
	return current_stats.attack + _get_base_attack()

func get_total_defense() -> int:
	"""Restituisce la difesa totale (base + equipment)"""
	return current_stats.defense + _get_base_defense()

func get_max_hp() -> int:
	"""Restituisce gli HP massimi"""
	return current_stats.max_hp

func refresh_display() -> void:
	"""Forza un refresh completo del display"""
	_update_stats()

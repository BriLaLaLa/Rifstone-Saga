# File: res://scripts/battle/CharacterDisplay.gd
# Display del personaggio con equipment slots e statistiche

extends Control
class_name CharacterDisplay

const LOG := true

# UI References
@onready var hp_bar: ProgressBar = $StatsPanel/HPBar
@onready var hp_label: Label = $StatsPanel/HPBar/HPLabel
@onready var level_label: Label = $StatsPanel/LevelLabel
@onready var attack_label: Label = $StatsPanel/AttackLabel
@onready var defense_label: Label = $StatsPanel/DefenseLabel

# Equipment slots
@onready var helmet_slot: Panel = $EquipmentSlots/HelmetSlot
@onready var weapon_slot: Panel = $EquipmentSlots/WeaponSlot
@onready var chest_slot: Panel = $EquipmentSlots/ChestSlot
@onready var shield_slot: Panel = $EquipmentSlots/ShieldSlot
@onready var belt_slot: Panel = $EquipmentSlots/BeltSlot
@onready var boots_slot: Panel = $EquipmentSlots/BootsSlot

# Mapping slot panel -> slot name
var slot_mapping := {
	"HelmetSlot": "helmet",
	"WeaponSlot": "weapon",
	"ChestSlot": "chest",
	"ShieldSlot": "shield",
	"BeltSlot": "belt",
	"BootsSlot": "boots"
}

# Equipment visuals (TextureRect per mostrare icons)
var equipment_visuals := {}

func _ready() -> void:
	_setup_equipment_slots()
	_connect_to_gamestate()
	_update_all_stats()
	
	if LOG:
		print("[CharacterDisplay] Ready with stats system")

func _setup_equipment_slots() -> void:
	"""Setup dei pannelli equipment per drag & drop"""
	var slots = [helmet_slot, weapon_slot, chest_slot, shield_slot, belt_slot, boots_slot]
	
	for slot_panel in slots:
		if slot_panel == null:
			continue
		
		# Crea TextureRect per l'icon dell'item
		var texture_rect = TextureRect.new()
		texture_rect.name = "ItemIcon"
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(texture_rect)
		
		equipment_visuals[slot_panel.name] = texture_rect
		
		# Setup drag & drop
		slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	if LOG:
		print("[CharacterDisplay] Equipment slots setup complete")

func _connect_to_gamestate() -> void:
	"""Connetti ai segnali del GameState"""
	if not Engine.has_singleton("GameState"):
		return
	
	var gs = Engine.get_singleton("GameState")
	if gs == null:
		return
	
	# Connetti segnali stats
	if gs.has_signal("on_stats_changed"):
		if not gs.on_stats_changed.is_connected(_update_all_stats):
			gs.on_stats_changed.connect(_update_all_stats)
	
	if gs.has_signal("on_item_equipped"):
		if not gs.on_item_equipped.is_connected(_on_item_equipped):
			gs.on_item_equipped.connect(_on_item_equipped)
	
	if gs.has_signal("on_item_unequipped"):
		if not gs.on_item_unequipped.is_connected(_on_item_unequipped):
			gs.on_item_unequipped.connect(_on_item_unequipped)
	
	# Connetti segnali HP/Mana
	if gs.has("character_stats") and gs.character_stats:
		var stats = gs.character_stats
		if stats.has_signal("hp_changed"):
			if not stats.hp_changed.is_connected(_on_hp_changed):
				stats.hp_changed.connect(_on_hp_changed)
		if stats.has_signal("mana_changed"):
			if not stats.mana_changed.is_connected(_on_mana_changed):
				stats.mana_changed.connect(_on_mana_changed)
	
	if LOG:
		print("[CharacterDisplay] Connected to GameState signals")

# ============================================
# UPDATE STATS UI
# ============================================

func _update_all_stats() -> void:
	"""Aggiorna tutte le statistiche visualizzate"""
	if not Engine.has_singleton("GameState"):
		return
	
	var gs = Engine.get_singleton("GameState")
	if gs == null or not gs.has("character_stats") or gs.character_stats == null:
		return
	
	var stats = gs.character_stats
	
	# Aggiorna HP
	_on_hp_changed(stats.current_hp, stats.get_stat("max_hp"))
	
	# Aggiorna level (se disponibile)
	if level_label:
		var level = 1  # TODO: Prendi dal GameState quando implementerai il leveling
		level_label.text = "Level: %d" % level
	
	# Aggiorna Attack
	if attack_label:
		var phys_dmg = stats.get_stat("physical_damage")
		var strength = stats.get_stat("strength")
		var total_attack = phys_dmg + (strength * 0.5)
		attack_label.text = "⚔️ Attack: %d" % int(total_attack)
	
	# Aggiorna Defense
	if defense_label:
		var phys_def = stats.get_stat("physical_defense")
		var vitality = stats.get_stat("vitality")
		var total_defense = phys_def + (vitality * 0.3)
		defense_label.text = "🛡️ Defense: %d" % int(total_defense)
	
	if LOG:
		print("[CharacterDisplay] Stats updated - HP: %d/%d, ATK: %d, DEF: %d" % [
			stats.current_hp, 
			stats.get_stat("max_hp"),
			int(stats.get_stat("physical_damage")),
			int(stats.get_stat("physical_defense"))
		])

func _on_hp_changed(current: float, maximum: float) -> void:
	"""Callback quando l'HP cambia"""
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
		
		# Cambia colore in base alla percentuale
		var percent = current / maximum if maximum > 0 else 0
		if percent > 0.5:
			hp_bar.modulate = Color.GREEN
		elif percent > 0.25:
			hp_bar.modulate = Color.YELLOW
		else:
			hp_bar.modulate = Color.RED
	
	if hp_label:
		hp_label.text = "%d / %d" % [int(current), int(maximum)]

func _on_mana_changed(current: float, maximum: float) -> void:
	"""Callback quando il Mana cambia (se hai una barra mana)"""
	pass  # TODO: Aggiungi mana bar se necessario

# ============================================
# EQUIPMENT CALLBACKS
# ============================================

func _on_item_equipped(slot: String, item_data: Dictionary) -> void:
	"""Callback quando un item viene equipaggiato"""
	if LOG:
		print("[CharacterDisplay] Item equipped in %s: %s" % [slot, item_data.get("name", "Unknown")])
	
	_update_equipment_visual(slot, item_data)
	_update_all_stats()

func _on_item_unequipped(slot: String, item_data: Dictionary) -> void:
	"""Callback quando un item viene de-equipaggiato"""
	if LOG:
		print("[CharacterDisplay] Item unequipped from %s: %s" % [slot, item_data.get("name", "Unknown")])
	
	_clear_equipment_visual(slot)
	_update_all_stats()

func _update_equipment_visual(slot: String, item_data: Dictionary) -> void:
	"""Aggiorna la visual di un equipment slot"""
	var slot_panel_name = _get_slot_panel_name(slot)
	if slot_panel_name == "":
		return
	
	if not equipment_visuals.has(slot_panel_name):
		return
	
	var texture_rect: TextureRect = equipment_visuals[slot_panel_name]
	
	# Carica la texture dell'item
	if item_data.has("icon") and item_data.icon != "":
		var texture = load(item_data.icon)
		if texture:
			texture_rect.texture = texture
			texture_rect.visible = true
			
			if LOG:
				print("[CharacterDisplay] Updated visual for %s with icon: %s" % [slot, item_data.icon])
		else:
			if LOG:
				print("[CharacterDisplay] Failed to load icon: %s" % item_data.icon)
	else:
		texture_rect.visible = false

func _clear_equipment_visual(slot: String) -> void:
	"""Pulisce la visual di un equipment slot"""
	var slot_panel_name = _get_slot_panel_name(slot)
	if slot_panel_name == "" or not equipment_visuals.has(slot_panel_name):
		return
	
	var texture_rect: TextureRect = equipment_visuals[slot_panel_name]
	texture_rect.texture = null
	texture_rect.visible = false

func _get_slot_panel_name(slot: String) -> String:
	"""Converte slot name (helmet) in panel name (HelmetSlot)"""
	for panel_name in slot_mapping.keys():
		if slot_mapping[panel_name] == slot:
			return panel_name
	return ""

# ============================================
# DRAG & DROP HANDLING
# ============================================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Controlla se possiamo droppare un item su uno slot"""
	if typeof(data) != TYPE_DICTIONARY:
		return false
	
	if not data.has("type") or data.type != "inventory_item":
		return false
	
	if not data.has("item_id"):
		return false
	
	# Trova lo slot su cui stiamo droppando
	var target_slot = _get_slot_at_position(at_position)
	if target_slot == "":
		return false
	
	# Verifica che l'item sia equipaggiabile in questo slot
	if not Engine.has_singleton("GameState"):
		return false
	
	var gs = Engine.get_singleton("GameState")
	if gs == null or not gs.has("data"):
		return false
	
	var item_id = data.item_id
	if not gs.data.items.has(item_id):
		return false
	
	var item_data = gs.data.items[item_id]
	var item_slot = item_data.get("slot", "none")
	
	# L'item può essere equipaggiato qui?
	if item_slot == target_slot or item_slot == "any":
		return true
	
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Gestisce il drop di un item su uno slot"""
	if typeof(data) != TYPE_DICTIONARY:
		return
	
	var item_id = data.get("item_id", "")
	if item_id == "":
		return
	
	var target_slot = _get_slot_at_position(at_position)
	if target_slot == "":
		return
	
	# Equipaggia l'item
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			var success = gs.equip_item_to_slot(item_id, target_slot)
			if success:
				# Marca il drop come riuscito sull'item
				if data.has("item") and is_instance_valid(data.item):
					data.item.mark_drop_success()
				
				if LOG:
					print("[CharacterDisplay] Successfully equipped %s to %s" % [item_id, target_slot])
			else:
				if LOG:
					print("[CharacterDisplay] Failed to equip %s to %s" % [item_id, target_slot])

func _get_slot_at_position(pos: Vector2) -> String:
	"""Trova quale slot si trova alla posizione specificata"""
	var local_pos = pos
	
	# Controlla ogni slot
	var slots_to_check = [
		{"panel": helmet_slot, "name": "helmet"},
		{"panel": weapon_slot, "name": "weapon"},
		{"panel": chest_slot, "name": "chest"},
		{"panel": shield_slot, "name": "shield"},
		{"panel": belt_slot, "name": "belt"},
		{"panel": boots_slot, "name": "boots"}
	]
	
	for slot_info in slots_to_check:
		var panel = slot_info.panel
		if panel == null:
			continue
		
		var rect = Rect2(panel.global_position, panel.size)
		if rect.has_point(pos):
			return slot_info.name
	
	return ""

# ============================================
# PUBLIC API
# ============================================

func refresh_equipment() -> void:
	"""Ricarica la visualizzazione di tutto l'equipment"""
	if not Engine.has_singleton("GameState"):
		return
	
	var gs = Engine.get_singleton("GameState")
	if gs == null or not gs.has("equipped_items"):
		return
	
	# Aggiorna ogni slot
	for slot in gs.equipped_items.keys():
		var item_data = gs.get_equipped_item(slot)
		if not item_data.is_empty():
			_update_equipment_visual(slot, item_data)
		else:
			_clear_equipment_visual(slot)
	
	_update_all_stats()

func get_equipped_item_in_slot(slot: String) -> Dictionary:
	"""Ottiene l'item equipaggiato in uno slot specifico"""
	if not Engine.has_singleton("GameState"):
		return {}
	
	var gs = Engine.get_singleton("GameState")
	if gs:
		return gs.get_equipped_item(slot)
	
	return {}

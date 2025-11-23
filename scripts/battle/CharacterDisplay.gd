# File: res://scripts/battle/CharacterDisplay.gd
# Display del personaggio con equipment slots e statistiche

extends Control
class_name CharacterDisplay

# ==================== EXPORTED VARIABLES (Inspector) ====================
# Path to Main Tab's EquipmentSlots container (set in Main.tscn editor)
# Se non impostato, cercherà automaticamente a runtime
@export var main_equipment_slots_path: NodePath = NodePath("")

@export_group("Equipment Layer - Helmet")
@export var helmet_z_index: int = 5
@export var helmet_scale: float = 0.4
@export var helmet_offset: Vector2 = Vector2(0, -60)

@export_group("Equipment Layer - Weapon")
@export var weapon_z_index: int = 3
@export var weapon_scale: float = 0.5
@export var weapon_offset: Vector2 = Vector2(-40, 20)

@export_group("Equipment Layer - Chest")
@export var chest_z_index: int = 2
@export var chest_scale: float = 0.6
@export var chest_offset: Vector2 = Vector2(0, 30)

@export_group("Equipment Layer - Shield")
@export var shield_z_index: int = 4
@export var shield_scale: float = 0.5
@export var shield_offset: Vector2 = Vector2(40, 20)

@export_group("Equipment Layer - Belt")
@export var belt_z_index: int = 1
@export var belt_scale: float = 0.4
@export var belt_offset: Vector2 = Vector2(0, 60)

@export_group("Equipment Layer - Boots")
@export var boots_z_index: int = 0
@export var boots_scale: float = 0.35
@export var boots_offset: Vector2 = Vector2(0, 90)

# ==================== UI REFERENCES ====================
@onready var hp_bar: ProgressBar = $StatsPanel/HPBar
@onready var hp_label: Label = $StatsPanel/HPBar/HPLabel
@onready var level_label: Label = $StatsPanel/LevelLabel
@onready var attack_label: Label = $StatsPanel/AttackLabel
@onready var defense_label: Label = $StatsPanel/DefenseLabel
@onready var character_background: TextureRect = $CharacterBackground

# Equipment slots (local display)
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

# Equipment visuals (TextureRect per mostrare icons negli slot)
var equipment_visuals := {}

# Equipment on character (TextureRect sovrapposti al character sprite)
var character_equipment_layers := {}

# Custom tooltip for rich text with colors
var custom_tooltip: Control = null
var hovered_slot: Panel = null

func _ready() -> void:
	_setup_equipment_slots()
	_setup_character_equipment_layers()
	_connect_to_gamestate()
	_ensure_character_alive()  # Make sure character has HP
	_update_all_stats()
	_refresh_all_equipment()

	# NOTE: visibility_changed signal connected in CharacterDisplay.tscn

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Ready with stats system and equipment rendering")

func _on_visibility_changed() -> void:
	"""Refresh equipment quando il CharacterDisplay diventa visibile"""
	if visible:
		if GameLogger.ENABLED:
			print("[CharacterDisplay] Became visible, forcing full refresh...")

		# Force refresh everything
		_refresh_all_equipment()
		_update_all_stats()

		# Force redraw
		queue_redraw()

		# Force update of all TextureRects
		for texture_rect in equipment_visuals.values():
			if texture_rect:
				texture_rect.queue_redraw()

		for layer in character_equipment_layers.values():
			if layer:
				layer.queue_redraw()

func _setup_equipment_slots() -> void:
	"""Setup dei pannelli equipment per drag & drop"""
	var slots = [helmet_slot, weapon_slot, chest_slot, shield_slot, belt_slot, boots_slot]

	for slot_panel in slots:
		if slot_panel == null:
			continue

		# Get existing TextureRect from .tscn (instead of creating new one)
		var texture_rect = slot_panel.get_node_or_null("ItemIcon")
		if texture_rect == null:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ ItemIcon not found in %s, creating new one" % slot_panel.name)
			# Fallback: crea TextureRect se non esiste nel .tscn
			texture_rect = TextureRect.new()
			texture_rect.name = "ItemIcon"
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot_panel.add_child(texture_rect)

		equipment_visuals[slot_panel.name] = texture_rect

		# Setup drag & drop
		slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Equipment slots setup complete (%d slots)" % equipment_visuals.size())

func _setup_character_equipment_layers() -> void:
	"""Creates equipment rendering layers on top of the character sprite (usa valori dall'Inspector)"""
	if not character_background:
		if GameLogger.ENABLED:
			print("[CharacterDisplay] WARNING: Character background not found!")
		return

	# Define equipment layer positions using Inspector values
	var layer_configs = {
		"helmet": {"z_index": helmet_z_index, "scale": helmet_scale, "offset": helmet_offset},
		"weapon": {"z_index": weapon_z_index, "scale": weapon_scale, "offset": weapon_offset},
		"chest": {"z_index": chest_z_index, "scale": chest_scale, "offset": chest_offset},
		"shield": {"z_index": shield_z_index, "scale": shield_scale, "offset": shield_offset},
		"belt": {"z_index": belt_z_index, "scale": belt_scale, "offset": belt_offset},
		"boots": {"z_index": boots_z_index, "scale": boots_scale, "offset": boots_offset}
	}

	for slot_name in layer_configs.keys():
		var config = layer_configs[slot_name]

		# Create TextureRect for this equipment layer
		var layer = TextureRect.new()
		layer.name = "Equipment_%s" % slot_name.capitalize()
		layer.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.z_index = config["z_index"]
		layer.visible = false  # Hidden until equipped

		# Position at center with offset
		layer.set_anchors_preset(Control.PRESET_CENTER)
		layer.position = config["offset"]
		layer.custom_minimum_size = Vector2(64, 64) * config["scale"]

		# Add to character background
		character_background.add_child(layer)
		character_equipment_layers[slot_name] = layer

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Character equipment layers created: %d" % character_equipment_layers.size())

func _ensure_character_alive() -> void:
	"""Assicura che il personaggio abbia HP (resurrect se morto)"""
	# Death is now handled by BattleTab
	# Just ensure we don't display negative HP
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("character_stats" in gs) or gs.character_stats == null:
		return

	var stats = gs.character_stats
	if stats.current_hp < 0:
		stats.current_hp = 0

func _connect_to_gamestate() -> void:
	"""Connetti ai segnali del GameState"""
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		if GameLogger.ENABLED:
			print("[CharacterDisplay] ⚠️ GameState not found")
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
	if "character_stats" in gs and gs.character_stats:
		var stats = gs.character_stats
		if stats.has_signal("hp_changed"):
			if not stats.hp_changed.is_connected(_on_hp_changed):
				stats.hp_changed.connect(_on_hp_changed)
		if stats.has_signal("mana_changed"):
			if not stats.mana_changed.is_connected(_on_mana_changed):
				stats.mana_changed.connect(_on_mana_changed)
	
	if GameLogger.ENABLED:
		print("[CharacterDisplay] Connected to GameState signals")

# ============================================
# UPDATE STATS UI
# ============================================

func _update_all_stats() -> void:
	"""Aggiorna tutte le statistiche visualizzate"""
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("character_stats" in gs) or gs.character_stats == null:
		if GameLogger.ENABLED:
			print("[CharacterDisplay] ⚠️ Cannot update stats: GameState or character_stats is null")
		return

	var stats = gs.character_stats

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Updating stats - HP: %d/%d, ATK: %d, DEF: %d" % [
			stats.current_hp,
			stats.get_stat("max_hp"),
			stats.get_stat("physical_damage"),
			stats.get_stat("physical_defense")
		])

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
	
	if GameLogger.ENABLED:
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
	if GameLogger.ENABLED:
		print("[CharacterDisplay] 🔔 _on_item_equipped CALLED! Slot: %s, Item: %s" % [slot, item_data.get("name", "Unknown")])

	# Force re-sync con gli slot reali per assicurarsi che tutto sia aggiornato
	_refresh_all_equipment()
	# Note: _refresh_all_equipment già chiama _update_all_stats()

func _on_item_unequipped(slot: String, item_data: Dictionary) -> void:
	"""Callback quando un item viene de-equipaggiato"""
	if GameLogger.ENABLED:
		print("[CharacterDisplay] 🔔 Item unequipped from %s: %s" % [slot, item_data.get("name", "Unknown")])

	# Force re-sync con gli slot reali per assicurarsi che GameState sia aggiornato
	_refresh_all_equipment()
	# Note: _refresh_all_equipment già chiama _update_all_stats()

func _update_equipment_visual(slot: String, item_data: Dictionary) -> void:
	"""Aggiorna la visual di un equipment slot"""
	if GameLogger.ENABLED:
		print("[CharacterDisplay] _update_equipment_visual called for slot: %s, item: %s" % [slot, item_data.get("name", "Unknown")])

	var slot_panel_name = _get_slot_panel_name(slot)
	if slot_panel_name == "":
		if GameLogger.ENABLED:
			print("[CharacterDisplay] ⚠️ No panel name found for slot: %s" % slot)
		return

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Mapped slot '%s' to panel '%s'" % [slot, slot_panel_name])

	# Update equipment slot panel icon
	if equipment_visuals.has(slot_panel_name):
		var texture_rect: TextureRect = equipment_visuals[slot_panel_name]
		var slot_panel = _get_slot_panel_by_name(slot_panel_name)

		# Carica la texture dell'item
		if item_data.has("icon") and item_data.icon != "":
			var texture = load(item_data.icon)
			if texture:
				texture_rect.texture = texture
				texture_rect.visible = true

				# Add tooltip to slot panel
				if slot_panel:
					_update_slot_tooltip(slot_panel, item_data)

				if GameLogger.ENABLED:
					print("[CharacterDisplay] Updated slot visual for %s with icon: %s" % [slot, item_data.icon])
			else:
				if GameLogger.ENABLED:
					print("[CharacterDisplay] Failed to load icon: %s" % item_data.icon)
		else:
			texture_rect.visible = false
			if slot_panel:
				slot_panel.tooltip_text = ""  # Clear tooltip

	# Update character equipment layer (on character sprite)
	if character_equipment_layers.has(slot):
		var layer: TextureRect = character_equipment_layers[slot]

		if item_data.has("icon") and item_data.icon != "":
			var texture = load(item_data.icon)
			if texture:
				layer.texture = texture
				layer.visible = true

				if GameLogger.ENABLED:
					print("[CharacterDisplay] ✅ Rendered %s on character sprite" % slot)
			else:
				layer.visible = false
		else:
			layer.visible = false

func _clear_equipment_visual(slot: String) -> void:
	"""Pulisce la visual di un equipment slot"""
	var slot_panel_name = _get_slot_panel_name(slot)

	# Clear slot panel icon
	if slot_panel_name != "" and equipment_visuals.has(slot_panel_name):
		var texture_rect: TextureRect = equipment_visuals[slot_panel_name]
		texture_rect.texture = null
		texture_rect.visible = false

	# Clear character equipment layer
	if character_equipment_layers.has(slot):
		var layer: TextureRect = character_equipment_layers[slot]
		layer.texture = null
		layer.visible = false

		if GameLogger.ENABLED:
			print("[CharacterDisplay] Cleared %s from character sprite" % slot)

func _get_slot_panel_name(slot: String) -> String:
	"""Converte slot name (helmet) in panel name (HelmetSlot)"""
	for panel_name in slot_mapping.keys():
		if slot_mapping[panel_name] == slot:
			return panel_name
	return ""

func _get_slot_panel_by_name(panel_name: String) -> Panel:
	"""Get the Panel node by its name"""
	match panel_name:
		"HelmetSlot": return helmet_slot
		"WeaponSlot": return weapon_slot
		"ChestSlot": return chest_slot
		"ShieldSlot": return shield_slot
		"BeltSlot": return belt_slot
		"BootsSlot": return boots_slot
	return null

func _update_slot_tooltip(slot_panel: Panel, item_data: Dictionary) -> void:
	"""Setup custom tooltip with RichTextLabel for BBCode support (colors!)"""
	# Get the TextureRect inside the Panel (ItemIcon)
	var texture_rect = slot_panel.get_node_or_null("ItemIcon")
	if not texture_rect:
		return

	# Store item_data on the slot for tooltip generation
	slot_panel.set_meta("item_data", item_data)

	# Enable mouse filter for hover detection
	texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	# Connect mouse signals if not already connected
	if not texture_rect.mouse_entered.is_connected(_on_slot_mouse_entered):
		texture_rect.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_panel))
	if not texture_rect.mouse_exited.is_connected(_on_slot_mouse_exited):
		texture_rect.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_panel))

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Tooltip configured for %s:" % slot_panel.name)
		print("  Item: %s (has bonuses: %s)" % [item_data.get("name", "Unknown"), item_data.has("bonuses")])

func _get_rarity_color(rarity: String) -> Color:
	"""Ottieni colore basato su rarità (stesso sistema di ItemTooltip)"""
	match rarity.to_lower():
		"common": return Color.WHITE
		"uncommon": return Color.GREEN
		"rare": return Color.BLUE
		"epic": return Color.PURPLE
		"legendary": return Color.ORANGE
		"artifact": return Color.RED
		_: return Color.WHITE


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
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("data" in gs):
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
	var gs = get_node_or_null("/root/GameState")
	if gs:
			var success = gs.equip_item_to_slot(item_id, target_slot)
			if success:
				# Marca il drop come riuscito sull'item
				if data.has("item") and is_instance_valid(data.item):
					data.item.mark_drop_success()
				
				if GameLogger.ENABLED:
					print("[CharacterDisplay] Successfully equipped %s to %s" % [item_id, target_slot])
			else:
				if GameLogger.ENABLED:
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
	_refresh_all_equipment()

func _refresh_all_equipment() -> void:
	"""Internal method to refresh all equipment visuals"""
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("equipped_items" in gs):
		if GameLogger.ENABLED:
			print("[CharacterDisplay] ⚠️ Cannot refresh equipment: GameState or equipped_items missing")
		return

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Refreshing all equipment from GameState...")
		print("[CharacterDisplay] Equipped items: %s" % gs.equipped_items)

	# VERIFICA: Sincronizza GameState con gli EquipmentSlot reali nella Main Tab
	var real_equipment = _get_real_equipment_from_main_tab()
	if real_equipment != null:
		if GameLogger.ENABLED:
			print("[CharacterDisplay] Verifying equipment with Main Tab slots...")

		# Pulisci equipment in GameState che non è realmente negli slot
		for slot in gs.equipped_items.keys():
			var in_gamestate = gs.equipped_items[slot]
			var in_real_slot = real_equipment.get(slot, null)

			if in_gamestate != null and in_real_slot == null:
				# GameState dice che c'è equipment ma lo slot è vuoto
				if GameLogger.ENABLED:
					print("[CharacterDisplay] ⚠️ Clearing ghost equipment in slot '%s' (not in real slot)" % slot)
				gs.equipped_items[slot] = null
			elif in_real_slot != null and in_gamestate == null:
				# C'è equipment nello slot ma GameState non lo sa
				if GameLogger.ENABLED:
					print("[CharacterDisplay] ✅ Adding missing equipment to GameState for slot '%s'" % slot)
				gs.equipped_items[slot] = in_real_slot

	# Aggiorna ogni slot
	for slot in gs.equipped_items.keys():
		var item_data = gs.get_equipped_item(slot)
		if not item_data.is_empty():
			if GameLogger.ENABLED:
				print("[CharacterDisplay] Updating slot '%s' with item: %s" % [slot, item_data.get("name", "Unknown")])
			_update_equipment_visual(slot, item_data)
		else:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] Clearing slot '%s' (no item equipped)" % slot)
			_clear_equipment_visual(slot)

	_update_all_stats()

func _get_real_equipment_from_main_tab():
	"""Cerca gli EquipmentSlot reali nella Main Tab e legge cosa c'è equipaggiato.
	Ritorna Dictionary con equipment reale, oppure null se non riesce a trovare la Main Tab."""

	var equipment_slots_container = null

	# METODO 1: Usa NodePath impostato nell'editor (più pulito!)
	if not main_equipment_slots_path.is_empty():
		equipment_slots_container = get_node_or_null(main_equipment_slots_path)
		if equipment_slots_container != null:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ✅ Using NodePath from editor: %s" % main_equipment_slots_path)
		else:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ NodePath set but node not found: %s" % main_equipment_slots_path)

	# METODO 2: Fallback - Cerca automaticamente (come prima)
	if equipment_slots_container == null:
		if GameLogger.ENABLED:
			print("[CharacterDisplay] Searching for EquipmentSlots automatically...")

		var main = get_tree().root.get_node_or_null("Main")
		if main == null:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ Cannot find Main node")
			return null

		# Path: Main/Margin/VBox/Tabs/Inventory/InvSplit/Right/EquipmentPanel/EquipmentSlots
		var tab_container = main.get_node_or_null("Margin/VBox/Tabs")
		if tab_container == null:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ Cannot find Tabs (TabContainer)")
			return null

		var inventory_tab = tab_container.get_node_or_null("Inventory")
		if inventory_tab == null:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ Cannot find Inventory tab")
			return null

		equipment_slots_container = inventory_tab.get_node_or_null("InvSplit/Right/EquipmentPanel/EquipmentSlots")
		if equipment_slots_container == null:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ Cannot find EquipmentSlots container")
			return null

		if GameLogger.ENABLED:
			print("[CharacterDisplay] ✅ Found EquipmentSlots via automatic search")

	# Mappa dei nomi dei nodi EquipmentSlot al tipo slot
	var slot_node_names = {
		"HelmetSlot": "helmet",
		"WeaponSlot": "weapon",
		"ChestSlot": "chest",
		"ShieldSlot": "shield",
		"BeltSlot": "belt",
		"BootsSlot": "boots"
	}

	var real_equipment = {}
	var gs = get_node_or_null("/root/GameState")

	# Cerca ogni EquipmentSlot e leggi cosa c'è equipaggiato
	for node_name in slot_node_names.keys():
		var slot_type = slot_node_names[node_name]
		var equipment_slot = equipment_slots_container.get_node_or_null(node_name)

		if equipment_slot != null and equipment_slot is EquipmentSlot:
			var equipped_item = equipment_slot.equipped_item  # Leggi direttamente la variabile
			if equipped_item != null:
				# C'è un item equipaggiato, ottieni i suoi dati da GameState
				var item_id = equipped_item.item_id
				if gs and "data" in gs and gs.data.has("items"):
					var item_data = gs.data.items.get(item_id, {})
					if not item_data.is_empty():
						real_equipment[slot_type] = item_data
						if GameLogger.ENABLED:
							print("[CharacterDisplay] ✅ Found real equipment in %s: %s" % [slot_type, item_data.get("name", item_id)])
			else:
				if GameLogger.ENABLED:
					print("[CharacterDisplay] Slot %s is empty" % slot_type)

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Real equipment from Main Tab: %s" % real_equipment)

	return real_equipment

func get_equipped_item_in_slot(slot: String) -> Dictionary:
	"""Ottiene l'item equipaggiato in uno slot specifico"""
	var gs = get_node_or_null("/root/GameState")
	if gs:
		return gs.get_equipped_item(slot)

	return {}

# ============================================
# CUSTOM TOOLTIP (RichTextLabel with BBCode)
# ============================================

func _on_slot_mouse_entered(slot_panel: Panel) -> void:
	"""Show custom tooltip when hovering over equipment slot"""
	hovered_slot = slot_panel

	# Get item data from slot metadata
	if not slot_panel.has_meta("item_data"):
		return

	var item_data = slot_panel.get_meta("item_data")
	_show_custom_tooltip(item_data)

func _on_slot_mouse_exited(slot_panel: Panel) -> void:
	"""Hide custom tooltip when leaving equipment slot"""
	if hovered_slot == slot_panel:
		hovered_slot = null
		_hide_custom_tooltip()

func _show_custom_tooltip(item_data: Dictionary) -> void:
	"""Create and show custom tooltip with RichTextLabel (same as CraftableItem)"""
	_hide_custom_tooltip()  # Hide any existing tooltip

	# Build tooltip text with BBCode
	var tooltip_lines: Array[String] = []

	# 1. NOME (bold)
	if item_data.has("name"):
		tooltip_lines.append("[b]%s[/b]" % item_data["name"])

	# 2. TIPO
	if item_data.has("type"):
		tooltip_lines.append("Type: %s" % item_data["type"])

	# 3. STATS
	if item_data.has("stats"):
		var stats = item_data.stats

		if stats.has("physical_damage") and stats.physical_damage > 0:
			tooltip_lines.append("Attack: +%d" % stats.physical_damage)

		if stats.has("physical_defense") and stats.physical_defense > 0:
			tooltip_lines.append("Defense: +%d" % stats.physical_defense)

		if stats.has("max_hp") and stats.max_hp > 0:
			tooltip_lines.append("HP: +%d" % stats.max_hp)

		if stats.has("vitality") and stats.vitality > 0:
			tooltip_lines.append("Vitality: +%d" % stats.vitality)

		if stats.has("strength") and stats.strength > 0:
			tooltip_lines.append("Strength: +%d" % stats.strength)

		if stats.has("block_chance") and stats.block_chance > 0:
			tooltip_lines.append("Block: +%d%%" % stats.block_chance)

	# 4. BONUSES (con colori!)
	if item_data.has("bonuses") and item_data.bonuses.size() > 0:
		tooltip_lines.append("")
		tooltip_lines.append("[b]--- Bonuses ---[/b]")

		const ItemBonus = preload("res://scripts/crafting/ItemBonus.gd")

		for bonus_dict in item_data.bonuses:
			var bonus = ItemBonus.new()
			bonus.from_dict(bonus_dict)

			var bonus_color = bonus.get_color()
			var bonus_text = bonus.get_display_text()
			var tier_text = bonus.get_tier_name()

			tooltip_lines.append("[color=%s]%s [%s][/color]" %
				[bonus_color.to_html(), bonus_text, tier_text])

	# 5. DESCRIZIONE (italic)
	if item_data.has("description"):
		tooltip_lines.append("")
		tooltip_lines.append("[i]%s[/i]" % item_data.description)

	var tooltip_text_full = "\n".join(tooltip_lines)

	# Create tooltip panel
	custom_tooltip = PanelContainer.new()
	custom_tooltip.z_index = 1000

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	custom_tooltip.add_theme_stylebox_override("panel", style)

	# Margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	custom_tooltip.add_child(margin)

	# RichTextLabel for BBCode support
	var rich_label = RichTextLabel.new()
	rich_label.bbcode_enabled = true
	rich_label.fit_content = true
	rich_label.scroll_active = false
	rich_label.text = tooltip_text_full
	rich_label.custom_minimum_size = Vector2(250, 0)
	margin.add_child(rich_label)

	# Add to scene tree
	get_tree().root.add_child(custom_tooltip)

	# Position near mouse
	await get_tree().process_frame

	# Check if tooltip still exists after await
	if not custom_tooltip or not is_instance_valid(custom_tooltip):
		return

	var mouse_pos = get_viewport().get_mouse_position()
	custom_tooltip.global_position = mouse_pos + Vector2(15, -10)

func _hide_custom_tooltip() -> void:
	"""Remove custom tooltip"""
	if custom_tooltip:
		custom_tooltip.queue_free()
		custom_tooltip = null

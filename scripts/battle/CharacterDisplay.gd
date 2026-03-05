# File: res://scripts/battle/CharacterDisplay.gd
# Display del personaggio con equipment slots e statistiche

extends Control
class_name CharacterDisplay

# Item scene for creating equipment visuals with particle effects
const ITEM_SCENE = preload("res://scripts/ui/Item.tscn")

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
# enemy_attack_bar and enemy_attack_label REMOVED - old system
@onready var character_background: TextureRect = $CharacterBackground

# Level UI
@onready var level_panel: PanelContainer = $StatsPanel/LevelPanel
@onready var level_label: Label = $StatsPanel/LevelPanel/VBox/LevelLabel
@onready var exp_bar: ProgressBar = $StatsPanel/LevelPanel/VBox/ExpBar
@onready var exp_label: Label = $StatsPanel/LevelPanel/VBox/ExpLabel

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

# Hovered slot tracking (for tooltip)
var hovered_slot: Panel = null

func _ready() -> void:
	print("[CharacterDisplay] 🔧 _ready() called")
	_setup_equipment_slots()
	_setup_character_equipment_layers()
	_connect_to_gamestate()
	_ensure_character_alive()  # Make sure character has HP
	_update_all_stats()
	_update_level_display()  # Initialize level display
	print("[CharacterDisplay] ✅ _ready() completed")

	# DON'T call _refresh_all_equipment() here - it clears equipped_items if slots are empty!
	# Instead, refresh_equipped_items() is called in _connect_to_gamestate()

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

		# Setup drag & drop - Forward drop events from Panel to CharacterDisplay
		slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # Stop events at panel
		print("[CharacterDisplay] 🔧 Setting up drag forwarding for: %s" % slot_panel.name)
		print("[CharacterDisplay]   → mouse_filter: %s (STOP)" % slot_panel.mouse_filter)
		print("[CharacterDisplay]   → position: %s, size: %s" % [slot_panel.global_position, slot_panel.size])

		# Forward drag & drop to CharacterDisplay's methods
		slot_panel.set_drag_forwarding(
			Callable(),  # No custom drag preview
			Callable(self, "_can_drop_data"),  # Forward can_drop_data to CharacterDisplay
			Callable(self, "_drop_data")  # Forward drop_data to CharacterDisplay
		)
		print("[CharacterDisplay]   → drag_forwarding set to CharacterDisplay methods")

		# Enable mouse detection for tooltips (even on empty slots)
		if texture_rect:
			# Use IGNORE so texture_rect doesn't intercept drop events
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Connect tooltip signals to panel (not texture_rect)
			if not slot_panel.mouse_entered.is_connected(_on_slot_mouse_entered):
				slot_panel.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_panel))
			if not slot_panel.mouse_exited.is_connected(_on_slot_mouse_exited):
				slot_panel.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_panel))

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
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ✅ Connected to on_item_equipped signal")
		else:
			if GameLogger.ENABLED:
				print("[CharacterDisplay] ⚠️ on_item_equipped already connected")
	
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

		# Connect level signals
		if stats.has_signal("level_up"):
			if not stats.level_up.is_connected(_on_player_level_up):
				stats.level_up.connect(_on_player_level_up)
				if GameLogger.ENABLED:
					print("[CharacterDisplay] ✅ Connected to level_up signal")
		if stats.has_signal("exp_gained"):
			if not stats.exp_gained.is_connected(_on_player_exp_gained):
				stats.exp_gained.connect(_on_player_exp_gained)
				if GameLogger.ENABLED:
					print("[CharacterDisplay] ✅ Connected to exp_gained signal")

	print("[CharacterDisplay] ✅ Connected to GameState signals")

	# CRITICAL: Request refresh of equipped items after connecting
	# This ensures equipment loaded from save is displayed
	if gs.has_method("refresh_equipped_items"):
		print("[CharacterDisplay] 🔄 Requesting equipment refresh from GameState...")
		gs.refresh_equipped_items()
		print("[CharacterDisplay] ✅ Equipment refresh completed")
	else:
		print("[CharacterDisplay] ⚠️ GameState doesn't have refresh_equipped_items() method!")

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

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Stats updated - HP: %d/%d" % [
			stats.current_hp,
			stats.get_stat("max_hp")
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

func _update_level_display() -> void:
	"""Update level and EXP bar display"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.character_stats:
		return

	var level = gs.character_stats.get_level()
	var current_exp = gs.character_stats.get_current_exp()
	var exp_to_next = gs.character_stats.get_exp_to_next_level()
	var progress = gs.character_stats.get_exp_progress()

	if level_label:
		level_label.text = "Level %d" % level

	if exp_bar:
		exp_bar.value = progress * 100.0

	if exp_label:
		exp_label.text = "%d / %d EXP" % [current_exp, exp_to_next]

	if GameLogger.ENABLED:
		print("[CharacterDisplay] Level display updated: Level %d, EXP %d/%d (%.1f%%)" % [level, current_exp, exp_to_next, progress * 100.0])

func _on_player_level_up(new_level: int) -> void:
	"""Called when player levels up"""
	_update_level_display()

	if GameLogger.ENABLED:
		print("[CharacterDisplay] 🎉 LEVEL UP! New level: %d" % new_level)

func _on_player_exp_gained(amount: int, current_exp: int, exp_to_next: int) -> void:
	"""Called when player gains EXP"""
	_update_level_display()

# OLD ENEMY ATTACK TIMER SYSTEM REMOVED
# update_enemy_attack_timer() and hide_enemy_attack_timer() removed
# Enemy attacks now shown per-enemy in EnemySlot.gd

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
	print("[CharacterDisplay] 🔔 Item unequipped from %s: %s" % [slot, item_data.get("name", "Unknown")])

	# Force re-sync con gli slot reali per assicurarsi che GameState sia aggiornato
	_refresh_all_equipment()
	# Note: _refresh_all_equipment già chiama _update_all_stats()

func _update_equipment_visual(slot: String, item_data: Dictionary) -> void:
	"""Aggiorna la visual di un equipment slot"""
	print("[CharacterDisplay] 🔧 _update_equipment_visual called for slot: %s, item: %s, enhancement: %s" % [
		slot,
		item_data.get("name", "Unknown"),
		item_data.get("enhancement_level", 0)
	])

	var slot_panel_name = _get_slot_panel_name(slot)
	print("[CharacterDisplay] → slot_panel_name: %s" % slot_panel_name)

	if slot_panel_name == "":
		print("[CharacterDisplay] ⚠️ No panel name found for slot: %s" % slot)
		return

	# Update equipment slot panel icon
	if equipment_visuals.has(slot_panel_name):
		var texture_rect: TextureRect = equipment_visuals[slot_panel_name]
		var slot_panel = _get_slot_panel_by_name(slot_panel_name)

		print("[CharacterDisplay] → equipment_visuals has slot_panel_name: true")
		print("[CharacterDisplay] → texture_rect: %s" % texture_rect)
		print("[CharacterDisplay] → slot_panel: %s" % slot_panel)

		# CRITICAL: Clear any existing Item nodes and Labels first (prevents duplicates)
		if slot_panel:
			print("[CharacterDisplay] 🧹 Cleaning slot_panel children, count: %d" % slot_panel.get_child_count())
			for child in slot_panel.get_children():
				print("[CharacterDisplay] → Child: %s (type: %s)" % [child.name, child.get_class()])

				# Keep ONLY the original ItemIcon TextureRect, remove everything else
				if child.name == "ItemIcon" and child is TextureRect:
					# This is the original TextureRect - keep it but clean its children
					for subchild in child.get_children():
						print("[CharacterDisplay] → → Subchild of ItemIcon: %s (type: %s)" % [subchild.name, subchild.get_class()])
						subchild.queue_free()
						print("[CharacterDisplay] ✅ Removed '%s' from inside ItemIcon" % subchild.name)
				else:
					# Remove any other child (Item nodes, Labels, extra TextureRects, etc.)
					child.queue_free()
					print("[CharacterDisplay] ✅ Removed %s '%s' from %s" % [child.get_class(), child.name, slot_panel_name])

		# Carica la texture dell'item
		if item_data.has("icon") and item_data.icon != "":
			print("[CharacterDisplay] → Loading icon: %s" % item_data.icon)
			var texture = load(item_data.icon)
			if texture:
				print("[CharacterDisplay] → Texture loaded successfully")
				print("[CharacterDisplay] → Checking enhancement: slot_panel=%s, has_enh=%s, enh_level=%s" % [
					slot_panel != null,
					item_data.has("enhancement_level"),
					item_data.get("enhancement_level", 0)
				])

				# CRITICAL FIX: Create Item node with particle effects if enhancement level >= 7
				var has_slot = slot_panel != null
				var has_enh_key = item_data.has("enhancement_level")
				var enh_level = item_data.get("enhancement_level", 0)
				var meets_level = enh_level >= 7
				print("[CharacterDisplay] → Particle condition check: has_slot=%s, has_enh_key=%s, enh_level=%s, meets_level=%s" % [has_slot, has_enh_key, enh_level, meets_level])

				if slot_panel and item_data.has("enhancement_level") and item_data.enhancement_level >= 7:
					print("[CharacterDisplay] ✨ ENTERING PARTICLE CREATION BLOCK")
					var item_node = ITEM_SCENE.instantiate() as Item
					if item_node:
						# Setup item with data (this creates particles)
						item_node.setup_item(item_data.get("id", "unknown"), item_data)
						item_node.set_enhancement_level(item_data.enhancement_level)

						# Position item to match TextureRect
						item_node.position = texture_rect.position
						item_node.custom_minimum_size = texture_rect.custom_minimum_size
						item_node.size = texture_rect.size

						# CRITICAL: Disable clip_contents to allow particles to be visible
						item_node.clip_contents = false

						# Make it non-interactive (display only)
						item_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
						item_node.set_meta("is_draggable", false)

						# CRITICAL: Disable native tooltip on Item node (we use CustomTooltip instead)
						item_node.tooltip_text = ""

						# Add to slot panel (on top of TextureRect)
						slot_panel.add_child(item_node)

						# CRITICAL: Hide the TextureRect since Item node will display the texture
						texture_rect.visible = false

						if GameLogger.ENABLED:
							print("[CharacterDisplay] ✨ Created Item with +%d enhancement particles for %s" % [item_data.enhancement_level, slot])
				else:
					print("[CharacterDisplay] ❌ NOT creating particles - using TextureRect instead")
					# No particles needed - just show the TextureRect
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

	# CRITICAL: Also clear ALL children from the slot panel (labels, items, etc.)
	var slot_panel = _get_slot_panel_by_name(slot_panel_name)
	if slot_panel:
		# CRITICAL FIX: Remove the item_data metadata that causes tooltip to show old item
		if slot_panel.has_meta("item_data"):
			slot_panel.remove_meta("item_data")
			print("[CharacterDisplay] ✅ Removed item_data metadata from %s" % slot_panel_name)

		for child in slot_panel.get_children():
			# Don't remove the TextureRect itself (it's managed)
			if child != equipment_visuals.get(slot_panel_name):
				child.queue_free()
				if GameLogger.ENABLED:
					print("[CharacterDisplay] Removed child from %s: %s" % [slot_panel_name, child.name])

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

	# CRITICAL: Disable native Godot tooltips (we use CustomTooltip instead)
	slot_panel.tooltip_text = ""
	texture_rect.tooltip_text = ""

	# Store item_data on the slot for tooltip generation
	slot_panel.set_meta("item_data", item_data)

	# Enable mouse filter for hover detection
	# Use PASS instead of STOP to allow drop events to reach the item below
	texture_rect.mouse_filter = Control.MOUSE_FILTER_PASS

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
	print("[CharacterDisplay] 🔧 _can_drop_data CALLED at position: %s" % at_position)
	print("[CharacterDisplay] → Mouse global position: %s" % get_viewport().get_mouse_position())

	if typeof(data) != TYPE_DICTIONARY:
		print("[CharacterDisplay] ❌ Data is not Dictionary: %s" % typeof(data))
		return false

	if not data.has("type") or data.type != "inventory_item":
		print("[CharacterDisplay] ❌ Not inventory_item type")
		return false

	if not data.has("item_id"):
		print("[CharacterDisplay] ❌ No item_id in data")
		return false

	print("[CharacterDisplay] → item_id: %s" % data.item_id)

	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("data" in gs):
		print("[CharacterDisplay] ❌ GameState not found")
		return false

	var item_id = data.item_id
	if not gs.data.items.has(item_id):
		print("[CharacterDisplay] ❌ Item not in database: %s" % item_id)
		return false

	var item_data = gs.data.items[item_id]
	var item_type = item_data.get("type", "")
	print("[CharacterDisplay] → item_type: %s" % item_type)

	# CASO 1: Gem being dropped - check if slot has equipped weapon/armor
	if item_type == "Gem":
		print("[CharacterDisplay] 🔹 CASE 1: Gem detected, checking slot...")
		var target_slot = _get_slot_at_position(at_position)
		print("[CharacterDisplay] → target_slot found: '%s'" % target_slot)

		if target_slot == "":
			print("[CharacterDisplay] ❌ No slot at position %s" % at_position)
			return false

		# Check if there's an equipped item in this slot
		var equipped_item = gs.get_equipped_item(target_slot)
		print("[CharacterDisplay] → equipped_item in slot: %s" % equipped_item.get("name", "None"))

		if equipped_item.is_empty():
			print("[CharacterDisplay] ❌ Cannot drop gem - slot %s is empty" % target_slot)
			return false

		# Check if equipped item is a weapon (gems can only go on weapons for now)
		var equipped_type = equipped_item.get("type", "")
		print("[CharacterDisplay] → equipped_type: %s" % equipped_type)

		if equipped_type == "Weapon":
			print("[CharacterDisplay] ✅ Can drop gem %s on weapon in slot %s" % [item_id, target_slot])
			return true

		print("[CharacterDisplay] ❌ Cannot drop gem - %s is not a weapon (type: %s)" % [target_slot, equipped_type])
		return false

	# CASO 2: Regular equipment item - check if it can be equipped to this slot
	print("[CharacterDisplay] 🔹 CASE 2: Regular equipment, checking slot...")
	var target_slot = _get_slot_at_position(at_position)
	print("[CharacterDisplay] → target_slot: '%s'" % target_slot)

	if target_slot == "":
		print("[CharacterDisplay] ❌ No slot at position %s" % at_position)
		return false

	var item_slot = item_data.get("slot", "none")
	print("[CharacterDisplay] → item_slot: %s" % item_slot)

	# L'item può essere equipaggiato qui?
	if item_slot == target_slot or item_slot == "any":
		print("[CharacterDisplay] ✅ Can equip %s to %s" % [item_id, target_slot])
		return true

	print("[CharacterDisplay] ❌ Cannot equip - slot mismatch")
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

	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	var item_data = gs.data.items.get(item_id, {})
	var item_type = item_data.get("type", "")

	# CASO 1: Gem being dropped on equipped weapon/armor
	if item_type == "Gem":
		var equipped_item = gs.get_equipped_item(target_slot)
		if equipped_item.is_empty():
			if GameLogger.ENABLED:
				print("[CharacterDisplay] Cannot apply gem - slot is empty")
			return

		# Apply gem using GemCrafting system
		var gem_crafting = get_node_or_null("/root/GemCrafting")
		if not gem_crafting:
			push_error("[CharacterDisplay] GemCrafting system not found!")
			return

		if GameLogger.ENABLED:
			print("[CharacterDisplay] Applying gem %s to equipped item in slot %s" % [item_id, target_slot])

		# Apply gem to equipped item
		var result = gem_crafting.apply_gem_to_item(equipped_item, item_id)

		# Update equipped item in GameState with new bonuses
		gs.equipped_items[target_slot] = result.item

		if GameLogger.ENABLED:
			print("[CharacterDisplay] ✅ Gem applied! New bonuses: %d" % result.item.bonuses.size())

		# Refresh visual to show updated item
		_refresh_all_equipment()

		# If gem was consumed, remove it from inventory
		if result.gem_consumed:
			# Remove from inventory count
			if "inventory" in gs:
				var inv = gs.get("inventory")
				if inv.has(item_id):
					inv[item_id] = max(0, inv[item_id] - 1)
					if inv[item_id] == 0:
						inv.erase(item_id)

			# Remove from inventory_items (positions)
			var gem_item = data.get("item", null)
			if gem_item:
				# Find InventoryTab to get gem position
				var inv_tab = _find_inventory_tab()
				if inv_tab and inv_tab.has_method("get_item_position"):
					var gem_pos = inv_tab.get_item_position(gem_item)
					if gem_pos != Vector2i(-1, -1):
						# Remove from inventory_items array
						for i in range(gs.inventory_items.size() - 1, -1, -1):
							var inv_item = gs.inventory_items[i]
							var inv_pos = inv_item.get("pos")
							var pos_vec: Vector2i
							if inv_pos is Dictionary:
								pos_vec = Vector2i(inv_pos.get("x", 0), inv_pos.get("y", 0))
							else:
								pos_vec = inv_pos

							if inv_item.get("item_id") == item_id and pos_vec == gem_pos:
								gs.inventory_items.remove_at(i)
								if GameLogger.ENABLED:
									print("[CharacterDisplay] 🗑️ Removed gem from inventory_items")
								break

				# Remove gem visual node
				if inv_tab and inv_tab.has_method("_remove_item_if_exists"):
					inv_tab._remove_item_if_exists(gem_item)

				gem_item.queue_free()

			if GameLogger.ENABLED:
				print("[CharacterDisplay] ✅ Gem consumed and removed from inventory")

		return

	# CASO 2: Regular equipment item being equipped
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
	print("[CharacterDisplay] 🔍 _get_slot_at_position called with pos: %s" % pos)

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
			print("[CharacterDisplay]   → %s: NULL panel" % slot_info.name)
			continue

		var rect = Rect2(panel.global_position, panel.size)
		print("[CharacterDisplay]   → %s: pos=%s size=%s contains=%s" % [
			slot_info.name,
			panel.global_position,
			panel.size,
			rect.has_point(pos)
		])

		if rect.has_point(pos):
			print("[CharacterDisplay] ✅ Found slot: %s" % slot_info.name)
			return slot_info.name

	print("[CharacterDisplay] ❌ No slot found at position %s" % pos)
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

	# NOTE: We intentionally do NOT sync with real equipment slots here!
	# During load, the visual slots are empty until we populate them from GameState.
	# If we clear GameState based on empty slots, we lose the saved equipment.
	# The sync should only happen during GAMEPLAY when user interacts with slots,
	# not during initial load.
	# 
	# REMOVED: _get_real_equipment_from_main_tab() sync logic that was clearing equipped_items

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
# TOOLTIP SYSTEM (Using TooltipManager)
# ============================================

func _on_slot_mouse_entered(slot_panel: Panel) -> void:
	"""Show tooltip when hovering over equipment slot"""
	print("[CharacterDisplay] 🖱️ MOUSE ENTERED: %s" % slot_panel.name)  # FORCED DEBUG
	hovered_slot = slot_panel

	# Get item data from slot metadata
	if not slot_panel.has_meta("item_data"):
		# Empty slot - show generic tooltip
		print("[CharacterDisplay] → Empty slot, showing generic tooltip")  # FORCED DEBUG
		var slot_name = slot_panel.name.replace("Slot", "")
		TooltipManager.show_text_tooltip(
			"[b]%s Slot[/b]" % slot_name,
			"[color=#888888]Empty - Drag an item here to equip[/color]",
			""
		)
		return

	var item_data = slot_panel.get_meta("item_data")
	print("[CharacterDisplay] → Has item_data: %s" % item_data.get("name", "Unknown"))  # FORCED DEBUG

	# Show item tooltip if slot has equipment
	if not item_data.is_empty():
		print("[CharacterDisplay] → Showing equipment tooltip")  # FORCED DEBUG
		TooltipManager.show_equipment_tooltip(item_data)
	else:
		print("[CharacterDisplay] → item_data is empty!")  # FORCED DEBUG

func _on_slot_mouse_exited(slot_panel: Panel) -> void:
	"""Hide tooltip when leaving equipment slot"""
	print("[CharacterDisplay] 🖱️ MOUSE EXITED: %s" % slot_panel.name)  # FORCED DEBUG
	if hovered_slot == slot_panel:
		hovered_slot = null
		TooltipManager.hide_item_tooltip()

# ============================================
# UTILITY FUNCTIONS
# ============================================

func _find_inventory_tab():
	"""Find the InventoryTab node by navigating up to Main and then down to Inventory"""
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return null

	var tab_container = main.get_node_or_null("Margin/VBox/Tabs")
	if tab_container == null:
		return null

	var inventory_tab = tab_container.get_node_or_null("Inventory")
	return inventory_tab

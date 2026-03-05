extends Panel
class_name EquipmentSlot

@export var slot_type: String = "helmet"  # helmet, weapon, chest, shield, belt, boots
@export var accepted_types: Array[String] = ["helmet"]  # Tipi di item accettati

var equipped_item: Item = null
var is_readonly: bool = false  # If true, no drag & drop allowed

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Setup visual dello slot
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5)
	add_theme_stylebox_override("panel", style)

	# Connetti il segnale mouse_exited per pulire l'highlight quando il mouse esce
	mouse_exited.connect(_on_mouse_exited)

	# Connetti child_exiting_tree per rilevare quando l'item viene rimosso (draggato via)
	child_exiting_tree.connect(_on_child_exiting_tree)
	
	# CRITICAL: Connect to GameState signal to restore equipped item on load!
	# Use call_deferred to ensure GameState is ready
	call_deferred("_connect_to_gamestate_and_restore")

func _connect_to_gamestate_and_restore() -> void:
	"""Connect to GameState signals and restore equipped item if any"""
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("[EquipmentSlot] ⚠️ GameState not found")
		return
	
	# Connect to on_item_equipped signal to handle future equips
	if gs.has_signal("on_item_equipped") and not gs.on_item_equipped.is_connected(_on_gamestate_item_equipped):
		gs.on_item_equipped.connect(_on_gamestate_item_equipped)
		print("[EquipmentSlot] ✅ %s connected to on_item_equipped signal" % slot_type)

	# Connect to on_item_unequipped signal to handle remote unequips
	if gs.has_signal("on_item_unequipped") and not gs.on_item_unequipped.is_connected(_on_gamestate_item_unequipped):
		gs.on_item_unequipped.connect(_on_gamestate_item_unequipped)
		print("[EquipmentSlot] ✅ %s connected to on_item_unequipped signal" % slot_type)

	# Restore equipped item from GameState (for this specific slot)
	restore_from_gamestate()

func _on_gamestate_item_equipped(slot: String, item_data: Dictionary) -> void:
	"""Called when an item is equipped via GameState signal (e.g., on load)"""
	# Only respond to our slot type
	if slot != slot_type:
		return

	# If we already have an item with same data, skip (avoid duplicates)
	if equipped_item != null:
		print("[EquipmentSlot] %s already has equipped item, skipping signal" % slot_type)
		return

	print("[EquipmentSlot] 🔔 Received on_item_equipped for %s: %s" % [slot, item_data.get("name", "Unknown")])
	_create_equipped_item_visual(item_data)

func _on_gamestate_item_unequipped(slot: String, item_data: Dictionary) -> void:
	"""Called when an item is unequipped in GameState (from any source)"""
	# Only handle if it's our slot
	if slot != slot_type:
		return

	print("[EquipmentSlot] 🔔 %s received unequip signal for %s" % [slot_type, item_data.get("name", "Unknown")])

	# Clear our equipped item visual
	if equipped_item != null:
		equipped_item.queue_free()
		equipped_item = null
		print("[EquipmentSlot] %s cleared equipped item after remote unequip" % slot_type)

	# CRITICAL: Also clear any remaining children (e.g., labels, textures)
	for child in get_children():
		if child is Item or child is Label or child is TextureRect:
			child.queue_free()
			print("[EquipmentSlot] Cleared remaining child: %s" % child.name)

func restore_from_gamestate() -> void:
	"""Restore equipped item visual from GameState data (called on load)"""
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	
	# Check if there's an equipped item for this slot
	if not gs.equipped_items.has(slot_type):
		return
	
	var item_data = gs.equipped_items[slot_type]
	if item_data == null or item_data.is_empty():
		return
	
	# Don't recreate if already have one
	if equipped_item != null:
		print("[EquipmentSlot] %s already has item, skipping restore" % slot_type)
		return
	
	print("[EquipmentSlot] 🔄 Restoring equipped item for %s: %s" % [slot_type, item_data.get("name", "Unknown")])
	_create_equipped_item_visual(item_data)

func _create_equipped_item_visual(item_data: Dictionary) -> void:
	"""Create the visual Item node for an equipped item"""
	var item_id = item_data.get("id", item_data.get("item_id", ""))
	if item_id == "":
		print("[EquipmentSlot] ⚠️ No item_id in item_data")
		return
	
	# CRITICAL: Merge database base data with saved custom data
	# The save file may not contain all fields (icon, name, etc), so we get base data from database
	var gs = get_node_or_null("/root/GameState")
	var merged_data = item_data.duplicate(true)  # Start with saved data (has bonuses, instance_id, etc)
	
	# Get base data from database
	if gs and "data" in gs and gs.data.has("items") and gs.data.items.has(item_id):
		var base_data = gs.data.items[item_id]
		# Merge: base_data provides defaults, saved item_data overrides
		for key in base_data.keys():
			if not merged_data.has(key):
				merged_data[key] = base_data[key]
		print("[EquipmentSlot] 🔀 Merged database data with saved data for %s" % item_id)
	
	# Ensure we have required fields
	if not merged_data.has("icon"):
		print("[EquipmentSlot] ⚠️ No icon in item_data for %s" % item_id)
	
	# Determine if this is a craftable item (weapon/armor)
	var item_slot = merged_data.get("slot", "")
	var is_craftable = item_slot in ["weapon", "helmet", "chest", "belt", "boots", "shield"]
	
	# Load the appropriate scene
	var scene_path = "res://scripts/ui/CraftableItem.tscn" if is_craftable else "res://scripts/ui/Item.tscn"
	var item_scene = load(scene_path)
	if item_scene == null:
		print("[EquipmentSlot] ⚠️ Could not load item scene: %s" % scene_path)
		return
	
	var item: Item = item_scene.instantiate()
	item.item_id = item_id
	
	# Restore instance_id if present
	if merged_data.has("instance_id"):
		item.set_meta("instance_id", merged_data.instance_id)
		print("[EquipmentSlot] → Restored instance_id: %s" % merged_data.instance_id)
	
	# Store complete merged item_data in metadata
	item.set_meta("item_data", merged_data)
	
	# Setup the item (this configures texture, tooltip with bonuses, etc.)
	item.setup_item(item_id, merged_data)

	# CRITICAL FIX: Apply enhancement level if present (for particle effects)
	if merged_data.has("enhancement_level"):
		var enh_level = merged_data.enhancement_level
		if enh_level > 0 and item.has_method("set_enhancement_level"):
			item.set_enhancement_level(enh_level)
			print("[EquipmentSlot] ✨ Applied enhancement level +%d to equipped %s" % [enh_level, item_id])

	# Add to this slot
	add_child(item)
	equipped_item = item

	# Position the item in the slot
	item.position = Vector2(4, 4)
	item.size = size - Vector2(8, 8)
	item.z_index = 5

	# Log what was restored
	var bonuses_count = merged_data.get("bonuses", []).size()
	var upgrade_level = merged_data.get("upgrade_level", 0)
	var enhancement_level = merged_data.get("enhancement_level", 0)
	print("[EquipmentSlot] ✅ Created visual for %s in %s slot (bonuses: %d, upgrade: +%d, enhancement: +%d)" % [item_id, slot_type, bonuses_count, upgrade_level, enhancement_level])

func set_readonly(readonly: bool) -> void:
	"""Set slot to readonly mode (view only, no drag & drop)"""
	is_readonly = readonly
	if is_readonly:
		mouse_filter = Control.MOUSE_FILTER_PASS  # Allow hover for tooltip but no drag
		if GameLogger.ENABLED:
			print("[EquipmentSlot] %s set to READ-ONLY" % slot_type)

# ==================== DRAG & DROP BASATO SU ESEMPI ONLINE ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Controlla se possiamo accettare questo item"""
	# If readonly, reject all drops
	if is_readonly:
		return false

	if GameLogger.ENABLED:
		print("[EquipmentSlot] _can_drop_data on %s slot" % slot_type)

	# Verifica che sia un item valido
	if not _is_valid_item_data(data):
		if GameLogger.ENABLED:
			print("[EquipmentSlot] Invalid item data")
		return false

	var item: Item = data.get("item", null)
	if item == null:
		return false

	# CASO 1: Gem being dropped - check if equipped item can accept it
	var item_type = _get_item_type(item)
	if item_type == "Gem":
		if GameLogger.ENABLED:
			print("[EquipmentSlot] 🔹 Gem detected, checking if equipped item can accept it...")

		# Check if there's an equipped item
		if equipped_item == null:
			if GameLogger.ENABLED:
				print("[EquipmentSlot] ❌ No equipped item to apply gem to")
			_show_highlight(false)
			return false

		# Check if equipped item has gem support (is CraftableItem)
		if not equipped_item.has_method("_can_drop_data"):
			if GameLogger.ENABLED:
				print("[EquipmentSlot] ❌ Equipped item doesn't support gem drops")
			_show_highlight(false)
			return false

		# Forward to equipped item
		var can_accept = equipped_item._can_drop_data(at_position, data)
		if GameLogger.ENABLED:
			print("[EquipmentSlot] → Equipped item can accept gem: %s" % can_accept)

		_show_highlight(can_accept)
		return can_accept

	# CASO 2: Regular equipment item
	var is_compatible = item_type in accepted_types

	if GameLogger.ENABLED:
		print("[EquipmentSlot] Item %s (type: %s) compatible with %s slot: %s" %
			[item.item_id, item_type, slot_type, is_compatible])

	# Visual feedback
	_show_highlight(is_compatible)

	return is_compatible

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Equipaggia l'item in questo slot o applica gemma"""
	if GameLogger.ENABLED:
		print("[EquipmentSlot] _drop_data on %s slot" % slot_type)

	_clear_highlight()

	if not _is_valid_item_data(data):
		return

	var item: Item = data.get("item", null)
	if item == null:
		return

	# CASO 1: Gem being dropped - forward to equipped item
	var item_type = _get_item_type(item)
	if item_type == "Gem":
		if GameLogger.ENABLED:
			print("[EquipmentSlot] 🔹 Gem drop, forwarding to equipped item...")

		if equipped_item != null and equipped_item.has_method("_drop_data"):
			# Forward gem drop to equipped item (CraftableItem)
			equipped_item._drop_data(at_position, data)

			if GameLogger.ENABLED:
				print("[EquipmentSlot] ✅ Gem forwarded to equipped item")
		else:
			if GameLogger.ENABLED:
				print("[EquipmentSlot] ❌ Cannot forward gem - no equipped item or no gem support")

		return

	# CASO 2: Regular equipment item - equip or swap
	if equipped_item != null:
		_swap_items(item)
	else:
		_equip_item(item)

func _equip_item(item: Item) -> void:
	"""Equipaggia un item in questo slot"""
	if GameLogger.ENABLED:
		print("[EquipmentSlot] Equipping %s in %s slot" % [item.item_id, slot_type])

	# Trova l'inventario
	var inventory_tab = _find_inventory_tab()

	# CRITICAL: Disabilita auto-refresh per evitare il riordino dell'inventario
	if inventory_tab and inventory_tab.has_method("set_auto_refresh"):
		inventory_tab.set_auto_refresh(false)

	# SIMPLIFIED APPROACH (from jlucaso1/drag-drop-inventory):
	# Just move the item visually - the parent system handles the rest

	# Imposta questo item come equipaggiato
	equipped_item = item

	# Sposta l'item in questo slot (remove from old parent, add to this slot)
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)

	# Posiziona e ridimensiona l'item
	item.position = Vector2(4, 4)
	item.size = size - Vector2(8, 8)
	item.z_index = 5

	# Aggiorna GameState
	_update_gamestate()

	# Sync after visual change is complete
	if inventory_tab and inventory_tab.has_method("_sync_to_gamestate"):
		inventory_tab._sync_to_gamestate()
		if GameLogger.ENABLED:
			print("[EquipmentSlot] ✅ Synced inventory after equip")

	# Riabilita auto-refresh
	if inventory_tab and inventory_tab.has_method("set_auto_refresh"):
		inventory_tab.set_auto_refresh(true)

	# Marca il drop come riuscito
	if item.has_method("mark_drop_success"):
		item.mark_drop_success()

func _swap_items(new_item: Item) -> void:
	"""Scambia l'item corrente con quello nuovo"""
	if GameLogger.ENABLED:
		print("[EquipmentSlot] Swapping %s with %s in %s slot" %
			[equipped_item.item_id if equipped_item else "none", new_item.item_id, slot_type])
	
	# Rimuovi il nuovo item dall'inventario
	var inventory_tab = _find_inventory_tab()
	if inventory_tab:
		inventory_tab._remove_item_if_exists(new_item)
	
	# Se c'è un item equipaggiato, rimettilo nell'inventario
	if equipped_item != null:
		_unequip_current_item()
	
	# Equipaggia il nuovo item
	_equip_item(new_item)

func _unequip_current_item() -> void:
	"""Rimuove l'item attualmente equipaggiato e lo rimette nell'inventario"""
	if equipped_item == null:
		return

	if GameLogger.ENABLED:
		print("[EquipmentSlot] Unequipping %s from %s slot" % [equipped_item.item_id, slot_type])

	# Trova l'inventario
	var inventory_tab = _find_inventory_tab()
	if inventory_tab == null:
		print("[EquipmentSlot] Could not find inventory to return item!")
		return

	# CRITICAL: Disabilita auto-refresh per evitare il riordino
	if inventory_tab.has_method("set_auto_refresh"):
		inventory_tab.set_auto_refresh(false)

	# Rimuovi l'item da questo slot
	remove_child(equipped_item)

	# Cerca uno spazio libero nell'inventario
	var free_pos = inventory_tab._find_next_free_position(Vector2i(0, 0), equipped_item.item_size)
	if free_pos != Vector2i(-1, -1):
		inventory_tab.place_item(equipped_item, free_pos)
	else:
		print("[EquipmentSlot] No space in inventory for unequipped item!")
		# In caso di emergenza, distruggi l'item (o gestisci diversamente)
		equipped_item.queue_free()

	equipped_item = null
	_update_gamestate()

	# CRITICAL FIX: Sync inventory_items from UI to ensure consistency
	# After adding item back to UI, rebuild gs.inventory_items from items_at_position
	if inventory_tab and inventory_tab.has_method("_sync_to_gamestate"):
		inventory_tab._sync_to_gamestate()
		if GameLogger.ENABLED:
			print("[EquipmentSlot] ✅ Synced inventory_items from UI after unequip")

	# Riabilita auto-refresh
	if inventory_tab and inventory_tab.has_method("set_auto_refresh"):
		inventory_tab.set_auto_refresh(true)

# ==================== VISUAL FEEDBACK ====================

func _show_highlight(is_valid: bool) -> void:
	"""Mostra highlight durante il drag"""
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		if is_valid:
			style.bg_color = Color(0.2, 1.0, 0.2, 0.4)
			style.border_color = Color(0.0, 1.0, 0.0, 0.8)
		else:
			style.bg_color = Color(1.0, 0.2, 0.2, 0.4)
			style.border_color = Color(1.0, 0.0, 0.0, 0.8)

func _clear_highlight() -> void:
	"""Rimuove highlight"""
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
		style.border_color = Color(0.4, 0.4, 0.5)

# ==================== UTILITY FUNCTIONS ====================

func _is_valid_item_data(data: Variant) -> bool:
	"""Verifica che i dati del drag siano validi"""
	if typeof(data) != TYPE_DICTIONARY:
		return false
	
	var dict: Dictionary = data
	return dict.has("type") and dict["type"] == "inventory_item" and dict.has("item")

func _get_item_type(item: Item) -> String:
	"""Ottiene il tipo di un item con logging dettagliato"""
	# GODOT 4 FIX: Accedi direttamente all'autoload, non usare Engine.get_singleton()
	if not has_node("/root/GameState"):
		if GameLogger.ENABLED:
			print("[EquipmentSlot] ERROR: No GameState autoload!")
		return "unknown"

	var gs = get_node("/root/GameState")
	if not gs:
		if GameLogger.ENABLED:
			print("[EquipmentSlot] ERROR: GameState is null!")
		return "unknown"

	if not "data" in gs:
		if GameLogger.ENABLED:
			print("[EquipmentSlot] ERROR: GameState has no 'data' property!")
		return "unknown"

	if not gs.data.has("items"):
		if GameLogger.ENABLED:
			print("[EquipmentSlot] ERROR: GameState.data has no 'items'!")
		return "unknown"

	var item_data = gs.data.items.get(item.item_id, {})
	if item_data.is_empty():
		if GameLogger.ENABLED:
			print("[EquipmentSlot] WARNING: No data found for item '%s'" % item.item_id)
		return "unknown"

	var item_type = item_data.get("slot", "unknown")
	if GameLogger.ENABLED:
		print("[EquipmentSlot] Item '%s' has type/slot: '%s'" % [item.item_id, item_type])

	return item_type

func _find_inventory_tab():
	"""Trova l'InventoryTab nella scena"""
	var current = self
	while current != null:
		if current.get_script() != null and "InventoryTab" in str(current.get_script().resource_path):
			return current
		current = current.get_parent()
	
	# Se non trovato risalendo, cerca nella scena
	var root = get_tree().current_scene
	return _search_for_inventory_tab(root)

func _search_for_inventory_tab(node: Node):
	"""Ricerca ricorsiva dell'InventoryTab"""
	if node.get_script() != null:
		var script_path = node.get_script().resource_path
		if script_path.find("InventoryTab") != -1:
			return node
	
	for child in node.get_children():
		var result = _search_for_inventory_tab(child)
		if result != null:
			return result
	
	return null

func _update_gamestate() -> void:
	"""Aggiorna il GameState con l'item equipaggiato"""
	# GODOT 4 FIX: Accedi direttamente all'autoload
	if not has_node("/root/GameState"):
		print("[EquipmentSlot] ⚠️ GameState not found")
		return

	var gs = get_node("/root/GameState")
	if not gs:
		print("[EquipmentSlot] ⚠️ GameState is null")
		return

	# Get item data from the Item itself (includes bonuses!)
	var item_data = null
	if equipped_item != null:
		# CRITICAL: Get complete data from Item metadata (includes bonuses)
		if equipped_item.has_meta("item_data"):
			item_data = equipped_item.get_meta("item_data")
			if GameLogger.ENABLED:
				print("[EquipmentSlot] ✅ Got item_data from Item metadata (has bonuses: %s)" % item_data.has("bonuses"))
				if item_data.has("bonuses"):
					print("[EquipmentSlot]   Bonuses: ", item_data.bonuses)

			# CRITICAL FIX: Add enhancement_level from Item node (for particle effects)
			if equipped_item.has_method("get_enhancement_level"):
				var enh_level = equipped_item.get_enhancement_level()
				if enh_level > 0:
					item_data["enhancement_level"] = enh_level
					if GameLogger.ENABLED:
						print("[EquipmentSlot] ✨ Added enhancement_level +%d to equipped item data" % enh_level)
		# Fallback: get base data from database (no bonuses)
		elif "data" in gs and gs.data.has("items"):
			item_data = gs.data.items.get(equipped_item.item_id, {})
			if GameLogger.ENABLED:
				print("[EquipmentSlot] ⚠️ Using fallback database data (no bonuses)")

	if equipped_item != null and item_data != null and not item_data.is_empty():
		print("[EquipmentSlot] Updating GameState for slot %s with item %s" % [slot_type, equipped_item.item_id])

		# CRITICAL FIX: Include instance_id for unique identification during load
		# This prevents the bug where ALL items with same item_id get skipped on reload
		if equipped_item.has_meta("instance_id"):
			item_data["instance_id"] = equipped_item.get_meta("instance_id")
			print("[EquipmentSlot] ✅ Added instance_id to equipped item: %s" % item_data["instance_id"])
		else:
			# Generate new instance_id if missing (shouldn't happen, but safety fallback)
			var new_instance_id = "%s_%d_%d" % [equipped_item.item_id, Time.get_ticks_msec(), randi()]
			item_data["instance_id"] = new_instance_id
			equipped_item.set_meta("instance_id", new_instance_id)
			print("[EquipmentSlot] ⚠️ Generated new instance_id: %s" % new_instance_id)

		# SIMPLIFIED: Just update equipped_items
		# inventory_items will be synced by _sync_to_gamestate() after this
		gs.equipped_items[slot_type] = item_data
		print("[EquipmentSlot] ✅ Updated equipped_items[%s]" % slot_type)

		# Apply stats if present
		if item_data.has("stats") and "character_stats" in gs and gs.character_stats:
			gs.character_stats.apply_equipment_stats(item_data.stats)
			print("[EquipmentSlot] Applied stats from %s" % item_data.get("name", equipped_item.item_id))

		# Emit signal manually for CharacterDisplay to update
		print("[EquipmentSlot] 📢 Manually emitting on_item_equipped for slot: %s, item: %s" % [slot_type, item_data.get("name", "unknown")])
		gs.on_item_equipped.emit(slot_type, item_data)
		gs.on_stats_changed.emit()
	else:
		print("[EquipmentSlot] Clearing slot %s" % slot_type)

		# Get item_data before clearing for unequip signal
		if gs.equipped_items.has(slot_type) and gs.equipped_items[slot_type] != null:
			item_data = gs.equipped_items[slot_type]

		# SIMPLIFIED: Don't manually add to inventory_items
		# _sync_to_gamestate() will rebuild inventory_items from UI after this

		# Remove stats if item was equipped
		if item_data and item_data.has("stats") and "character_stats" in gs and gs.character_stats:
			gs.character_stats.remove_equipment_stats(item_data.stats)

		# Clear from GameState
		gs.equipped_items[slot_type] = null

		# Emit unequip signal
		if item_data:
			gs.on_item_unequipped.emit(slot_type, item_data)

		gs.on_stats_changed.emit()

# ==================== CLEANUP ====================

func _on_mouse_exited() -> void:
	"""Pulisce l'highlight quando il mouse esce dallo slot durante il drag"""
	_clear_highlight()

func _on_child_exiting_tree(node: Node) -> void:
	"""Chiamato quando un child viene rimosso (item draggato via)"""
	# Check if the node being removed is our equipped item
	if node == equipped_item:
		if GameLogger.ENABLED:
			print("[EquipmentSlot] Item %s is being removed from %s slot (dragged away)" % [equipped_item.item_id if equipped_item else "unknown", slot_type])

		# Defer the update to after the node is fully removed
		call_deferred("_handle_item_removed")

func _handle_item_removed() -> void:
	"""Gestisce la rimozione dell'item (chiamato in deferred)"""
	# Check if equipped_item is no longer a child of this slot
	if equipped_item != null and equipped_item.get_parent() != self:
		if GameLogger.ENABLED:
			print("[EquipmentSlot] Item confirmed removed from %s slot (parent changed), updating GameState" % slot_type)

		equipped_item = null
		_update_gamestate()  # This will emit on_item_unequipped
	elif equipped_item != null:
		if GameLogger.ENABLED:
			print("[EquipmentSlot] Item %s still in %s slot, not removed" % [equipped_item.item_id, slot_type])

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_highlight()

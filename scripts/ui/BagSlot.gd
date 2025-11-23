extends Panel
class_name BagSlot

signal bag_equipped(slot_index: int, bag_slots: int)
signal bag_removed(slot_index: int)

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Slot Configuration")
@export var slot_index: int = 0  # 0-4 (5 total slots)
@export var is_locked: bool = false  # True for starter bag slot (non-removable)

@export_group("Visual Style")
@export var locked_bg_color: Color = Color(0.4, 0.3, 0.2, 0.9)  # Brown leather (starter bag)
@export var unlocked_bg_color: Color = Color(0.3, 0.2, 0.15, 0.8)  # Darker brown (empty slot)
@export var border_width: int = 2
@export var border_color: Color = Color(0.7, 0.6, 0.3, 0.9)  # Gold border

@export_group("Drag Feedback")
@export var valid_drop_bg: Color = Color(0.2, 1.0, 0.2, 0.4)  # Green
@export var valid_drop_border: Color = Color(0.0, 1.0, 0.0, 0.8)
@export var invalid_drop_bg: Color = Color(1.0, 0.2, 0.2, 0.4)  # Red
@export var invalid_drop_border: Color = Color(1.0, 0.0, 0.0, 0.8)

@export_group("Error Message")
@export var error_text_color: Color = Color(1, 0.3, 0.3)  # Red
@export var error_outline_color: Color = Color.BLACK
@export var error_font_size: int = 14
@export var error_outline_size: int = 2

# ==================== INTERNAL VARIABLES ====================
var equipped_bag: Item = null
var inventory_tab: InventoryTab = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Setup visual dello slot (usa valori dall'Inspector)
	var style = StyleBoxFlat.new()
	if is_locked:
		style.bg_color = locked_bg_color
	else:
		style.bg_color = unlocked_bg_color

	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	add_theme_stylebox_override("panel", style)

	mouse_exited.connect(_on_mouse_exited)
	child_exiting_tree.connect(_on_child_exiting_tree)

# ==================== DRAG & DROP ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Controlla se possiamo accettare questa bag"""
	# Locked slot non accetta drop
	if is_locked:
		if GameLogger.ENABLED:
			print("[BagSlot] Slot %d is LOCKED (starter bag)" % slot_index)
		return false

	if GameLogger.ENABLED:
		print("[BagSlot] _can_drop_data on slot %d" % slot_index)

	# Verifica che sia un item valido
	if not _is_valid_item_data(data):
		if GameLogger.ENABLED:
			print("[BagSlot] Invalid item data")
		return false

	var item: Item = data.get("item", null)
	if item == null:
		return false

	# Verifica che sia una bag
	var is_bag = _is_bag(item)

	if GameLogger.ENABLED:
		print("[BagSlot] Item %s is bag: %s" % [item.item_id, is_bag])

	# Visual feedback
	_show_highlight(is_bag)

	return is_bag

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Equipaggia la bag in questo slot"""
	if GameLogger.ENABLED:
		print("[BagSlot] _drop_data on slot %d" % slot_index)

	_clear_highlight()

	if not _is_valid_item_data(data):
		return

	var item: Item = data.get("item", null)
	if item == null:
		return

	# Se c'è già una bag equipaggiata, scambiala
	if equipped_bag != null:
		_swap_bags(item)
	else:
		_equip_bag(item)

func _equip_bag(bag: Item) -> void:
	"""Equipaggia una bag in questo slot"""
	if GameLogger.ENABLED:
		print("[BagSlot] Equipping bag %s in slot %d" % [bag.item_id, slot_index])

	# CRITICAL: Rimuovi bag dall'inventario (sia visivamente che dal GameState)
	if inventory_tab:
		# IMPORTANT: Get position BEFORE removing visually!
		var bag_pos = inventory_tab.get_item_position(bag)
		print("[BagSlot] Bag position before removal: %s" % bag_pos)

		# Rimuovi visivamente
		inventory_tab._remove_item_if_exists(bag)

		# Rimuovi anche dal GameState.inventory_items per evitare duplicati
		if has_node("/root/GameState"):
			var gs = get_node("/root/GameState")
			if gs and "inventory_items" in gs:
				var removed = false
				for i in range(gs.inventory_items.size() - 1, -1, -1):
					var inv_item = gs.inventory_items[i]
					# Match by item_id - bags are unique, so we can remove any with same ID
					if inv_item.get("item_id") == bag.item_id:
						gs.inventory_items.remove_at(i)
						print("[BagSlot] Removed bag %s from GameState.inventory_items" % bag.item_id)
						removed = true
						break
				if not removed:
					print("[BagSlot] WARNING: Bag %s not found in GameState.inventory_items!" % bag.item_id)

	# Imposta questa bag come equipaggiata
	equipped_bag = bag

	# Sposta la bag in questo slot
	if bag.get_parent():
		bag.get_parent().remove_child(bag)
	add_child(bag)

	# Posiziona e ridimensiona la bag
	bag.position = Vector2(4, 4)
	bag.size = size - Vector2(8, 8)
	bag.z_index = 5

	# CRITICAL: Marca il drop come riuscito PRIMA di emettere il segnale
	# Questo previene che l'item torni alla posizione originale
	if bag.has_method("mark_drop_success"):
		bag.mark_drop_success()

	# Ottieni il numero di slot della bag
	var bag_slots = _get_bag_slots(bag)

	# Emetti segnale per espandere l'inventario
	bag_equipped.emit(slot_index, bag_slots)

func _swap_bags(new_bag: Item) -> void:
	"""Scambia la bag corrente con quella nuova"""
	if GameLogger.ENABLED:
		print("[BagSlot] Swapping bags in slot %d" % slot_index)

	# Rimuovi la nuova bag dall'inventario
	if inventory_tab:
		inventory_tab._remove_item_if_exists(new_bag)

	# Rimetti la bag vecchia nell'inventario
	if equipped_bag != null:
		_unequip_current_bag()

	# Equipaggia la nuova bag
	_equip_bag(new_bag)

func _unequip_current_bag() -> void:
	"""Rimuove la bag attualmente equipaggiata"""
	if equipped_bag == null:
		return

	if GameLogger.ENABLED:
		print("[BagSlot] Unequipping bag from slot %d" % slot_index)

	# Controlla se c'è spazio nell'inventario per tutti gli item
	if not _can_unequip_bag():
		_show_error_message("Not enough space! Free up some inventory slots first.")
		return

	# Rimuovi la bag da questo slot
	remove_child(equipped_bag)

	# Cerca uno spazio libero nell'inventario
	if inventory_tab:
		var free_pos = inventory_tab._find_next_free_position(Vector2i(0, 0), equipped_bag.item_size)
		if free_pos != Vector2i(-1, -1):
			inventory_tab.place_item(equipped_bag, free_pos)
		else:
			print("[BagSlot] No space in inventory for bag!")
			# Tieni la bag nello slot se non c'è spazio
			add_child(equipped_bag)
			return

	# Ottieni il numero di slot prima di rimuovere
	var bag_slots = _get_bag_slots(equipped_bag)

	equipped_bag = null

	# Emetti segnale per ridurre l'inventario
	bag_removed.emit(slot_index)

func _can_unequip_bag() -> bool:
	"""Controlla se possiamo rimuovere questa bag (c'è abbastanza spazio per gli item?)"""
	if inventory_tab == null:
		return false

	# Use inventory_tab's check to see if all items can fit in reduced space
	if inventory_tab.has_method("can_remove_bag"):
		return inventory_tab.can_remove_bag(slot_index)

	return true

func _is_bag(item: Item) -> bool:
	"""Verifica se un item è una bag"""
	if not has_node("/root/GameState"):
		return false

	var gs = get_node("/root/GameState")
	if not gs or not "data" in gs:
		return false

	var item_data = gs.data.items.get(item.item_id, {})
	var item_type = item_data.get("type", "")

	return item_type == "Bag"

func _get_bag_slots(bag: Item) -> int:
	"""Ottiene il numero di slot che la bag fornisce"""
	if not has_node("/root/GameState"):
		return 0

	var gs = get_node("/root/GameState")
	if not gs or not "data" in gs:
		return 0

	var item_data = gs.data.items.get(bag.item_id, {})
	return item_data.get("bag_slots", 0)

# ==================== VISUAL FEEDBACK ====================

func _show_highlight(is_valid: bool) -> void:
	"""Mostra highlight durante il drag"""
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		if is_valid:
			style.bg_color = valid_drop_bg
			style.border_color = valid_drop_border
		else:
			style.bg_color = invalid_drop_bg
			style.border_color = invalid_drop_border

func _clear_highlight() -> void:
	"""Rimuove highlight"""
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		if is_locked:
			style.bg_color = locked_bg_color
		else:
			style.bg_color = unlocked_bg_color
		style.border_color = border_color

func _show_error_message(message: String) -> void:
	"""Mostra un messaggio di errore visivo al player"""
	print("[BagSlot] ERROR: %s" % message)

	# Create floating error label (usa valori dall'Inspector)
	var error_label = Label.new()
	error_label.text = message
	error_label.add_theme_font_size_override("font_size", error_font_size)
	error_label.add_theme_color_override("font_color", error_text_color)
	error_label.add_theme_color_override("font_outline_color", error_outline_color)
	error_label.add_theme_constant_override("outline_size", error_outline_size)

	# Add to scene root so it's always visible
	var root = get_tree().root
	root.add_child(error_label)

	# Position near mouse
	error_label.global_position = get_global_mouse_position() + Vector2(10, -30)
	error_label.z_index = 100

	# Animate and remove after 2 seconds
	var tween = create_tween()
	tween.tween_property(error_label, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.tween_property(error_label, "global_position:y", error_label.global_position.y - 30, 2.0).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(error_label.queue_free)

# ==================== UTILITY FUNCTIONS ====================

func _is_valid_item_data(data: Variant) -> bool:
	"""Verifica che i dati del drag siano validi"""
	if typeof(data) != TYPE_DICTIONARY:
		return false

	var dict: Dictionary = data
	return dict.has("type") and dict["type"] == "inventory_item" and dict.has("item")

# ==================== CLEANUP ====================

func _on_mouse_exited() -> void:
	"""Pulisce l'highlight quando il mouse esce"""
	_clear_highlight()

func _on_child_exiting_tree(node: Node) -> void:
	"""Chiamato quando un child viene rimosso (bag draggata via)"""
	print("\n[BagSlot] ========== _on_child_exiting_tree START (slot %d) ==========" % slot_index)
	print("[BagSlot]   Node exiting: %s (type: %s)" % [node.name if node else "null", node.get_class() if node else "null"])
	print("[BagSlot]   is_locked: %s" % is_locked)
	print("[BagSlot]   equipped_bag: %s" % (equipped_bag.item_id if equipped_bag else "null"))
	print("[BagSlot]   node == equipped_bag: %s" % (node == equipped_bag))

	# Locked slot non può avere items rimossi
	if is_locked:
		print("[BagSlot]   SKIPPING: Slot is locked")
		return

	if node == equipped_bag:
		print("[BagSlot]   ✅ Node is equipped bag! Calling deferred _handle_bag_removed")
		call_deferred("_handle_bag_removed")
	else:
		print("[BagSlot]   SKIPPING: Node is not the equipped bag")

	print("[BagSlot] ========== _on_child_exiting_tree END ==========\n")

func _handle_bag_removed() -> void:
	"""Gestisce la rimozione della bag (chiamato in deferred)"""
	print("\n[BagSlot] ========== _handle_bag_removed START (slot %d) ==========" % slot_index)
	print("[BagSlot]   equipped_bag: %s" % (equipped_bag.item_id if equipped_bag else "null"))
	print("[BagSlot]   equipped_bag != null: %s" % (equipped_bag != null))

	if equipped_bag != null:
		var parent = equipped_bag.get_parent()
		print("[BagSlot]   equipped_bag.get_parent(): %s (type: %s)" % [parent.name if parent else "null", parent.get_class() if parent else "null"])
		print("[BagSlot]   self: %s" % name)
		print("[BagSlot]   equipped_bag.get_parent() != self: %s" % (parent != self))

	if equipped_bag != null and equipped_bag.get_parent() != self:
		print("[BagSlot] === BAG BEING DRAGGED AWAY from slot %d ===" % slot_index)

		# CRITICAL: Controlla se possiamo rimuovere questa bag
		if inventory_tab and inventory_tab.has_method("can_remove_bag"):
			var can_remove = inventory_tab.can_remove_bag(slot_index)
			print("[BagSlot] can_remove_bag(%d) = %s" % [slot_index, can_remove])

			if not can_remove:
				print("[BagSlot] ❌ CANNOT REMOVE BAG - not enough space! Returning bag to slot...")

				# CRITICAL: Rimuovi la bag dall'inventory (items_at_position) se è stata aggiunta
				if inventory_tab and inventory_tab.has_method("_remove_item_if_exists"):
					inventory_tab._remove_item_if_exists(equipped_bag)
					print("[BagSlot] Removed bag from inventory items_at_position")

				# Rimetti la bag nel slot
				if equipped_bag.get_parent():
					equipped_bag.get_parent().remove_child(equipped_bag)
				add_child(equipped_bag)
				equipped_bag.position = Vector2(4, 4)
				equipped_bag.size = size - Vector2(8, 8)

				_show_error_message("Cannot remove bag: not enough space to redistribute items!")
				return

		print("[BagSlot] ✅ Can remove bag, proceeding...")
		var bag_slots = _get_bag_slots(equipped_bag)
		equipped_bag = null

		# Emetti segnale per ridurre l'inventario
		print("[BagSlot] Emitting bag_removed signal for slot %d" % slot_index)
		bag_removed.emit(slot_index)
	else:
		print("[BagSlot] ❌ CONDITION FAILED - bag removal check skipped!")
		if equipped_bag == null:
			print("[BagSlot]   Reason: equipped_bag is null")
		elif equipped_bag.get_parent() == self:
			print("[BagSlot]   Reason: bag parent is still self (not moved yet)")

	print("[BagSlot] ========== _handle_bag_removed END ==========\n")

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_highlight()

# ==================== PUBLIC API ====================

func equip_starter_bag(bag: Item) -> void:
	"""Equipaggia la starter bag (chiamato programmaticamente, non via drag&drop)"""
	print("[BagSlot] === equip_starter_bag() START === slot_index=%d, is_locked=%s" %
		[slot_index, is_locked])

	if not is_locked:
		push_warning("[BagSlot] equip_starter_bag called on non-locked slot!")
		return

	equipped_bag = bag

	# Aggiungi come child
	add_child(bag)
	bag.position = Vector2(4, 4)
	bag.size = size - Vector2(8, 8)
	bag.z_index = 5

	# Emetti segnale
	var bag_slots = _get_bag_slots(bag)
	print("[BagSlot] About to emit bag_equipped signal: slot_index=%d, bag_slots=%d" %
		[slot_index, bag_slots])
	bag_equipped.emit(slot_index, bag_slots)
	print("[BagSlot] Signal emitted successfully")

	print("[BagSlot] Starter bag equipped in slot %d (%d slots)" % [slot_index, bag_slots])

extends Panel
class_name BagSlot

signal bag_equipped(slot_index: int, bag_slots: int)
signal bag_removed(slot_index: int)

@export var slot_index: int = 0  # 0-4 (5 total slots)
@export var is_locked: bool = false  # True for starter bag slot (non-removable)

var equipped_bag: Item = null
var inventory_tab: InventoryTab = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Setup visual dello slot - colore marrone/pelle per distinguerlo dall'inventario
	var style = StyleBoxFlat.new()
	if is_locked:
		# Locked slot (starter bag) - gold/brown color
		style.bg_color = Color(0.4, 0.3, 0.2, 0.9)  # Brown leather look
	else:
		# Empty bag slot - darker brown
		style.bg_color = Color(0.3, 0.2, 0.15, 0.8)

	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	# Gold border for bag slots
	style.border_color = Color(0.7, 0.6, 0.3, 0.9)
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
			style.bg_color = Color(0.2, 1.0, 0.2, 0.4)
			style.border_color = Color(0.0, 1.0, 0.0, 0.8)
		else:
			style.bg_color = Color(1.0, 0.2, 0.2, 0.4)
			style.border_color = Color(1.0, 0.0, 0.0, 0.8)

func _clear_highlight() -> void:
	"""Rimuove highlight"""
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		if is_locked:
			style.bg_color = Color(0.4, 0.3, 0.2, 0.9)  # Brown leather
		else:
			style.bg_color = Color(0.3, 0.2, 0.15, 0.8)  # Darker brown
		style.border_color = Color(0.7, 0.6, 0.3, 0.9)  # Gold border

func _show_error_message(message: String) -> void:
	"""Mostra un messaggio di errore visivo al player"""
	print("[BagSlot] ERROR: %s" % message)

	# Create floating error label
	var error_label = Label.new()
	error_label.text = message
	error_label.add_theme_font_size_override("font_size", 14)
	error_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))  # Red
	error_label.add_theme_color_override("font_outline_color", Color.BLACK)
	error_label.add_theme_constant_override("outline_size", 2)

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
	# Locked slot non può avere items rimossi
	if is_locked:
		return

	if node == equipped_bag:
		if GameLogger.ENABLED:
			print("[BagSlot] Bag being removed from slot %d" % slot_index)
		call_deferred("_handle_bag_removed")

func _handle_bag_removed() -> void:
	"""Gestisce la rimozione della bag (chiamato in deferred)"""
	if equipped_bag != null and equipped_bag.get_parent() != self:
		if GameLogger.ENABLED:
			print("[BagSlot] Bag confirmed removed from slot %d" % slot_index)

		var bag_slots = _get_bag_slots(equipped_bag)
		equipped_bag = null

		# Emetti segnale per ridurre l'inventario
		bag_removed.emit(slot_index)

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

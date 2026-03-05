# File: res://scripts/ui/TrashBin.gd
# Cestino per buttare gli item dall'inventario

extends Control
class_name TrashBin

var background: Panel = null
var label: Label = null

var is_hovering: bool = false

func _ready() -> void:
	# IMPORTANT: MOUSE_FILTER_STOP to intercept drops before they reach slots
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Create visual elements programmatically
	_create_visuals()

	# Size is set by parent (InventoryTab)

func _create_visuals() -> void:
	"""Creates the visual elements for the trash bin"""
	# Create background Panel
	background = Panel.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style the background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.2, 0.2, 0.9)  # Dark red background
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.8, 0.3, 0.3, 1.0)  # Light red border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	background.add_theme_stylebox_override("panel", style)

	add_child(background)

	# Create label
	label = Label.new()
	label.name = "Label"
	label.text = "🗑️  DRAG ITEMS HERE TO DELETE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)

	add_child(label)

	if GameLogger.ENABLED:
		print("[TrashBin] Visual elements created")

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Accetta qualsiasi item dall'inventario"""
	if typeof(data) != TYPE_DICTIONARY:
		return false

	# Accetta solo inventory items
	if data.get("type", "") != "inventory_item":
		return false

	# Mostra feedback visivo
	if not is_hovering:
		is_hovering = true
		modulate = Color(1.0, 0.5, 0.5)  # Rosso chiaro
		if GameLogger.ENABLED:
			print("[TrashBin] Item hovering over trash")

	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Elimina l'item droppato"""
	print("[TrashBin] 🗑️ _drop_data called")
	is_hovering = false
	modulate = Color.WHITE

	if typeof(data) != TYPE_DICTIONARY:
		print("[TrashBin] ❌ Invalid data type")
		return

	var item = data.get("item", null)
	var item_id = data.get("item_id", "")

	if item == null or item_id == "":
		print("[TrashBin] ❌ Invalid drop data - item=%s, item_id=%s" % [item, item_id])
		return

	print("[TrashBin] 🗑️ Deleting item: %s (instance: %s)" % [item_id, item.get_meta("instance_id", "none") if item else "none"])

	# CRITICAL: Mark item as being deleted BEFORE queue_free so it doesn't revert position
	if is_instance_valid(item):
		item.set_meta("being_deleted", true)
		if GameLogger.ENABLED:
			print("[TrashBin] Marked item as being_deleted")

	# CRITICAL: Rimuovi l'item dall'InventoryTab PRIMA per liberare lo slot
	print("[TrashBin] 🔍 Finding InventoryTab...")
	var inventory_tab = _find_inventory_tab()
	if inventory_tab and is_instance_valid(item):
		print("[TrashBin] ✅ InventoryTab found: %s" % inventory_tab.name)
		if inventory_tab.has_method("_remove_item_if_exists"):
			print("[TrashBin] 📍 Calling _remove_item_if_exists...")
			inventory_tab._remove_item_if_exists(item)
			print("[TrashBin] ✅ Item removed from inventory grid")

		# CRITICAL FIX: Sincronizza con GameState per aggiornare inventory_items
		if inventory_tab.has_method("_sync_to_gamestate"):
			print("[TrashBin] 🔄 Calling _sync_to_gamestate...")
			inventory_tab._sync_to_gamestate()
			print("[TrashBin] ✅ Synced inventory to GameState")
	else:
		print("[TrashBin] ❌ InventoryTab not found or item invalid!")

	# CRITICAL FIX: Restore mouse filters BEFORE freeing the item!
	# DON'T call _restore_mouse_filter() on the item being deleted - it won't work!
	# Instead, manually restore ALL items in the inventory directly!
	print("[TrashBin] 🔧 Manually restoring mouse filters on all inventory items...")
	if inventory_tab:
		var items_layer = inventory_tab.get_node_or_null("InvSplit/Left/InventoryScroll/InventoryContainer/ItemsLayer")
		if not items_layer:
			items_layer = inventory_tab.get_node_or_null("InvSplit/Left/ItemsLayer")

		if items_layer:
			var restored_count = 0
			for child in items_layer.get_children():
				if child != item and child is Control:  # Skip the item being deleted
					child.mouse_filter = Control.MOUSE_FILTER_PASS
					restored_count += 1
			print("[TrashBin] ✅ Restored mouse_filter on %d items" % restored_count)
		else:
			print("[TrashBin] ❌ ItemsLayer not found!")
	else:
		print("[TrashBin] ❌ InventoryTab not found!")

	# CRITICAL FIX: Hide item immediately but free it AFTER the next frame
	# This allows Godot's drag system to completely finish before the item is destroyed
	if is_instance_valid(item):
		print("[TrashBin] 👻 Hiding item immediately...")
		item.hide()  # Hide immediately so it disappears from view
		print("[TrashBin] ⏳ Waiting for next frame before freeing...")
		# Use a timer to free after next frame instead of call_deferred
		# This ensures drag system has time to complete
		_free_item_after_frame(item)

	# Mostra feedback
	print("[TrashBin] 🎨 Showing delete feedback...")
	_show_delete_feedback()
	print("[TrashBin] ✅ Delete operation complete!")

func _find_inventory_tab() -> Node:
	"""Trova l'InventoryTab parent"""
	var current = get_parent()
	if GameLogger.ENABLED:
		print("[TrashBin] Searching for InventoryTab, starting from: %s" % (current.name if current else "null"))

	while current:
		if GameLogger.ENABLED:
			print("[TrashBin]   Checking: %s (class: %s)" % [current.name, current.get_class()])

		# Check by name or if it has the method we need
		if current.name.contains("InventoryTab") or current.has_method("_remove_item_if_exists"):
			if GameLogger.ENABLED:
				print("[TrashBin]   ✅ Found InventoryTab: %s" % current.name)
			return current

		current = current.get_parent()

	if GameLogger.ENABLED:
		print("[TrashBin]   ❌ InventoryTab not found!")
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Reset visual quando il drag finisce
		is_hovering = false
		modulate = Color.WHITE

func _free_item_after_frame(item: Node) -> void:
	"""Free an item after waiting for the next frame to allow drag to complete"""
	print("[TrashBin] ⏱️ Waiting for next frame before freeing item...")
	await get_tree().process_frame
	if is_instance_valid(item):
		print("[TrashBin] 🗑️ Freeing item now...")
		item.queue_free()
		print("[TrashBin] ✅ Item freed after frame delay")
	else:
		print("[TrashBin] ⚠️ Item already freed")

func _show_delete_feedback() -> void:
	"""Mostra un feedback visivo quando un item viene cancellato"""
	# Animazione semplice: flash rosso
	modulate = Color(1.5, 0.3, 0.3)

	# Torna normale dopo 0.3 secondi
	await get_tree().create_timer(0.3).timeout
	modulate = Color.WHITE

	if GameLogger.ENABLED:
		print("[TrashBin] Item deleted!")

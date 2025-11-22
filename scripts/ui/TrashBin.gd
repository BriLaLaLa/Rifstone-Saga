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
	is_hovering = false
	modulate = Color.WHITE

	if typeof(data) != TYPE_DICTIONARY:
		return

	var item = data.get("item", null)
	var item_id = data.get("item_id", "")

	if item == null or item_id == "":
		if GameLogger.ENABLED:
			print("[TrashBin] Invalid drop data")
		return

	if GameLogger.ENABLED:
		print("[TrashBin] Deleting item: %s" % item_id)

	# CRITICAL: Mark item as being deleted BEFORE queue_free so it doesn't revert position
	if is_instance_valid(item):
		item.set_meta("being_deleted", true)
		if GameLogger.ENABLED:
			print("[TrashBin] Marked item as being_deleted")

	# CRITICAL: Rimuovi l'item dall'InventoryTab PRIMA per liberare lo slot
	var inventory_tab = _find_inventory_tab()
	if inventory_tab and is_instance_valid(item):
		if inventory_tab.has_method("_remove_item_if_exists"):
			inventory_tab._remove_item_if_exists(item)
			if GameLogger.ENABLED:
				print("[TrashBin] Item removed from inventory grid")

		# CRITICAL FIX: Sincronizza con GameState per aggiornare inventory_items
		if inventory_tab.has_method("_sync_to_gamestate"):
			inventory_tab._sync_to_gamestate()
			if GameLogger.ENABLED:
				print("[TrashBin] Synced inventory to GameState")

	# Rimuovi l'item dalla scena
	if is_instance_valid(item):
		item.queue_free()

	# Mostra feedback
	_show_delete_feedback()

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

func _show_delete_feedback() -> void:
	"""Mostra un feedback visivo quando un item viene cancellato"""
	# Animazione semplice: flash rosso
	modulate = Color(1.5, 0.3, 0.3)

	# Torna normale dopo 0.3 secondi
	await get_tree().create_timer(0.3).timeout
	modulate = Color.WHITE

	if GameLogger.ENABLED:
		print("[TrashBin] Item deleted!")

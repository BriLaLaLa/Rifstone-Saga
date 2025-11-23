extends Panel
class_name InventorySlot

# const LOG removed - using GameLogger

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Visual Style")
@export var bg_color: Color = Color(0.2, 0.2, 0.3, 0.8)
@export var border_width: int = 1
@export var border_color: Color = Color(0.4, 0.4, 0.5)

@export_group("Hover Effect")
@export var hover_brightness: float = 1.1
@export var hover_tint: Color = Color(1.1, 1.1, 1.2)

@export_group("Locked State")
@export var locked_tint: Color = Color(0.9, 0.9, 1.0)

# ==================== INTERNAL VARIABLES ====================
var slot_pos: Vector2i = Vector2i(0, 0)
var inventory_tab: InventoryTab = null
var locked_to: Item = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Stile base dello slot (usa valori dall'Inspector)
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	add_theme_stylebox_override("panel", style)
	
	if GameLogger.ENABLED:
		print("[InventorySlot] Ready at pos: %s" % slot_pos)

# ==================== SISTEMA NATIVO DI DRAG & DROP ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Chiamato da Godot quando un item viene draggato sopra questo slot"""
	print("[InventorySlot] _can_drop_data called at slot %s" % slot_pos)
	
	if not _is_valid_item_data(data):
		print("[InventorySlot] Invalid item data")
		return false
	
	if inventory_tab == null:
		if GameLogger.ENABLED:
			print("[InventorySlot] No inventory_tab reference")
		return false
	
	var item: Item = data.get("item", null)
	if item == null:
		print("[InventorySlot] No item in data")
		return false
	
	var hotspot: Vector2 = data.get("hotspot", Vector2.ZERO)
	
	# Calcola la posizione top-left dove l'item verrebbe piazzato
	var tl: Vector2i = inventory_tab.compute_top_left_from_hotspot(self, item, hotspot)
	
	# Valida il posizionamento
	var is_valid: bool = inventory_tab.validate_item_placement(item, tl)
	
	# Mostra l'anteprima nell'highlight layer
	inventory_tab.render_highlight_preview(item, tl, is_valid)
	
	if GameLogger.ENABLED:
		print("[InventorySlot] Can drop? slot=%s, tl=%s, valid=%s, item=%s" % 
			[slot_pos, tl, is_valid, item.item_id])
	
	return is_valid

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Chiamato da Godot quando l'item viene rilasciato su questo slot"""
	print("[InventorySlot] _drop_data called on slot %s" % slot_pos)

	# Pulisci l'highlight
	if inventory_tab:
		inventory_tab.clear_highlight()

	if not _is_valid_item_data(data):
		return

	var item: Item = data.get("item", null)
	if item == null:
		return

	var hotspot: Vector2 = data.get("hotspot", Vector2.ZERO)
	var tl: Vector2i = inventory_tab.compute_top_left_from_hotspot(self, item, hotspot)

	# IMPORTANTE: Controlla se è già in questa posizione
	var current_pos = inventory_tab.get_item_position(item)
	if current_pos == tl:
		print("[InventorySlot] Item already at target position %s, no move needed" % tl)
		item.mark_drop_success()
		return

	# NEW: Check for stack merging
	if _try_merge_stacks(item, tl):
		print("[InventorySlot] Successfully merged stacks")
		item.mark_drop_success()
		return

	# Piazza l'item nella nuova posizione
	var placed = inventory_tab.place_item(item, tl)

	if placed:
		print("[InventorySlot] Successfully placed item %s at %s" % [item.item_id, tl])
		item.mark_drop_success()
	else:
		print("[InventorySlot] Failed to place item %s at %s" % [item.item_id, tl])

func _is_valid_item_data(data: Variant) -> bool:
	"""Verifica che i dati del drag siano validi"""
	if typeof(data) != TYPE_DICTIONARY:
		return false
	
	var dict: Dictionary = data
	
	if not dict.has("type") or dict["type"] != "inventory_item":
		return false
	
	if not dict.has("item"):
		return false
	
	return true

# ==================== GESTIONE DEL LOCK (items multi-cella) ====================

func lock_to(item: Item) -> void:
	locked_to = item
	modulate = locked_tint

func clear() -> void:
	locked_to = null
	modulate = Color.WHITE

func is_locked() -> bool:
	return locked_to != null

# ==================== STACK MERGING ====================

func _try_merge_stacks(dragged_item: Item, target_pos: Vector2i) -> bool:
	"""Try to merge dragged item stack with existing stack at target position"""
	if not inventory_tab:
		return false

	# Get item at target position
	var target_item = inventory_tab.get_item_at(target_pos)
	if not target_item:
		return false  # No item to merge with

	# Check if items are the same type
	if dragged_item.item_id != target_item.item_id:
		return false  # Different items, can't merge

	# Check if both are stackable
	var item_data = inventory_tab._get_item_data(dragged_item.item_id)
	if not item_data:
		return false

	var is_stackable = item_data.get("stackable", false)
	if not is_stackable:
		return false  # Not stackable

	var max_stack = item_data.get("max_stack", 1)
	if max_stack <= 1:
		return false  # Stack size 1 = not stackable

	# Get current stack counts
	var dragged_count = dragged_item.stack_count if dragged_item.stack_count > 0 else 1
	var target_count = target_item.stack_count if target_item.stack_count > 0 else 1

	# Check if target stack has room
	if target_count >= max_stack:
		return false  # Target stack is full

	# Calculate how much we can merge
	var available_space = max_stack - target_count
	var amount_to_merge = mini(dragged_count, available_space)

	# Merge the stacks
	target_count += amount_to_merge
	dragged_count -= amount_to_merge

	# Update target stack count
	target_item.stack_count = target_count
	if target_item.has_method("_update_stack_label"):
		target_item._update_stack_label()

	# Handle dragged item
	if dragged_count <= 0:
		# All items merged, remove dragged item
		print("[InventorySlot] Merged all %d items into stack at %s (new count: %d)" %
			[amount_to_merge, target_pos, target_count])
		inventory_tab.remove_item(dragged_item)
		dragged_item.queue_free()
	else:
		# Partial merge, update dragged item count
		print("[InventorySlot] Partially merged %d items (dragged has %d left, target has %d)" %
			[amount_to_merge, dragged_count, target_count])
		dragged_item.stack_count = dragged_count
		if dragged_item.has_method("_update_stack_label"):
			dragged_item._update_stack_label()
		return false  # Return false so the remaining stack stays in place

	return true

# ==================== VISUAL FEEDBACK ====================

func _mouse_entered() -> void:
	if not is_locked():
		modulate = hover_tint

func _mouse_exited() -> void:
	if not is_locked():
		modulate = Color.WHITE
	else:
		modulate = locked_tint

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
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

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

func _on_mouse_entered():
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		print("[InventorySlot] 🖱️ MOUSE ENTERED slot %s (WHILE DRAGGING)" % slot_pos)
	else:
		# CRITICAL: Use get_item_occupying() to find items that occupy this slot (even if not top-left)
		if inventory_tab:
			var item_at_slot = inventory_tab.get_item_occupying(slot_pos)
			if item_at_slot and item_at_slot.has_method("_on_mouse_entered"):
				print("[InventorySlot] 📍 Forwarding mouse_entered to item %s at slot %s" % [item_at_slot.item_id, slot_pos])
				item_at_slot._on_mouse_entered()

func _on_mouse_exited():
	# CRITICAL: Use call_deferred to check if mouse truly exited the item
	# If mouse moved to another slot occupied by the same item, don't hide tooltip
	if inventory_tab:
		var item_at_slot = inventory_tab.get_item_occupying(slot_pos)
		if item_at_slot and item_at_slot.has_method("_on_mouse_exited"):
			# Defer the call to next frame to allow mouse to enter adjacent slot
			call_deferred("_deferred_mouse_exit_check", item_at_slot)

func _deferred_mouse_exit_check(item: Item) -> void:
	"""Check if mouse truly exited the item or just moved to another slot it occupies"""
	if not inventory_tab:
		return

	# Get current mouse position in grid coordinates
	var mouse_pos = get_global_mouse_position()
	var hovered_slot = _get_slot_at_mouse(mouse_pos)

	if hovered_slot != Vector2i(-1, -1):
		var item_at_hovered_slot = inventory_tab.get_item_occupying(hovered_slot)
		if item_at_hovered_slot == item:
			print("[InventorySlot] 📍 Mouse moved to another slot of same item %s, NOT hiding tooltip" % item.item_id)
			return  # Mouse is still over the same item, don't hide tooltip

	# Mouse truly exited the item
	print("[InventorySlot] 📍 Forwarding mouse_exited to item %s at slot %s" % [item.item_id, slot_pos])
	item._on_mouse_exited()

func _get_slot_at_mouse(global_pos: Vector2) -> Vector2i:
	"""Get grid position of slot at global mouse position"""
	if not inventory_tab:
		return Vector2i(-1, -1)

	# Find which slot the mouse is over
	for slot in inventory_tab.slots:
		if slot.get_global_rect().has_point(global_pos):
			return slot.slot_pos

	return Vector2i(-1, -1)

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

	# CASO 1: Check if it's a Gem being dropped
	var item_data = data.get("item_data", {})
	var item_type = item_data.get("type", "")

	if item_type == "Gem":
		print("[InventorySlot] 🔹 Gem detected (dragging: %s), checking for item at slot %s..." % [item.item_id, slot_pos])
		print("  → Mouse hover position in _can_drop_data: %s" % at_position)

		# CRITICAL: Use get_item_occupying() to find items that occupy this slot (even if not top-left)
		# This allows dropping gems on ANY slot occupied by a multi-cell weapon
		var target_item = inventory_tab.get_item_occupying(slot_pos)
		if target_item == item:
			print("[InventorySlot] ⚠️ Target is the dragged item itself, treating as empty slot")
			target_item = null

		if target_item != null:
			print("[InventorySlot] → Found item at slot: %s" % target_item.item_id)

			# SPECIAL CASE: Check if target is also a gem of the same type (stacking)
			var target_data = target_item.get_meta("item_data", {})
			var target_type = target_data.get("type", "")

			# DEBUG: Print detailed comparison
			print("[InventorySlot] 🔍 STACKING CHECK:")
			print("  - Dragged gem: %s (type: %s)" % [item.item_id, item_type])
			print("  - Target item: %s (type: %s)" % [target_item.item_id, target_type])
			print("  - Same ID? %s" % (target_item.item_id == item.item_id))
			print("  - Both Gems? target_type='%s' == 'Gem'? %s" % [target_type, target_type == "Gem"])

			if target_type == "Gem" and target_item.item_id == item.item_id:
				print("[InventorySlot] ✅ Gem-on-gem stacking detected, accepting drop")
				return true  # Accept drop for stacking
			else:
				print("[InventorySlot] ❌ NOT STACKING - Condition failed")

			# Check if target item supports gem drops (is CraftableItem)
			if target_item.has_method("_can_drop_data"):
				# Forward to target item
				var can_accept = target_item._can_drop_data(at_position, data)
				print("[InventorySlot] → Target item can accept gem: %s" % can_accept)
				return can_accept
			else:
				# Target is a regular item (not craftable) - allow swap
				print("[InventorySlot] → Target is regular item, allowing swap")
				return true  # Accept drop for swap
		else:
			# No target item - allow normal placement (continue to CASE 2)
			print("[InventorySlot] No item at slot, allowing normal gem placement")
			# Don't return false here - let it fall through to regular placement logic

	# CASO 2: Regular item placement
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
	print("[InventorySlot] 🎯 _drop_data called on slot %s, at_position: %s" % [slot_pos, at_position])

	# Pulisci l'highlight
	if inventory_tab:
		inventory_tab.clear_highlight()

	if not _is_valid_item_data(data):
		return

	var item: Item = data.get("item", null)
	if item == null:
		return

	# CASO 1: Check if it's a Gem being dropped
	var item_data = data.get("item_data", {})
	var item_type = item_data.get("type", "")

	if item_type == "Gem":
		# SPECIAL CASE: Check if we're dropping a gem ON ANOTHER GEM (stacking) or ON A WEAPON
		# CRITICAL: Use get_item_occupying() to find items at ANY slot they occupy
		print("[InventorySlot] 🔍 Checking for item occupying slot_pos: %s" % slot_pos)
		var target_item = inventory_tab.get_item_occupying(slot_pos)
		if target_item == item:
			print("[InventorySlot] ⚠️ Target is the dragged item itself, treating as empty slot")
			target_item = null

		if target_item != null:
			var target_data = target_item.get_meta("item_data", {})
			var target_type = target_data.get("type", "")

			# If target is also a gem AND same ID, try to stack instead of applying
			if target_type == "Gem" and target_item.item_id == item.item_id:
				print("[InventorySlot] 🔹 Gem-on-gem detected, attempting stack merge...")
				var hotspot: Vector2 = data.get("hotspot", Vector2.ZERO)
				var tl: Vector2i = inventory_tab.compute_top_left_from_hotspot(self, item, hotspot)

				if _try_merge_stacks(item, tl):
					print("[InventorySlot] ✅ Successfully merged gem stacks")
					item.mark_drop_success()
				else:
					print("[InventorySlot] ❌ Failed to merge gem stacks")
				return

			# Check if target item supports gem drops (is CraftableItem like weapon/armor)
			if target_item.has_method("_drop_data"):
				# Forward gem drop to target item (CraftableItem)
				print("[InventorySlot] 🔹 Forwarding gem to %s..." % target_item.item_id)
				target_item._drop_data(at_position, data)
				print("[InventorySlot] ✅ Gem forwarded to %s" % target_item.item_id)
				return  # Done - gem was applied to item
			else:
				# Target is a regular item (not craftable) - allow swap
				print("[InventorySlot] → Target is regular item, allowing swap")
				# Fall through to CASE 2 for swap logic
		else:
			# No target item - allow normal gem placement (continue to CASE 2)
			print("[InventorySlot] No target item, proceeding with normal gem placement")

	# CASO 2: Regular item placement
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
	print("[InventorySlot] 📦 _try_merge_stacks called: dragged=%s, target_pos=%s" % [dragged_item.item_id, target_pos])

	if not inventory_tab:
		print("[InventorySlot] ❌ No inventory_tab")
		return false

	# Get item at target position
	# CRITICAL: Exclude the dragged item itself (it's still in the grid during drag)
	var target_item = inventory_tab.get_item_at(target_pos)
	if target_item == dragged_item:
		print("[InventorySlot] ⚠️ Target is the dragged item itself, cannot merge with self")
		return false

	if not target_item:
		print("[InventorySlot] ❌ No item at target position %s" % target_pos)
		return false  # No item to merge with

	print("[InventorySlot] 🎯 Target item found: %s" % target_item.item_id)

	# Check if items are the same type
	if dragged_item.item_id != target_item.item_id:
		print("[InventorySlot] ❌ Different item types: %s vs %s" % [dragged_item.item_id, target_item.item_id])
		return false  # Different items, can't merge

	print("[InventorySlot] ✅ Same item type: %s" % dragged_item.item_id)

	# Check if both are stackable
	var item_data = inventory_tab._get_item_data(dragged_item.item_id)
	if not item_data:
		print("[InventorySlot] ❌ No item_data found for %s" % dragged_item.item_id)
		return false

	var is_stackable = item_data.get("stackable", false)
	if not is_stackable:
		print("[InventorySlot] ❌ Item not stackable: %s" % dragged_item.item_id)
		return false  # Not stackable

	var max_stack = item_data.get("max_stack", 1)
	if max_stack <= 1:
		print("[InventorySlot] ❌ max_stack is %d" % max_stack)
		return false  # Stack size 1 = not stackable

	print("[InventorySlot] ✅ Item is stackable, max_stack=%d" % max_stack)

	# Get current stack counts
	var dragged_count = dragged_item.stack_count if dragged_item.stack_count > 0 else 1
	var target_count = target_item.stack_count if target_item.stack_count > 0 else 1

	print("[InventorySlot] 📊 Stack counts: dragged=%d, target=%d" % [dragged_count, target_count])

	# Check if target stack has room
	if target_count >= max_stack:
		print("[InventorySlot] ❌ Target stack is full (%d/%d)" % [target_count, max_stack])
		return false  # Target stack is full

	# Calculate how much we can merge
	var available_space = max_stack - target_count
	var amount_to_merge = mini(dragged_count, available_space)

	print("[InventorySlot] ➕ Merging %d items (available space: %d)" % [amount_to_merge, available_space])

	# Merge the stacks
	target_count += amount_to_merge
	dragged_count -= amount_to_merge

	# Update target stack count
	target_item.stack_count = target_count
	if target_item.has_method("_update_stack_label"):
		target_item._update_stack_label()
		print("[InventorySlot] ✅ Updated target stack label to %d" % target_count)
	else:
		print("[InventorySlot] ⚠️ Target item has no _update_stack_label method")

	# Handle dragged item
	if dragged_count <= 0:
		# All items merged, remove dragged item
		print("[InventorySlot] Merged all %d items into stack at %s (new count: %d)" %
			[amount_to_merge, target_pos, target_count])

		# CRITICAL: Ripristina mouse filter di TUTTI gli item PRIMA di eliminare l'item draggato
		# Altrimenti gli altri item rimangono a IGNORE e non sono più draggabili!
		if dragged_item.has_method("_restore_mouse_filter"):
			dragged_item._restore_mouse_filter()

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

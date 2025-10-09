extends Panel
class_name InventorySlot

const LOG := true

var slot_pos: Vector2i = Vector2i(0, 0)
var inventory_tab: InventoryTab = null
var locked_to: Item = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Stile base dello slot
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.5)
	add_theme_stylebox_override("panel", style)
	
	if LOG:
		print("[InventorySlot] Ready at pos: %s" % slot_pos)

# ==================== SISTEMA NATIVO DI DRAG & DROP ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Chiamato da Godot quando un item viene draggato sopra questo slot"""
	print("[InventorySlot] _can_drop_data called at slot %s" % slot_pos)
	
	if not _is_valid_item_data(data):
		print("[InventorySlot] Invalid item data")
		return false
	
	if inventory_tab == null:
		if LOG:
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
	
	if LOG:
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
	modulate = Color(0.9, 0.9, 1.0)

func clear() -> void:
	locked_to = null
	modulate = Color.WHITE

func is_locked() -> bool:
	return locked_to != null

# ==================== VISUAL FEEDBACK ====================

func _mouse_entered() -> void:
	if not is_locked():
		modulate = Color(1.1, 1.1, 1.2)

func _mouse_exited() -> void:
	if not is_locked():
		modulate = Color.WHITE
	else:
		modulate = Color(0.9, 0.9, 1.0)

extends Control

# Coordinate degli slot basate sulla posizione reale nel pannello equipment
@export var slots: Dictionary = {
	"helmet": Rect2(137, 218, 64, 64),
	"weapon": Rect2(80, 230, 64, 128),
	"chest":  Rect2(137, 267, 64, 128),
	"shield": Rect2(203, 263, 64, 128),
	"belt":   Rect2(108, 378, 128, 64),
	"boots":  Rect2(134, 440, 64, 64),
}

var _hover_slot: String = ""
var _hover_rect: Rect2 = Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	print("[EquipDrop] READY - Name: %s" % name)
	print("[EquipDrop] Position: %s, Size: %s" % [position, size])
	print("[EquipDrop] Global position: %s" % global_position)
	print("[EquipDrop] Mouse filter: %s" % mouse_filter)
	
	# Forza il mouse_filter sui figli per evitare che intercettino eventi
	_fix_children_mouse_filter()
	
	for k in slots.keys():
		print("[EquipDrop]   cached slot=%s rect=%s" % [k, slots[k]])
	print("[EquipDrop] slots -> %s" % ", ".join(slots.keys()))

func _fix_children_mouse_filter() -> void:
	"""Imposta tutti i figli su IGNORE per evitare che intercettino eventi"""
	for child in get_children():
		if child is Control:
			var ctrl = child as Control
			ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			print("[EquipDrop] Set %s to IGNORE" % ctrl.name)
			_fix_children_mouse_filter_recursive(ctrl)

func _fix_children_mouse_filter_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var ctrl = child as Control
			ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			print("[EquipDrop]   Set child %s to IGNORE" % ctrl.name)
			_fix_children_mouse_filter_recursive(child)

# ==================== SISTEMA NATIVO DI DRAG & DROP ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Chiamato da Godot quando un item viene draggato sopra questo pannello"""
	print("[EquipDrop] _can_drop_data at position: %s" % at_position)
	
	if not _is_valid_item_data(data):
		print("[EquipDrop] Invalid item data")
		return false
	
	var slot := _get_slot_at(at_position)
	_hover_slot = slot
	
	if slot != "":
		_hover_rect = slots[slot]
		queue_redraw()
		print("[EquipDrop] Can drop at slot '%s': YES" % slot)
		return true
	else:
		_hover_rect = Rect2()
		queue_redraw()
		print("[EquipDrop] No valid slot at position")
		return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Chiamato da Godot quando l'item viene rilasciato su questo pannello"""
	print("[EquipDrop] _drop_data at position: %s" % at_position)
	
	var slot := _get_slot_at(at_position)
	if slot == "":
		print("[EquipDrop] No valid slot at position")
		_hover_slot = ""
		queue_redraw()
		return

	var rect: Rect2 = slots[slot]
	var item = data.get("item")
	
	if item and item is Control:
		var ctrl := item as Control
		
		# Rimuovi dal parent precedente (inventario)
		if ctrl.get_parent():
			print("[EquipDrop] Removing item from parent: %s" % ctrl.get_parent().name)
			ctrl.get_parent().remove_child(ctrl)
		
		# Aggiungi all'equipment panel
		add_child(ctrl)
		
		# Posiziona nell'equipment slot
		var final_pos := rect.position + Vector2(8, 8)
		ctrl.position = final_pos
		ctrl.z_index = 10
		
		# Marca il drop come riuscito
		if item.has_method("mark_drop_success"):
			item.mark_drop_success()
		
		print("[EquipDrop] DROPPED id=%s into slot=%s at position=%s" %
			[data.get("item_id","?"), slot, final_pos])
	else:
		print("[EquipDrop] Invalid item data")

	_hover_slot = ""
	queue_redraw()

# ==================== UTILITY FUNCTIONS ====================

func _get_slot_at(local_pos: Vector2) -> String:
	"""Trova quale slot si trova alla posizione locale"""
	for k in slots.keys():
		var r: Rect2 = slots[k]
		if r.has_point(local_pos):
			return k
	return ""

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

# ==================== RENDERING ====================

func _draw() -> void:
	# Disegna tutti gli slot
	for k in slots.keys():
		var r: Rect2 = slots[k]
		draw_rect(r, Color(0.1, 0.3, 0.5, 0.12), true)
		draw_rect(r, Color(0.3, 0.6, 1.0, 0.7), false, 2.0)
	
	# Evidenzia lo slot in hover durante il drag
	if _hover_slot != "":
		draw_rect(_hover_rect, Color(0.9, 0.9, 0.2, 0.25), true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hover_slot = ""
		queue_redraw()
